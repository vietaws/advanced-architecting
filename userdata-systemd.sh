#!/bin/bash
set -e

# Variables - UPDATE THESE
EFS_ID="fs-0df1a5706ceb8608f"  # Your EFS File System ID
MOUNT_POINT="/data/efs"
AWS_REGION="us-east-1"
DYNAMODB_PRODUCTS_TABLE="products_table"
DYNAMODB_ORDERS_TABLE="orders_table"
DAX_ENDPOINT="dax-demo.wfcknw.dax-clusters.us-east-1.amazonaws.com:8111"
S3_BUCKET="demo-product-images-123456"
SQS_QUEUE_URL="https://sqs.us-east-1.amazonaws.com/916495840179/orders"
RDS_HOST="database-2.cluster-crkedvynyebh.us-east-1.rds.amazonaws.com" # store providers data
RDS_PORT="5432"
RDS_DATABASE="providers_db"
RDS_USER="dbadmin"
RDS_PASSWORD="YourPassword"
PGPASSWORD=$RDS_PASSWORD

# Update system
dnf update -y

# Install Node.js 22, Git, PostgreSQL, and EFS utilities
dnf install -y nodejs22 git postgresql17 amazon-efs-utils

# Setup EFS mount
echo "Setting up EFS"
mkdir -p $MOUNT_POINT

# nslookup $EFS_ID.efs.$AWS_REGION.amazonaws.com
# mount -t efs -o tls fs-0df1a5706ceb8608f.efs.us-east-1.amazonaws.com:/ $MOUNT_POINT
# mount -t efs -o tls fs-0df1a5706ceb8608f:/ efs

echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ $MOUNT_POINT efs _netdev,tls,iam 0 0" >> /etc/fstab
mount -a
chmod 777 $MOUNT_POINT

# Clone application from GitHub
cd /home/ec2-user
git clone https://github.com/vietaws/advanced-architecting.git
cd advanced-architecting

# Run the SQL script
psql -h $RDS_HOST -U $RDS_USER -d $RDS_DATABASE -f setup.sql || true

# Unset password
unset PGPASSWORD

# Create config file
cat > app_config.json <<EOF
{
  "dynamodb": {
    "region": "${AWS_REGION}",
    "productsTableName": "${DYNAMODB_PRODUCTS_TABLE}",
    "ordersTableName": "${DYNAMODB_ORDERS_TABLE}"
  },
  "dax": {
    "endpoint": "${DAX_ENDPOINT}"
  },
  "rds": {
    "host": "${RDS_HOST}",
    "port": ${RDS_PORT},
    "database": "${RDS_DATABASE}",
    "user": "${RDS_USER}",
    "password": "${RDS_PASSWORD}"
  },
  "s3": {
    "region": "${AWS_REGION}",
    "bucketName": "${S3_BUCKET}"
  },
  "sqs": {
    "region": "${AWS_REGION}",
    "queueUrl": "${SQS_QUEUE_URL}"
  },
  "server": {
    "port": 3000
  }
}
EOF

# Install dependencies
npm install

# Set ownership
chown -R ec2-user:ec2-user /home/ec2-user/advanced-architecting

# Create systemd service
cat > /etc/systemd/system/demo-app.service <<'EOFS'
[Unit]
Description=Product Provider Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/advanced-architecting
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=demo-app

[Install]
WantedBy=multi-user.target
EOFS

# Enable and start service
systemctl daemon-reload
systemctl enable demo-app
systemctl start demo-app

# Wait for app to start
sleep 5

# Check status
systemctl status demo-app --no-pager
