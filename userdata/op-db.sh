#!/bin/bash
# =============================================================================
# Hybrid DNS Demo — On-Premises DB Server
# VPC OP | IP: 10.2.1.30 | Hostname: db.op.viet.vn
#
# After first boot, verify with:
#   nc -zv 10.2.1.30 5432
#   PGPASSWORD=DemoPassword psql -h 10.2.1.30 -U dbadmin -d demo -c '\dt'
# =============================================================================

set -e

DB_NAME="demo"
DB_USER="dbadmin"
DB_PASSWORD="DemoPassword"
TABLE_NAME="products"

dnf update -y
dnf install -y postgresql18-server bind-utils nc

hostnamectl set-hostname db.op.viet.vn

# Initialize and start database
postgresql-setup --initdb
systemctl enable postgresql
systemctl start postgresql

# Create user, database and grant privileges
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
sudo -u postgres createdb -O ${DB_USER} ${DB_NAME}
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

# Create table and seed data
sudo -u postgres psql -d ${DB_NAME} -c "
CREATE TABLE ${TABLE_NAME} (
  id       SERIAL PRIMARY KEY,
  name     VARCHAR(255) NOT NULL,
  price    DECIMAL(10, 2),
  sku VARCHAR(50)
);"

sudo -u postgres psql -d ${DB_NAME} -c "
INSERT INTO ${TABLE_NAME} (name, price, sku) VALUES
  ('Mouse',    19.99,   50),
  ('Laptop',   2999.99,  10),
  ('Keyboard', 39.99,   30);"

sudo -u postgres psql -d ${DB_NAME} -c "
  GRANT ALL ON SCHEMA public TO ${DB_USER};
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${DB_USER};
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
  ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ${DB_USER};
"

# Configure authentication and network listening
sed -i "s/^#*listen_addresses = 'localhost'/listen_addresses = '*'/g" \
  /var/lib/pgsql/data/postgresql.conf

sed -i 's/local   all             all                                     peer/local   all             all                                     scram-sha-256/g' \
  /var/lib/pgsql/data/pg_hba.conf

sed -i 's/host    all             all             127.0.0.1\/32            ident/host    all             all             127.0.0.1\/32            scram-sha-256/g' \
  /var/lib/pgsql/data/pg_hba.conf

sed -i 's/host    all             all             ::1\/128                 ident/host    all             all             ::1\/128                 scram-sha-256/g' \
  /var/lib/pgsql/data/pg_hba.conf

sed -i '$a host    demo    dbadmin    0.0.0.0/0    md5' \
  /var/lib/pgsql/data/pg_hba.conf

systemctl restart postgresql

echo "[$(date)] DB Server setup complete."
echo "DB: ${DB_NAME} | User: ${DB_USER} | Password: ${DB_PASSWORD} | Port: 5432"
