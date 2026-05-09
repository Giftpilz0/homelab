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

log_info "Starting PostgreSQL backup daemon..."

POSTGRES_HOST=${PGHOST:-${KC_DB_URL_HOST:-localhost}}
POSTGRES_PORT=${PGPORT:-${KC_DB_URL_PORT:-5432}}
POSTGRES_DB=${PGDATABASE:-db}
POSTGRES_USER=${PGUSER:-${KC_DB_USERNAME:-postgres}}
POSTGRES_PASSWORD=${PGPASSWORD:-${KC_DB_PASSWORD}}

PGSSLMODE=${PGSSLMODE:-verify-ca}
PGSSLROOTCERT=${PGSSLROOTCERT:-/etc/ssl/certs/ca.crt}

BACKUP_SCHEDULE_HOURS=${BACKUP_SCHEDULE_HOURS:-0}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
BACKUP_COMPRESSION_LEVEL=${BACKUP_COMPRESSION_LEVEL:-6}
BACKUP_VERIFICATION_ENABLED=${BACKUP_VERIFICATION_ENABLED:-true}
BACKUP_INITIAL_BACKUP=${BACKUP_INITIAL_BACKUP:-true}
BACKUP_ON_FAILURE_RETRY_COUNT=${BACKUP_ON_FAILURE_RETRY_COUNT:-3}
BACKUP_ON_FAILURE_RETRY_DELAY=${BACKUP_ON_FAILURE_RETRY_DELAY:-30}

BACKUP_DIR=${BACKUP_DIR:-/backups}
LOCK_FILE="${BACKUP_DIR}/.backup.lock"
LOG_FILE="${BACKUP_DIR}/backup.log"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

trap 'cleanup_and_exit' EXIT INT TERM

cleanup_and_exit() {
    local exit_code=$?
    if [ -f "${LOCK_FILE}" ]; then
        rm -f "${LOCK_FILE}"
        log_info "Lock file removed"
    fi
    log_info "Backup daemon exiting with code ${exit_code}"
    exit ${exit_code}
}

acquire_lock() {
    if [ -f "${LOCK_FILE}" ]; then
        local lock_age=$(( $(date +%s) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo 0) ))
        if [ ${lock_age} -gt 7200 ]; then
            log_warn "Stale lock file found (${lock_age}s old), removing it"
            rm -f "${LOCK_FILE}"
        else
            log_error "Backup already in progress (lock file exists)"
            return 1
        fi
    fi
    touch "${LOCK_FILE}"
    return 0
}

check_dependencies() {
    local missing_deps=""
    for cmd in pg_dump pg_restore pg_isready sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="${missing_deps} ${cmd}"
        fi
    done

    if [ -n "${missing_deps}" ]; then
        log_error "Missing required dependencies:${missing_deps}"
        return 1
    fi
    return 0
}

wait_for_postgres() {
    local max_wait=300
    local wait_interval=5
    local waited=0

    log_info "Waiting for PostgreSQL to be ready..."

    while [ ${waited} -lt ${max_wait} ]; do
        if PGPASSWORD="${POSTGRES_PASSWORD}" pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -q 2>/dev/null; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        sleep ${wait_interval}
        waited=$((waited + wait_interval))
        log_info "Still waiting for PostgreSQL (${waited}/${max_wait}s)..."
    done

    log_error "PostgreSQL did not become ready within ${max_wait} seconds"
    return 1
}

verify_backup() {
    local backup_file=$1

    log_info "Verifying backup integrity..."

    if ! pg_restore -l "${backup_file}" > /dev/null 2>&1; then
        log_error "Backup verification failed - file may be corrupted"
        return 1
    fi

    if [ -f "${backup_file}.sha256" ]; then
        if ! sha256sum -c "${backup_file}.sha256" > /dev/null 2>&1; then
            log_error "Checksum verification failed"
            return 1
        fi
        log_info "Checksum verification: PASSED"
    fi

    log_info "Backup verification: PASSED"
    return 0
}

generate_metadata() {
    local backup_file=$1
    local metadata_file="${backup_file}.meta"

    cat > "${metadata_file}" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "database": "${POSTGRES_DB}",
  "host": "${POSTGRES_HOST}",
  "port": "${POSTGRES_PORT}",
  "user": "${POSTGRES_USER}",
  "compression_level": "${BACKUP_COMPRESSION_LEVEL}",
  "size_bytes": "$(stat -c %s "${backup_file}" 2>/dev/null || echo 0)",
  "size_human": "$(du -h "${backup_file}" 2>/dev/null | cut -f1 || echo unknown)",
  "checksum": "$(sha256sum "${backup_file}" 2>/dev/null | cut -d ' ' -f1 || echo unknown)"
}
EOF
}

