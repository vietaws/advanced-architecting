#!/bin/bash
set -e

# Variables - UPDATE THESE
AWS_REGION="ap-southeast-1"
DYNAMODB_PRODUCTS_TABLE="products_table"
DYNAMODB_ORDERS_TABLE="orders_table"
DAX_ENDPOINT="daxs://dax-demo.wfcknw.dax-clusters.ap-southeast-1.amazonaws.com"
S3_BUCKET="demo-product-images-91841967" # Your S3 bucket name
SQS_QUEUE_URL="https://sqs.ap-southeast-1.amazonaws.com/274595021951/orders"
RDS_HOST="database-demo.cluster-crkedvynyebh.ap-southeast-1.rds.amazonaws.com" # store providers data
RDS_PORT="5432"
RDS_DATABASE="providers_db"
RDS_USER="dbadmin"
RDS_PASSWORD="YourPassword"
PGPASSWORD=$RDS_PASSWORD

# Update system
dnf update -y

# Install Node.js 22, Git, PostgreSQL, and EFS utilities
dnf install -y nodejs22 git postgresql17 amazon-efs-utils

# Fix for EFS mount issue
# EFS_ID="fs-04d1e5b35d2c67bd7"  # Your EFS File System ID
# MOUNT_POINT="/data/efs"
# echo "Setting up EFS"
# mkdir -p $MOUNT_POINT
# echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ $MOUNT_POINT efs _netdev,tls,iam 0 0" >> /etc/fstab
# mount -a
# chmod 755 $MOUNT_POINT
# chown ec2-user:ec2-user $MOUNT_POINT

# Clone application from GitHub
cd /home/ec2-user
git clone -b appmod https://github.com/vietaws/architecting-pro.git
cd architecting-pro


# Create .env file
cat > .env <<EOF
PORT=3001
NODE_ENV=development
LOG_LEVEL=info
AWS_REGION=${AWS_REGION}
DYNAMODB_PRODUCTS_TABLE=${DYNAMODB_PRODUCTS_TABLE}
DYNAMODB_ORDERS_TABLE=${DYNAMODB_ORDERS_TABLE}
DAX_ENDPOINT=${DAX_ENDPOINT}
RDS_HOST=${RDS_HOST}
RDS_PORT=${RDS_PORT}
RDS_DATABASE=${RDS_DATABASE}
RDS_USER=${RDS_USER}
RDS_PASSWORD=${RDS_PASSWORD}
S3_BUCKET=${S3_BUCKET}
SQS_QUEUE_URL=${SQS_QUEUE_URL}
EOF

# Install dependencies
npm install

# Set ownership
chown -R ec2-user:ec2-user /home/ec2-user/architecting-pro

# Create systemd service
cat > /etc/systemd/system/demo-app.service <<'EOFS'
[Unit]
Description=AWS Architecting Pro Demo Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/architecting-pro
EnvironmentFile=/home/ec2-user/architecting-pro/.env
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

# See logs
# sudo journalctl -u demo-app -n 100
# sudo journalctl -u demo-app -f
