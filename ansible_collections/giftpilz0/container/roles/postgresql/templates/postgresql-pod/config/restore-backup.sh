#!/bin/sh

set -eu

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

show_usage() {
    cat << EOF
PostgreSQL Backup Restore Script

Usage: $0 [OPTIONS] <backup-file>

Options:
  -l, --list              List available backups and exit
  -v, --verify-only       Verify backup integrity without restoring
  -y, --yes               Skip confirmation prompts
  -f, --force             Force restore even if database is active
  -c, --create-db-only    Create database without restoring data
  --dry-run               Show what would be done without making changes
  -h, --help              Show this help message

Arguments:
  <backup-file>           Path to the backup file (.dump file)

Environment Variables:
  PGHOST                  PostgreSQL host (default: localhost)
  PGPORT                  PostgreSQL port (default: 5432)
  PGDATABASE              Database name (default: db)
  PGUSER                  PostgreSQL user (default: postgres)
  PGPASSWORD              PostgreSQL password

Examples:
  $0 --list
  $0 ${POSTGRES_DB}_backup_20250203_120000.dump
  $0 -y ${POSTGRES_DB}_backup_20250203_120000.dump
  $0 --verify-only ${POSTGRES_DB}_backup_20250203_120000.dump

EOF
    exit 0
}

list_backups() {
    local backup_dir=${BACKUP_DIR:-/backups}

    log_info "Available backups in ${backup_dir}:"
    echo ""

    if [ ! -d "${backup_dir}" ]; then
        log_error "Backup directory not found: ${backup_dir}"
        exit 1
    fi

    local found=false
    find "${backup_dir}" -name "${POSTGRES_DB}_backup_*.dump" -type f -printf '%T@ %s %p\n' 2>/dev/null | sort -rn | while read -r timestamp size path; do
        found=true
        local size_human=$(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size}B")
        local basename_file=$(basename "${path}")
        local meta_file="${path%.dump}.meta"
        local db_name="unknown"
        local backup_date=$(date -d @${timestamp} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")

        if [ -f "${meta_file}" ]; then
            db_name=$(grep -oP '"database":\s*"\K[^"]+' "${meta_file}" 2>/dev/null || echo "unknown")
        fi

        printf "  %-30s %10s  %-20s  %s\n" "${basename_file}" "${size_human}" "${db_name}" "${backup_date}"
    done

    if [ "${found}" = false ]; then
        log_warn "No backups found in ${backup_dir}"
        exit 1
    fi
}

verify_backup() {
    local backup_file=$1

    log_info "Verifying backup file: ${backup_file}"

    if [ ! -f "${backup_file}" ]; then
        log_error "Backup file not found: ${backup_file}"
        return 1
    fi

    log_info "Checking file integrity with pg_restore..."
    if ! pg_restore -l "${backup_file}" > /dev/null 2>&1; then
        log_error "Backup file is corrupted or invalid"
        return 1
    fi

    local sha256_file="${backup_file}.sha256"
    if [ -f "${sha256_file}" ]; then
        log_info "Verifying SHA256 checksum..."
        if ! sha256sum -c "${sha256_file}" > /dev/null 2>&1; then
            log_error "Checksum verification failed"
            return 1
        fi
        log_info "Checksum verification: PASSED"
    else
        log_warn "SHA256 checksum file not found, skipping checksum verification"
    fi

    local meta_file="${backup_file%.dump}.meta"
    if [ -f "${meta_file}" ]; then
        log_info "Backup metadata:"
        cat "${meta_file}" | grep -E '(version|timestamp|database|size_human)' | sed 's/^/  /'
    fi

    log_info "Backup verification: PASSED"
    return 0
}

check_dependencies() {
    for cmd in pg_restore pg_dump dropdb createdb psql pg_isready; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing required dependency: $cmd"
            return 1
        fi
    done
    return 0
}

check_database_connections() {
    local db_name=$1

    log_info "Checking for active connections to database '${db_name}'..."

    local active_connections
    active_connections=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -t -c "SELECT count(*) FROM pg_stat_activity WHERE datname = '${db_name}' AND state != 'idle';" 2>/dev/null | tr -d ' ')

    if [ -n "${active_connections}" ] && [ "${active_connections}" -gt 0 ]; then
        log_warn "Found ${active_connections} active connection(s) to database '${db_name}'"
        return 1
    fi

    return 0
}

