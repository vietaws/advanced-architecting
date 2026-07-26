## End-to-End Encryption in Transit

### Architecture Options

Option 1: Network Load Balancer (NLB) - True End-to-End Encryption
Client → HTTPS (TLS) → NLB (passthrough) → HTTPS (TLS) → EC2
        └─────────────────────────────────────────────┘
                    Encrypted end-to-end


Option 2: Application Load Balancer (ALB) - Re-encryption
Client → HTTPS (TLS) → ALB (decrypt) → HTTPS (TLS) → EC2
        └──────────────┘ ALB sees traffic └──────────┘


For true end-to-end encryption, use Network Load Balancer (NLB).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation: NLB with End-to-End Encryption

### Step 1: Obtain SSL/TLS Certificate

Option A: AWS Certificate Manager (ACM) - Free
bash
# Request certificate
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names www.example.com \
  --validation-method DNS

# Get certificate ARN
aws acm list-certificates


Option B: Import Existing Certificate
bash
aws acm import-certificate \
  --certificate fileb://certificate.crt \
  --private-key fileb://private.key \
  --certificate-chain fileb://chain.crt


### Step 2: Create Network Load Balancer

bash
# Create NLB
aws elbv2 create-load-balancer \
  --name my-nlb \
  --type network \
  --scheme internet-facing \
  --subnets subnet-xxxxx subnet-yyyyy \
  --tags Key=Name,Value=my-nlb

# Get NLB ARN
NLB_ARN=$(aws elbv2 describe-load-balancers \
  --names my-nlb \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)


### Step 3: Create Target Group

bash
# Create target group for HTTPS (port 443)
aws elbv2 create-target-group \
  --name my-https-targets \
  --protocol TLS \
  --port 443 \
  --vpc-id vpc-xxxxx \
  --target-type instance \
  --health-check-protocol HTTPS \
  --health-check-path /health \
  --health-check-interval-seconds 30

# Get target group ARN
TG_ARN=$(aws elbv2 describe-target-groups \
  --names my-https-targets \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)


### Step 4: Create NLB Listener (TLS Passthrough)

bash
# Create TLS listener with passthrough
aws elbv2 create-listener \
  --load-balancer-arn $NLB_ARN \
  --protocol TLS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:us-east-1:ACCOUNT:certificate/xxxxx \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN


### Step 5: Configure EC2 Instances with SSL/TLS

#### Install Nginx on EC2

bash
# SSH into EC2
ssh ec2-user@your-ec2-ip

# Install Nginx
sudo amazon-linux-extras install nginx1 -y

# Create directory for certificates
sudo mkdir -p /etc/nginx/ssl


#### Copy Certificate to EC2

Option 1: Store in S3 (Recommended)
bash
# Upload to S3
aws s3 cp certificate.crt s3://my-certs-bucket/
aws s3 cp private.key s3://my-certs-bucket/
aws s3 cp chain.crt s3://my-certs-bucket/

# On EC2, download from S3
aws s3 cp s3://my-certs-bucket/certificate.crt /etc/nginx/ssl/
aws s3 cp s3://my-certs-bucket/private.key /etc/nginx/ssl/
aws s3 cp s3://my-certs-bucket/chain.crt /etc/nginx/ssl/

# Set permissions
sudo chmod 600 /etc/nginx/ssl/private.key
sudo chmod 644 /etc/nginx/ssl/certificate.crt


Option 2: Use AWS Secrets Manager
bash
# Store certificate in Secrets Manager
aws secretsmanager create-secret \
  --name ssl-certificate \
  --secret-string file://certificate.crt

aws secretsmanager create-secret \
  --name ssl-private-key \
  --secret-string file://private.key

# On EC2, retrieve from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id ssl-certificate \
  --query SecretString \
  --output text > /etc/nginx/ssl/certificate.crt

aws secretsmanager get-secret-value \
  --secret-id ssl-private-key \
  --query SecretString \
  --output text > /etc/nginx/ssl/private.key


#### Configure Nginx for HTTPS

bash
sudo nano /etc/nginx/nginx.conf


Nginx Configuration:
nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # HTTPS Server
    server {
        listen 443 ssl http2;
        server_name example.com www.example.com;

        # SSL Certificate
        ssl_certificate /etc/nginx/ssl/certificate.crt;
        ssl_certificate_key /etc/nginx/ssl/private.key;

        # SSL Configuration (Strong Security)
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # Security Headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Application
        location / {
            proxy_pass http://localhost:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name example.com www.example.com;
        return 301 https://$server_name$request_uri;
    }
}


Start Nginx:
bash
sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl status nginx


### Step 6: Configure Auto Scaling Group Launch Template

