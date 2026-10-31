{% for database in mariadb_databases %}
CREATE DATABASE IF NOT EXISTS `{{ database.name | replace('`', '``') }}`;
CREATE USER IF NOT EXISTS '{{ database.user | replace("'", "''") }}'@'%' IDENTIFIED BY '{{ database.password | replace("'", "''") }}';
GRANT ALL PRIVILEGES ON `{{ database.name | replace('`', '``') }}`.* TO '{{ database.user | replace("'", "''") }}'@'%';
{% endfor %}
FLUSH PRIVILEGES;
