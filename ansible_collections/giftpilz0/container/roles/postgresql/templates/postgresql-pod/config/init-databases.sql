{% for database in postgresql_databases %}
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '{{ database.user | replace("'", "''") }}') THEN
    CREATE ROLE "{{ database.user | replace('"', '""') }}" LOGIN PASSWORD '{{ database.password | replace("'", "''") }}';
  END IF;
END
$$;

SELECT 'CREATE DATABASE "{{ database.name | replace('"', '""') }}" OWNER "{{ database.user | replace('"', '""') }}"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '{{ database.name | replace("'", "''") }}')\gexec

ALTER DATABASE "{{ database.name | replace('"', '""') }}" OWNER TO "{{ database.user | replace('"', '""') }}";
{% endfor %}