wait_for_postgres() {
    local max_wait=60
    local wait_interval=2
    local waited=0

    log_info "Waiting for PostgreSQL to be ready..."

    while [ ${waited} -lt ${max_wait} ]; do
        if PGPASSWORD="${POSTGRES_PASSWORD}" pg_isready \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -q 2>/dev/null; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        sleep ${wait_interval}
        waited=$((waited + wait_interval))
    done

    log_error "PostgreSQL did not become ready within ${max_wait} seconds"
    return 1
}

backup_existing_database() {
    local db_name=$1
    local timestamp
    local backup_path

    log_info "Creating pre-restore backup of existing database..."

    if PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "SELECT 1 FROM pg_database WHERE datname = '${db_name}'" 2>/dev/null | grep -q 1; then

        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_path="${BACKUP_DIR}/pre_restore_${db_name}_${timestamp}.dump"

        log_info "Backing up existing database to: ${backup_path}"

        if PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -d "${db_name}" \
            -F c \
            -Z 6 \
            -f "${backup_path}" \
            --no-password 2>/dev/null; then

            sha256sum "${backup_path}" > "${backup_path}.sha256"
            local backup_size=$(du -h "${backup_path}" | cut -f1)
            log_info "Pre-restore backup created: ${backup_size}"
            echo "${backup_path}"
        else
            log_error "Failed to create pre-restore backup"
            return 1
        fi
    else
        log_info "Database '${db_name}' does not exist, skipping pre-restore backup"
    fi

    return 0
}

restore_database() {
    local backup_file=$1
    local pre_restore_backup=$2
    local restore_start restore_end duration
    local table_count

    restore_start=$(date +%s)

    log_info "Starting database restoration..."

    if ! PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" 2>/dev/null | grep -q 1; then

        log_info "Database '${POSTGRES_DB}' does not exist, creating it..."
        PGPASSWORD="${POSTGRES_PASSWORD}" createdb \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            "${POSTGRES_DB}"
    else
        log_info "Dropping existing database '${POSTGRES_DB}'..."
        PGPASSWORD="${POSTGRES_PASSWORD}" dropdb \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            "${POSTGRES_DB}"
    fi

    log_info "Recreating database '${POSTGRES_DB}'..."
    PGPASSWORD="${POSTGRES_PASSWORD}" createdb \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        "${POSTGRES_DB}"

    log_info "Restoring data from backup..."
    if ! PGPASSWORD="${POSTGRES_PASSWORD}" pg_restore \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -j 2 \
        -v \
        "${backup_file}" 2>&1 | while read -r line; do
            case "$line" in
                *PROCESSING*) echo "[INFO] $line" | sed 's/pg_restore: //';;
                *ERROR*) echo "[ERROR] $line" >&2;;
            esac
        done; then

        log_error "Database restoration failed!"
        if [ -n "${pre_restore_backup}" ] && [ -f "${pre_restore_backup}" ]; then
            log_warn "Attempting to restore from pre-restore backup: ${pre_restore_backup}"
            PGPASSWORD="${POSTGRES_PASSWORD}" dropdb -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>/dev/null || true
            PGPASSWORD="${POSTGRES_PASSWORD}" createdb -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" "${POSTGRES_DB}"
            PGPASSWORD="${POSTGRES_PASSWORD}" pg_restore \
                -h "${POSTGRES_HOST}" \
                -p "${POSTGRES_PORT}" \
                -U "${POSTGRES_USER}" \
                -d "${POSTGRES_DB}" \
                -j 2 \
                "${pre_restore_backup}" 2>/dev/null || true
        fi
        return 1
    fi

    table_count=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')

    restore_end=$(date +%s)
    duration=$((restore_end - restore_start))

    log_info "Database restoration completed successfully!"
    log_info "Tables restored: ${table_count}"
    log_info "Duration: ${duration}s"

    return 0
}

