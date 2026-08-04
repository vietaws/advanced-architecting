#!/bin/bash
# =============================================================================
# Hybrid DNS Demo — On-Premises DB Server
# VPC OP | IP: 10.2.1.30 | Hostname: db.corp.local
#
# Installs PostgreSQL. Creates demo database with a products table.
#
# After first boot, verify with:
#   nc -zv 10.2.1.30 5432
#   PGPASSWORD=DemoPassword psql -h db.corp.local -U dbadmin -d demo -c '\dt'
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/userdata-db-server.log) 2>&1

echo "[$(date)] Starting DB Server setup..."

dnf update -y
dnf install -y postgresql15-server bind-utils nc

hostnamectl set-hostname db.corp.local

postgresql-setup --initdb
systemctl enable postgresql
systemctl start postgresql

# Create user and database
runuser -l postgres -c "psql -c \"CREATE USER dbadmin WITH PASSWORD 'DemoPassword';\""
runuser -l postgres -c "psql -c \"CREATE DATABASE demo OWNER dbadmin;\""

# Create schema and seed data
runuser -l postgres -c "psql -d demo -c \"CREATE TABLE IF NOT EXISTS products (id SERIAL PRIMARY KEY, name VARCHAR(100), price NUMERIC(10,2), sku VARCHAR(50));\""
runuser -l postgres -c "psql -d demo -c \"INSERT INTO products (name, price, sku) VALUES ('Mouse', 19.99, 'SKU001'), ('Laptop', 2999.99, 'SKU002'), ('Keyboard', 39.99, 'SKU003');\""
runuser -l postgres -c "psql -d demo -c \"GRANT SELECT ON products TO dbadmin;\""

# Allow password auth from 10.0.0.0/8 and listen on all interfaces
PG_DATA=$(runuser -l postgres -c "psql -t -c 'SHOW data_directory;'" | tr -d ' \n')
sed -i 's/\bident\b/md5/g' "${PG_DATA}/pg_hba.conf"
echo "host  demo  dbadmin  10.0.0.0/8  md5" >> "${PG_DATA}/pg_hba.conf"
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "${PG_DATA}/postgresql.conf"

systemctl restart postgresql

# DNS + DB test helper
cat > /usr/local/bin/dns-test << 'SCRIPT'
#!/bin/bash
echo "============================================"
echo " DNS Test — db.corp.local (10.2.1.30)"
echo "============================================"
echo ""
echo "-- Current DNS server --"
grep nameserver /etc/resolv.conf
echo ""
echo "-- On-prem records (via BIND directly @ 10.2.1.10) --"
dig @10.2.1.10 +noall +answer app.corp.local
dig @10.2.1.10 +noall +answer db.corp.local
dig @10.2.1.10 +noall +answer dns.corp.local
echo ""
echo "-- On-prem records (via configured DNS) --"
dig +noall +answer app.corp.local
dig +noall +answer db.corp.local
echo ""
echo "-- Cloud records (via configured DNS) --"
dig +noall +answer app.cloud.corp.local
echo ""
echo "-- DB self-check --"
PGPASSWORD=DemoPassword psql -h 127.0.0.1 -U dbadmin -d demo \
  -c "SELECT * FROM products;" 2>/dev/null || echo "DB not ready"
SCRIPT
chmod +x /usr/local/bin/dns-test

echo "[$(date)] DB Server setup complete."
echo "DB: demo | User: dbadmin | Password: DemoPassword | Port: 5432"
