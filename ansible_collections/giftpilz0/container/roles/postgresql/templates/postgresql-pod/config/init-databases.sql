{% for user in postgresql_users | default([]) %}
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '{{ user.name | replace("'", "''") }}') THEN
    CREATE ROLE "{{ user.name | replace('"', '""') }}" LOGIN PASSWORD '{{ user.password | replace("'", "''") }}';
  END IF;
END
$$;
{% endfor %}

{% for database in postgresql_databases %}
SELECT 'CREATE DATABASE "{{ database.name | replace('"', '""') }}" OWNER "{{ database.owner | replace('"', '""') }}"'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '{{ database.name | replace("'", "''") }}')\gexec

ALTER DATABASE "{{ database.name | replace('"', '""') }}" OWNER TO "{{ database.owner | replace('"', '""') }}";
{% endfor %}