bash
# Create launch template with user data
aws ec2 create-launch-template \
  --launch-template-name my-https-template \
  --version-description "HTTPS enabled" \
  --launch-template-data '{
    "ImageId": "ami-xxxxx",
    "InstanceType": "t3.medium",
    "IamInstanceProfile": {
      "Arn": "arn:aws:iam::ACCOUNT:instance-profile/EC2-SSM-Role"
    },
    "SecurityGroupIds": ["sg-xxxxx"],
    "UserData": "'$(base64 -w 0 user-data.sh)'"
  }'


user-data.sh:
bash
#!/bin/bash

# Install Nginx
amazon-linux-extras install nginx1 -y

# Create SSL directory
mkdir -p /etc/nginx/ssl

# Download certificates from S3
aws s3 cp s3://my-certs-bucket/certificate.crt /etc/nginx/ssl/
aws s3 cp s3://my-certs-bucket/private.key /etc/nginx/ssl/
aws s3 cp s3://my-certs-bucket/chain.crt /etc/nginx/ssl/

# Set permissions
chmod 600 /etc/nginx/ssl/private.key
chmod 644 /etc/nginx/ssl/certificate.crt

# Copy Nginx config
aws s3 cp s3://my-config-bucket/nginx.conf /etc/nginx/nginx.conf

# Start application
cd /home/ec2-user/app
npm start &

# Start Nginx
systemctl start nginx
systemctl enable nginx


### Step 7: Update Auto Scaling Group

bash
# Create/Update Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name my-asg \
  --launch-template LaunchTemplateName=my-https-template,Version='$Latest' \
  --min-size 2 \
  --max-size 10 \
  --desired-capacity 2 \
  --target-group-arns $TG_ARN \
  --vpc-zone-identifier "subnet-xxxxx,subnet-yyyyy" \
  --health-check-type ELB \
  --health-check-grace-period 300


### Step 8: Configure Security Groups

NLB Security Group (if using):
bash
# NLB doesn't use security groups, but EC2 needs to allow traffic


EC2 Security Group:
bash
# Allow HTTPS from anywhere (NLB forwards traffic)
aws ec2 authorize-security-group-ingress \
  --group-id sg-ec2-xxxxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Allow HTTP for redirect
aws ec2 authorize-security-group-ingress \
  --group-id sg-ec2-xxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Allow SSH for management
aws ec2 authorize-security-group-ingress \
  --group-id sg-ec2-xxxxx \
  --protocol tcp \
  --port 22 \
  --source-group sg-bastion-xxxxx


### Step 9: Update DNS

bash
# Get NLB DNS name
NLB_DNS=$(aws elbv2 describe-load-balancers \
  --names my-nlb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Create Route 53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z1234567890ABC",
          "DNSName": "'$NLB_DNS'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Alternative: ALB with Re-encryption

If you need ALB features (path-based routing, WAF, etc.):

### Create ALB with HTTPS Listeners

bash
# Create ALB
aws elbv2 create-load-balancer \
  --name my-alb \
  --type application \
  --scheme internet-facing \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups sg-alb-xxxxx

# Create target group (HTTPS to EC2)
aws elbv2 create-target-group \
  --name my-https-targets \
  --protocol HTTPS \
  --port 443 \
  --vpc-id vpc-xxxxx \
  --health-check-protocol HTTPS \
  --health-check-path /health

# Create HTTPS listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:us-east-1:ACCOUNT:certificate/xxxxx \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN


Note: With ALB, traffic is decrypted at ALB and re-encrypted to EC2. ALB can inspect traffic.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Verification

### Test End-to-End Encryption

bash
# Test HTTPS connection
curl -v https://example.com

# Check certificate
openssl s_client -connect example.com:443 -showcerts

# Verify TLS version
nmap --script ssl-enum-ciphers -p 443 example.com


### Monitor SSL/TLS

bash
# Check certificate expiration
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:ACCOUNT:certificate/xxxxx \
  --query 'Certificate.NotAfter'

# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name HealthyHostCount \
  --dimensions Name=LoadBalancer,Value=net/my-nlb/xxxxx \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T18:00:00Z \
  --period 300 \
  --statistics Average


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Component | Configuration |
|-----------|---------------|
| Load Balancer | Network Load Balancer (NLB) |
| NLB Listener | TLS port 443 with ACM certificate |
| Target Group | TLS protocol, port 443 |
| EC2 Nginx | HTTPS with same certificate |
| Security Group | Allow 443 from 0.0.0.0/0 |
| Certificate | AWS ACM or imported |
| Encryption | TLS 1.2/1.3 end-to-end |

Result: Client → NLB → EC2 all encrypted with TLS, true end-to-end encryption.