perform_backup() {
    local timestamp
    local backup_file
    local backup_path
    local retry_count=0
    local start_time end_time duration

    if ! acquire_lock; then
        return 1
    fi

    start_time=$(date +%s)
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="${POSTGRES_DB}_backup_${timestamp}.dump"
    backup_path="${BACKUP_DIR}/${backup_file}"

    log_info "Starting backup: ${backup_file}"
    log_info "Database: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    log_info "Backup path: ${backup_path}"
    log_info "Compression level: ${BACKUP_COMPRESSION_LEVEL}"

    if ! wait_for_postgres; then
        return 1
    fi

    while [ ${retry_count} -le ${BACKUP_ON_FAILURE_RETRY_COUNT} ]; do
        log_info "Creating backup dump (attempt $((retry_count + 1))/${BACKUP_ON_FAILURE_RETRY_COUNT})..."

        if PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
            -h "${POSTGRES_HOST}" \
            -p "${POSTGRES_PORT}" \
            -U "${POSTGRES_USER}" \
            -d "${POSTGRES_DB}" \
            -F c \
            -Z "${BACKUP_COMPRESSION_LEVEL}" \
            -f "${backup_path}" \
            --no-password 2>/dev/null; then

            break
        else
            retry_count=$((retry_count + 1))
            if [ ${retry_count} -le ${BACKUP_ON_FAILURE_RETRY_COUNT} ]; then
                log_warn "Backup creation failed, retrying in ${BACKUP_ON_FAILURE_RETRY_DELAY}s..."
                sleep ${BACKUP_ON_FAILURE_RETRY_DELAY}
                rm -f "${backup_path}"
            else
                log_error "Backup creation failed after ${retry_count} attempts"
                rm -f "${backup_path}"
                rm -f "${LOCK_FILE}"
                return 1
            fi
        fi
    done

    local backup_size=$(du -h "${backup_path}" | cut -f1)
    log_info "Backup created: ${backup_size}"

    if [ "${BACKUP_VERIFICATION_ENABLED}" = "true" ]; then
        if ! verify_backup "${backup_path}"; then
            log_error "Backup verification failed, removing corrupted file"
            rm -f "${backup_path}"
            rm -f "${LOCK_FILE}"
            return 1
        fi
    fi

    log_info "Generating checksum and metadata..."
    sha256sum "${BACKUP_DIR}/${backup_file}" > "${backup_path}.sha256"
    generate_metadata "${backup_path}"

    cleanup_old_backups
    list_backups_summary

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    log_info "Backup completed successfully in ${duration}s"
    rm -f "${LOCK_FILE}"
    return 0
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: ${BACKUP_RETENTION_DAYS} days)..."

    local deleted_count=0
    local freed_space=0

    for file_pattern in "${BACKUP_DIR}"/${POSTGRES_DB}_backup_*.{dump,sha256,meta}; do
        for file in $file_pattern; do
            if [ -f "${file}" ]; then
                local file_age=$(( ($(date +%s) - $(stat -c %Y "${file}")) / 86400 ))
                if [ ${file_age} -gt ${BACKUP_RETENTION_DAYS} ]; then
                    local file_size=$(stat -c %s "${file}" 2>/dev/null || echo 0)
                    rm -f "${file}"
                    deleted_count=$((deleted_count + 1))
                    freed_size=$((freed_size + file_size))
                fi
            fi
        done
    done

    if [ ${deleted_count} -gt 0 ]; then
        log_info "Deleted ${deleted_count} old backup files ($(numfmt --to=iec-i --suffix=B ${freed_size} 2>/dev/null || echo "${freed_size} bytes"))"
    fi
}

list_backups_summary() {
    local backup_count=$(find "${BACKUP_DIR}" -name "${POSTGRES_DB}_backup_*.dump" -type f | wc -l)
    local total_size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "unknown")
    local latest_backup=$(find "${BACKUP_DIR}" -name "${POSTGRES_DB}_backup_*.dump" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d ' ' -f2- | xargs basename 2>/dev/null || echo "none")

    log_info "Backup summary: ${backup_count} backups, ${total_size} total"
    log_info "Latest backup: ${latest_backup}"
}

list_backups() {
    log_info "Current backups in ${BACKUP_DIR}:"
    find "${BACKUP_DIR}" -name "${POSTGRES_DB}_backup_*.dump" -type f -printf '%T+ %s %p\n' 2>/dev/null | sort -r | while read -r timestamp size path; do
        local size_human=$(numfmt --to=iec-i --suffix=B ${size} 2>/dev/null || echo "${size}B")
        local basename_file=$(basename "${path}")
        printf "  %-30s %10s  %s\n" "${basename_file}" "${size_human}" "${timestamp}"
    done
}

show_configuration() {
    log_info "Backup daemon configuration:"
    log_info "  PostgreSQL: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    log_info "  Schedule: Every ${BACKUP_SCHEDULE_HOURS} hour(s)"
    log_info "  Retention: ${BACKUP_RETENTION_DAYS} day(s)"
    log_info "  Compression level: ${BACKUP_COMPRESSION_LEVEL}"
    log_info "  Verification: ${BACKUP_VERIFICATION_ENABLED}"
    log_info "  Initial backup: ${BACKUP_INITIAL_BACKUP}"
    log_info "  Retry on failure: ${BACKUP_ON_FAILURE_RETRY_COUNT} attempts with ${BACKUP_ON_FAILURE_RETRY_DELAY}s delay"
    log_info "  Backup directory: ${BACKUP_DIR}"
}

main() {
    if ! check_dependencies; then
        exit 1
    fi

    show_configuration

    if [ "${BACKUP_INITIAL_BACKUP}" = "true" ]; then
        log_info "Performing initial backup..."
        perform_backup
    else
        list_backups
    fi

    if [ "${BACKUP_SCHEDULE_HOURS}" -eq 0 ]; then
        log_info "Backup schedule is set to 0, initial backup completed and daemon will exit"
        exit 0
    fi

    log_info "Entering backup loop (next backup in ${BACKUP_SCHEDULE_HOURS} hour(s))..."

    while true; do
        local sleep_seconds=$((BACKUP_SCHEDULE_HOURS * 3600))
        local sleep_end=$(( $(date +%s) + sleep_seconds ))

        log_info "Next scheduled backup: $(date -d @${sleep_end} '+%Y-%m-%d %H:%M:%S')"

        while [ $(date +%s) -lt ${sleep_end} ]; do
            local remaining=$((sleep_end - $(date +%s)))
            if [ ${remaining} -le 60 ]; then
                sleep ${remaining}
            else
                sleep 60
            fi
        done

        perform_backup
        list_backups
    done
}

main
