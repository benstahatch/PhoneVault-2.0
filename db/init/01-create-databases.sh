#!/bin/bash
set -e
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}_test\`;
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
-- covers the _test database and production's _cache, _queue, and _cable databases
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\_%\`.* TO '${MYSQL_USER}'@'%';
EOSQL
