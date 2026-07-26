# Product-Provider Management Application

## Architecture
- **Application Tier**: Node.js on EC2 with Auto Scaling
- **Load Balancer**: Application Load Balancer (ALB)
- **Databases**: 
  - DynamoDB: `products_table` (products), `orders_table` (orders)
  - RDS PostgreSQL: `providers_db` (providers)
- **Storage**: S3 (product images), EFS (shared images)
- **Queue**: SQS (order processing)

## Setup Instructions

### 1. Prerequisites
- EC2 instance with Node.js installed
- IAM role attached to EC2 with policies:
  - `AmazonDynamoDBFullAccess`
  - `AmazonS3FullAccess`
  - `AmazonSQSFullAccess`

- VPC Setup:
  - VPC name: `lab-vpc`
  - CIDR: `10.1.0.0/16`
  - public subnets (public-1 and public-2): `10.1.1.0/24` and `10.1.2.0/24`
  - app subnets (app-1 and app-2): `10.1.3.0/24` and `10.1.4.0/24`
  - db subnets (db-1 and db-2): `10.1.5.0/24` and `10.1.6.0/24`

- Firewall setup
  - Public Security group: `public-sg`
  - ELB Security group: `elb-sg`
  - APP Security group: `app-sg`
  - DB Security group: `db-sg`
  - NACL: allow all inbound/outbound

### 2. Database Setup

**DynamoDB Tables:**
```bash
# Products table
aws dynamodb create-table \
  --table-name products_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1

# Orders table
aws dynamodb create-table \
  --table-name orders_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1

# Create S3 Image Bucket - Linux / macOS
aws s3api create-bucket \
    --bucket "demo-product-images-$(openssl rand -hex 4)"

aws s3 mb s3://demo-product-images-$(openssl rand -hex 4)

# Create S3 Image Bucket - Windows PowerShell with GUID
$suffix = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
aws s3 mb s3://demo-product-images-$suffix --region ap-southeast-1

# Create DB Subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name demo-aurora-subnet-group \
  --db-subnet-group-description "Architecting Pro subnet group" \
  --subnet-ids subnet-xxxxxxxxx subnet-yyyyyyyyy

# Create RDS Aurora 
aws rds create-db-cluster \
  --db-cluster-identifier demo-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username dbadmin \
  --master-user-password YourPassword \
  --db-subnet-group-name demo-aurora-subnet-group \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=1 \
  --database-name products_db \
  --no-deletion-protection

aws rds create-db-instance \
    --db-instance-identifier demo-aurora-instance \
    --db-cluster-identifier demo-aurora-cluster \
    --db-instance-class db.serverless \
    --engine aurora-postgresql \
    --no-publicly-accessible
```

**RDS PostgreSQL:**
Connect to your RDS instance and run:
```bash
psql -h db.viet.vn -U dbadmin -d products_db

\dt;

CREATE TABLE IF NOT EXISTS providers (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  city VARCHAR(100)
);

SELECT * FROM providers;

INSERT INTO providers (name, city) VALUES
  ('Acme Supplies', 'Ho Chi Minh City'),
  ('Miracle Tech', 'Hanoi'),
  ('One Training', 'Da Nang');
```

**S3 Bucket:**
```bash
aws s3 mb s3://demo_product_images_bucket
```

### 3. Application Deployment

Update `userdata.sh` with your actual credentials and endpoints.

Install dependencies and start:
```bash
npm install
npm start
```

Access the web interface at: `http://<EC2-Public-IP>:3000`

### 4. Auto Scaling Configuration

Create Launch Template with:
- AMI with Node.js and application code
- IAM role with DynamoDB and S3 permissions
- User data script to start application

Create Auto Scaling Group:
- Min: 2, Max: 10, Desired: 2
- Target tracking policy (CPU 70%)
- Attach to ALB target group

### 5. ALB Setup

- Create ALB with target group (port 3000)
- Health check: `/health`
- Register Auto Scaling Group

### 6. EC2 Security Group

Ensure your EC2 security group allows:
- Port 3001 (from ALB or 0.0.0.0/0 for testing)

### 7. Quick Deploy to EC2

```bash
# SSH to EC2
ssh -i your-key.pem ec2-user@<EC2-IP>

# Install Node.js
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs git

# Clone/upload your application
git clone <your-repo> || scp -r ./architecting ec2-user@<EC2-IP>:~

# Navigate and install
cd architecting
npm install

# Start application (use PM2 for production)
npm start

# Or with PM2 for auto-restart
sudo npm install -g pm2
pm2 start server.js --name product-app
pm2 startup
pm2 save
```

## API Endpoints

**Products (DynamoDB):**
- `POST /products` - Create product
- `GET /products` - List all products
- `GET /products/:id` - Get product by ID
- `PUT /products/:id` - Update product
- `DELETE /products/:id` - Delete product

**Providers (RDS PostgreSQL):**
- `POST /providers` - Create provider
- `GET /providers` - List all providers
- `GET /providers/:id` - Get provider by ID
- `PUT /providers/:id` - Update provider
- `DELETE /providers/:id` - Delete provider

## Configuration

All connection parameters are in `app_config.json`:
- DynamoDB region and table name
- RDS PostgreSQL connection details
- S3 bucket name and region
- Server port