LIST_ONLY=false
VERIFY_ONLY=false
SKIP_CONFIRMATION=false
FORCE=false
CREATE_DB_ONLY=false
DRY_RUN=false
BACKUP_FILE=""
BACKUP_DIR=${BACKUP_DIR:-/backups}

while [ $# -gt 0 ]; do
    case "$1" in
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -v|--verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -c|--create-db-only)
            CREATE_DB_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

POSTGRES_HOST=${PGHOST:-${KC_DB_URL_HOST:-localhost}}
POSTGRES_PORT=${PGPORT:-${KC_DB_URL_PORT:-5432}}
POSTGRES_DB=${PGDATABASE:-db}
POSTGRES_USER=${PGUSER:-${KC_DB_USERNAME:-postgres}}
POSTGRES_PASSWORD=${PGPASSWORD:-${KC_DB_PASSWORD}}

PGSSLMODE=${PGSSLMODE:-verify-ca}
PGSSLROOTCERT=${PGSSLROOTCERT:-/etc/ssl/certs/ca.crt}

if [ "${LIST_ONLY}" = true ]; then
    list_backups
    exit 0
fi

if [ -z "${BACKUP_FILE}" ]; then
    log_error "No backup file specified"
    show_usage
fi

if [ "${BACKUP_FILE##*/}" = "${BACKUP_FILE}" ]; then
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
fi

if [ "${BACKUP_FILE##*.}" != "dump" ]; then
    log_error "Backup file must have .dump extension"
    exit 1
fi

if [ "${DRY_RUN}" = true ]; then
    log_info "DRY RUN MODE - No changes will be made"
    log_info "Would restore from: ${BACKUP_FILE}"
    log_info "Target database: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    verify_backup "${BACKUP_FILE}"
    exit 0
fi

if ! check_dependencies; then
    exit 1
fi

if ! verify_backup "${BACKUP_FILE}"; then
    exit 1
fi

if [ "${VERIFY_ONLY}" = true ]; then
    log_info "Verification complete, exiting without restoring"
    exit 0
fi

log_info "Restore operation details:"
log_info "  Backup file: ${BACKUP_FILE}"
log_info "  Target: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
log_info ""
log_warn "WARNING: This will completely overwrite the database '${POSTGRES_DB}'!"
log_warn "All existing data will be permanently lost!"
log_warn ""

if [ "${FORCE}" = false ]; then
    check_database_connections "${POSTGRES_DB}"
    if [ $? -ne 0 ]; then
        log_error "Database has active connections. Use --force to proceed anyway."
        exit 1
    fi
fi

if [ "${SKIP_CONFIRMATION}" = false ]; then
    echo ""
    echo "Press Ctrl+C to cancel, or wait for countdown to proceed..."
    for i in 10 9 8 7 6 5 4 3 2 1; do
        echo -ne "\rRestoring in ${i} seconds... "
        sleep 1
    done
    echo -ne "\rRestoring now...        \n"
fi

if ! wait_for_postgres; then
    exit 1
fi

pre_restore_backup=""
if [ "${CREATE_DB_ONLY}" = false ]; then
    pre_restore_backup=$(backup_existing_database "${POSTGRES_DB}")
fi

if [ "${CREATE_DB_ONLY}" = true ]; then
    if ! PGPASSWORD="${POSTGRES_PASSWORD}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -c "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" 2>/dev/null | grep -q 1; then

        log_info "Creating database '${POSTGRES_DB}'..."
        PGPASSWORD="${POSTGRES_PASSWORD}" createdb \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            "${POSTGRES_DB}"
        log_info "Database created successfully"
    else
        log_info "Database '${POSTGRES_DB}' already exists"
    fi
else
    if ! restore_database "${BACKUP_FILE}" "${pre_restore_backup}"; then
        exit 1
    fi
fi

log_info "Restore operation completed successfully!"
