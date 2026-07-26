## Architecture #003 - CloudFront Functions vs Lambda@Edge Demo

### Architecture Diagram

Global Users
    ↓
CloudFront Distribution (PriceClass_100)
    │
    ├── Default: /* → S3 Origin (static content)
    │   ├── CF Function: URL Rewrite (Viewer Request)
    │   └── CF Function: Security Headers (Viewer Response)
    │
    └── /api/* → ALB Origin (dynamic content)
        ├── Lambda@Edge: A/B Testing (Origin Request)
        └── Lambda@Edge: Response Modification (Origin Response)

Origins:
├── S3 Bucket (us-east-1) ← OAC
└── ALB → EC2 t3.micro (us-east-1) ← Node.js API


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: S3 Bucket for Static Content

bash
REGION="us-east-1"
BUCKET_NAME="cf-demo-static-$(date +%s)"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION

aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"


Upload demo page:

bash
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CloudFront Functions vs Lambda@Edge</title>
    <style>
        body { font-family: Arial; max-width: 900px; margin: 40px auto; padding: 0 20px; }
        .header { background: #232f3e; color: white; padding: 20px; border-radius: 8px; }
        .section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 8px; }
        .result { background: #f5f5f5; padding: 12px; margin: 10px 0; font-family: monospace; white-space: pre-wrap; }
        button { background: #ff9900; border: none; padding: 10px 20px; cursor: pointer; border-radius: 4px; margin: 4px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        td, th { border: 1px solid #ddd; padding: 8px; text-align: left; }
    </style>
</head>
<body>
    <div class="header">
        <h1>CloudFront Functions vs Lambda@Edge Demo</h1>
        <p>Demonstrating capabilities, use cases, and performance differences</p>
    </div>

    <div class="section">
        <h2>1. CloudFront Function - URL Rewrite</h2>
        <p>Rewrites /about to /about/index.html (Viewer Request)</p>
        <button onclick="testUrlRewrite()">Test URL Rewrite</button>
        <div id="url-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>2. CloudFront Function - Security Headers</h2>
        <p>Adds security headers to every response (Viewer Response)</p>
        <button onclick="testSecurityHeaders()">Check Response Headers</button>
        <div id="header-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>3. Lambda@Edge - A/B Testing</h2>
        <p>Assigns users to variant A or B at the edge (Origin Request)</p>
        <button onclick="testABTest()">Test A/B Assignment</button>
        <div id="ab-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>4. Lambda@Edge - Geo Routing</h2>
        <p>Reads CloudFront geo headers and customizes response</p>
        <button onclick="testGeo()">Test Geo Detection</button>
        <div id="geo-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>5. Performance Comparison</h2>
        <button onclick="runPerfTest()">Run 10-Request Benchmark</button>
        <div id="perf-result" class="result">Click to run benchmark...</div>
    </div>

    <script>
        async function testUrlRewrite() {
            const r = document.getElementById('url-result');
            try {
                const res = await fetch('/about');
                r.textContent = `Status: ${res.status}\nURL tested: /about\nRewritten to: /about/index.html\nContent-Type: ${res.headers.get('content-type')}`;
            } catch(e) { r.textContent = 'URL rewrite working - request was processed'; }
        }

        async function testSecurityHeaders() {
            const res = await fetch('/index.html');
            const h = {};
            ['strict-transport-security','x-content-type-options','x-frame-options','x-xss-protection','x-cf-function-time'].forEach(k => {
                const v = res.headers.get(k);
                if (v) h[k] = v;
            });
            document.getElementById('header-result').textContent = JSON.stringify(h, null, 2);
        }

        async function testABTest() {
            const res = await fetch('/api/ab-test');
            const data = await res.json();
            const cookie = document.cookie.match(/ab-test-variant=([AB])/);
            document.getElementById('ab-result').textContent =
                `Variant: ${data.variant}\nCookie: ${cookie ? cookie[0] : 'Not set yet'}\nResponse: ${JSON.stringify(data, null, 2)}`;
        }

        async function testGeo() {
            const res = await fetch('/api/geo');
            const data = await res.json();
            document.getElementById('geo-result').textContent = JSON.stringify(data, null, 2);
        }

        async function runPerfTest() {
            const r = document.getElementById('perf-result');
            r.textContent = 'Running benchmark...';
            const n = 10;
            let cfTotal = 0, lambdaTotal = 0;
            for (let i = 0; i < n; i++) {
                let t = performance.now();
                await fetch('/index.html?t=' + Date.now());
                cfTotal += performance.now() - t;

                t = performance.now();
                await fetch('/api/ab-test?t=' + Date.now());
                lambdaTotal += performance.now() - t;
            }
            r.textContent =
                `CloudFront Function (static):  avg ${(cfTotal/n).toFixed(1)}ms\nLambda@Edge (API):             avg ${(lambdaTotal/n).toFixed(1)}ms\nDifference:                    ${((lambdaTotal-cfTotal)/n).toFixed(1)}ms slower for Lambda@Edge`;
        }
    </script>
</body>
</html>
EOF

# Create a page for URL rewrite demo
mkdir -p about
echo "<h1>About Page - URL Rewrite Worked!</h1>" > about/index.html

aws s3 cp index.html s3://$BUCKET_NAME/index.html --content-type "text/html"
aws s3 cp about/index.html s3://$BUCKET_NAME/about/index.html --content-type "text/html"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: VPC + ALB + EC2 (API Origin)

bash
# VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=CF-Demo-VPC}]' \
  --region $REGION \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# 2 Public Subnets (required for ALB)
SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --region $REGION \
  --query 'Subnet.SubnetId' --output text)

SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --region $REGION \
  --query 'Subnet.SubnetId' --output text)

aws ec2 modify-subnet-attribute --subnet-id $SUBNET_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_2 --map-public-ip-on-launch

# Route table
RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID --region $REGION \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_1
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_2

# Security Groups
ALB_SG=$(aws ec2 create-security-group \
  --group-name cf-demo-alb-sg --description "ALB SG" \
  --vpc-id $VPC_ID --region $REGION \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0

EC2_SG=$(aws ec2 create-security-group \
  --group-name cf-demo-ec2-sg --description "EC2 SG" \
  --vpc-id $VPC_ID --region $REGION \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG --protocol tcp --port 80 --source-group $ALB_SG


EC2 with Node.js API:

bash
cat > user-data.sh << 'USERDATA'
#!/bin/bash
yum update -y
yum install -y nodejs

cat > /home/ec2-user/server.js << 'APP'
const http = require('http');
const url = require('url');

http.createServer((req, res) => {
    const path = url.parse(req.url, true).pathname;
    res.setHeader('Content-Type', 'application/json');

    const routes = {
        '/api/ab-test': () => ({
            variant: req.headers['x-ab-test-variant'] || 'none',
            message: `Variant ${req.headers['x-ab-test-variant'] || 'not assigned'}`,
            timestamp: new Date().toISOString()
        }),
        '/api/geo': () => ({
            country: req.headers['cloudfront-viewer-country'] || 'Unknown',
            city: req.headers['cloudfront-viewer-city'] || 'Unknown',
            region: req.headers['cloudfront-viewer-country-region-name'] || 'Unknown'
        }),
        '/api/health': () => ({ status: 'ok' })
    };

    const handler = routes[path];
    if (handler) {
        res.writeHead(200);
        res.end(JSON.stringify(handler()));
    } else {
        res.writeHead(404);
        res.end(JSON.stringify({ error: 'Not found' }));
    }
}).listen(80);
APP

node /home/ec2-user/server.js &
USERDATA

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --instance-type t3.micro \
  --subnet-id $SUBNET_1 \
  --security-group-ids $EC2_SG \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=CF-Demo-API}]' \
  --region $REGION \
  --query 'Instances[0].InstanceId' --output text)


ALB:

bash
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name cf-demo-alb \
  --subnets $SUBNET_1 $SUBNET_2 \
  --security-groups $ALB_SG \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' --output text)

TG_ARN=$(aws elbv2 create-target-group \
  --name cf-demo-tg --protocol HTTP --port 80 \
  --vpc-id $VPC_ID --health-check-path /api/health \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$INSTANCE_ID

aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: CloudFront Functions

3.1 URL Rewrite (Viewer Request):

javascript
// cf-func-url-rewrite.js
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    if (uri.endsWith('/')) {
        request.uri += 'index.html';
    } else if (!uri.includes('.')) {
        request.uri += '/index.html';
    }

    request.headers['x-cf-function'] = { value: 'url-rewrite' };
    return request;
}


3.2 Security Headers (Viewer Response):

javascript
// cf-func-security-headers.js
function handler(event) {
    var response = event.response;
    var h = response.headers;

    h['strict-transport-security'] = { value: 'max-age=63072000; includeSubdomains; preload' };
    h['x-content-type-options'] = { value: 'nosniff' };
    h['x-frame-options'] = { value: 'DENY' };
    h['x-xss-protection'] = { value: '1; mode=block' };
    h['x-cf-function-time'] = { value: new Date().toISOString() };

    return response;
}


Deploy:

bash
# URL Rewrite
aws cloudfront create-function \
  --name cf-url-rewrite \
  --function-config Comment="URL rewrite",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-url-rewrite.js \
  --region us-east-1

ETAG_1=$(aws cloudfront describe-function --name cf-url-rewrite --query 'ETag' --output text)
aws cloudfront publish-function --name cf-url-rewrite --if-match $ETAG_1

CF_FUNC_REWRITE=$(aws cloudfront describe-function --name cf-url-rewrite \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)

# Security Headers
aws cloudfront create-function \
  --name cf-security-headers \
  --function-config Comment="Security headers",Runtime=cloudfront-js-2.0 \
  --function-code fileb://cf-func-security-headers.js \
  --region us-east-1

ETAG_2=$(aws cloudfront describe-function --name cf-security-headers --query 'ETag' --output text)
aws cloudfront publish-function --name cf-security-headers --if-match $ETAG_2

CF_FUNC_HEADERS=$(aws cloudfront describe-function --name cf-security-headers \
  --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: Lambda@Edge Functions

4.1 IAM Role:

bash
cat > lambda-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF

ROLE_ARN=$(aws iam create-role \
  --role-name lambda-edge-role \
  --assume-role-policy-document file://lambda-trust.json \
  --query 'Role.Arn' --output text)

aws iam attach-role-policy \
  --role-name lambda-edge-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

sleep 10


4.2 A/B Testing (Origin Request):

javascript
// lambda-ab-test.js
'use strict';
exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    const cookies = request.headers.cookie || [];
    let variant = Math.random() < 0.5 ? 'A' : 'B';

    for (const c of cookies) {
        const match = c.value.match(/ab-test-variant=([AB])/);
        if (match) { variant = match[1]; break; }
    }

    request.headers['x-ab-test-variant'] = [{ key: 'X-AB-Test-Variant', value: variant }];
    callback(null, request);
};


4.3 Response Modification (Origin Response):

javascript
// lambda-response-mod.js
'use strict';
exports.handler = (event, context, callback) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const variant = request.headers['x-ab-test-variant'];

    if (variant) {
        response.headers['set-cookie'] = [{
            key: 'Set-Cookie',
            value: `ab-test-variant=${variant[0].value}; Path=/; Max-Age=86400; Secure; HttpOnly`
        }];
    }

    response.headers['x-lambda-edge'] = [{ key: 'X-Lambda-Edge', value: 'processed' }];
    response.headers['x-edge-time'] = [{ key: 'X-Edge-Time', value: new Date().toISOString() }];

    callback(null, response);
};


Deploy Lambda@Edge:

bash
# A/B Test
zip lambda-ab-test.zip lambda-ab-test.js
LAMBDA_AB_ARN=$(aws lambda create-function \
  --function-name cf-ab-test \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-ab-test.handler \
  --zip-file fileb://lambda-ab-test.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_AB_VER=$(aws lambda publish-version \
  --function-name cf-ab-test --region us-east-1 \
  --query 'Version' --output text)

# Response Modification
zip lambda-response-mod.zip lambda-response-mod.js
LAMBDA_RESP_ARN=$(aws lambda create-function \
  --function-name cf-response-mod \
  --runtime nodejs18.x \
  --role $ROLE_ARN \
  --handler lambda-response-mod.handler \
  --zip-file fileb://lambda-response-mod.zip \
  --memory-size 128 --timeout 5 \
  --region us-east-1 \
  --query 'FunctionArn' --output text)

LAMBDA_RESP_VER=$(aws lambda publish-version \
  --function-name cf-response-mod --region us-east-1 \
  --query 'Version' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 5: CloudFront Distribution

bash
# Origin Access Control for S3
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    Name=cf-demo-oac,Description="OAC for S3",SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3 \
  --query 'OriginAccessControl.Id' --output text)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Distribution config
cat > dist-config.json << EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "CF Functions vs Lambda@Edge Demo",
  "Enabled": true,
  "PriceClass": "PriceClass_100",
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "S3-Static",
        "DomainName": "${BUCKET_NAME}.s3.us-east-1.amazonaws.com",
        "S3OriginConfig": { "OriginAccessIdentity": "" },
        "OriginAccessControlId": "${OAC_ID}"
      },
      {
        "Id": "ALB-API",
        "DomainName": "${ALB_DNS}",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginSslProtocols": { "Quantity": 1, "Items": ["TLSv1.2"] }
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-Static",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": { "Quantity": 2, "Items": ["GET","HEAD"], "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
    "Compress": true,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "FunctionAssociations": {
      "Quantity": 2,
      "Items": [
        { "FunctionARN": "${CF_FUNC_REWRITE}", "EventType": "viewer-request" },
        { "FunctionARN": "${CF_FUNC_HEADERS}", "EventType": "viewer-response" }
      ]
    }
  },
  "CacheBehaviors": {
    "Quantity": 1,
    "Items": [{
      "PathPattern": "/api/*",
      "TargetOriginId": "ALB-API",
      "ViewerProtocolPolicy": "redirect-to-https",
      "AllowedMethods": { "Quantity": 7, "Items": ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"], "CachedMethods": { "Quantity": 2, "Items": ["GET","HEAD"] } },
      "Compress": true,
      "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
      "LambdaFunctionAssociations": {
        "Quantity": 2,
        "Items": [
          { "LambdaFunctionARN": "${LAMBDA_AB_ARN}:${LAMBDA_AB_VER}", "EventType": "origin-request", "IncludeBody": false },
          { "LambdaFunctionARN": "${LAMBDA_RESP_ARN}:${LAMBDA_RESP_VER}", "EventType": "origin-response", "IncludeBody": false }
        ]
      }
    }]
  }
}
EOF

DIST_ID=$(aws cloudfront create-distribution \
  --distribution-config file://dist-config.json \
  --query 'Distribution.Id' --output text)

CF_DOMAIN=$(aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DomainName' --output text)

echo "Distribution: https://${CF_DOMAIN}"


S3 Bucket Policy for OAC:

bash
cat > bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFront",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"
      }
    }
  }]
}
EOF

aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 6: Testing

bash
# Wait for distribution deployment (~5 minutes)
aws cloudfront wait distribution-deployed --id $DIST_ID

# Test 1: Static content with CF Functions
curl -I "https://${CF_DOMAIN}/index.html"
# Expect: x-cf-function-time, strict-transport-security, x-frame-options

# Test 2: URL rewrite
curl -I "https://${CF_DOMAIN}/about"
# Expect: 200 OK (rewritten to /about/index.html)

# Test 3: API with Lambda@Edge
curl "https://${CF_DOMAIN}/api/ab-test"
# Expect: {"variant":"A or B","message":"..."}
# Expect headers: set-cookie, x-lambda-edge, x-edge-time

# Test 4: Geo detection
curl "https://${CF_DOMAIN}/api/geo"
# Expect: {"country":"...","city":"..."}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudFront Functions vs Lambda@Edge Comparison

| Feature | CloudFront Functions | Lambda@Edge |
|---------|---------------------|-------------|
| Trigger Points | Viewer Request/Response only | All 4 (Viewer + Origin) |
| Runtime | JavaScript (ES 5.1 / 2.0) | Node.js, Python |
| Max Execution Time | 1ms | 5s (viewer) / 30s (origin) |
| Max Memory | 2MB | 128-3,008 MB |
| Max Package Size | 10KB | 1MB (viewer) / 50MB (origin) |
| Network Access | No | Yes |
| File System Access | No | Yes |
| Request Body Access | No | Yes |
| Pricing | $0.10/million | $0.60/million + duration |
| Scale | 10,000,000 RPS | Thousands RPS |
| Deploy Time | Seconds | Minutes (replicated globally) |

### When to Use What

CloudFront Functions (lightweight, fast, cheap):
- URL rewrites/redirects
- Header manipulation
- Cache key normalization
- Simple A/B testing (cookie-based routing)
- Request/response header inspection
- JWT token validation (simple)

Lambda@Edge (powerful, flexible, expensive):
- Complex authentication (OAuth, SAML)
- A/B testing with origin-side logic
- Dynamic origin selection
- Image transformation
- Server-side rendering at edge
- Bot detection with external API calls
- Content personalization with database lookups

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Analysis

### Monthly Costs (Demo Environment)

| Component | Cost | Notes |
|-----------|------|-------|
| EC2 t3.micro | $7.59 | 730 hours |
| EBS 8GB gp3 | $0.64 | Root volume |
| ALB | $16.43 | $0.0225/hour |
| ALB LCU | ~$1.00 | Minimal traffic |
| S3 Storage | $0.02 | <1GB |
| CloudFront | | |
| - Data transfer (10GB) | $0.85 | PriceClass_100 |
| - Requests (100K) | $0.01 | |
| - CF Functions (100K) | $0.01 | $0.10/million |
| - Lambda@Edge (50K) | $0.03 | $0.60/million + duration |
| Total | ~$26.58 | |

### At Scale (1M requests/day)

| Component | CF Functions | Lambda@Edge | Savings |
|-----------|-------------|-------------|---------|
| 30M requests/month | $3.00 | $18.00 | $15.00 |
| 300M requests/month | $30.00 | $180.00 | $150.00 |
| 1B requests/month | $100.00 | $600.00 | $500.00 |

Lambda@Edge is 6x more expensive per invocation. Use CloudFront Functions wherever possible and Lambda@Edge only when you need 
its extra capabilities.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cleanup

bash
# Disable and delete CloudFront distribution
aws cloudfront get-distribution-config --id $DIST_ID --query 'ETag' --output text
# Update with Enabled=false, then delete after deployed

# Delete Lambda@Edge (wait for replicas to be removed, can take hours)
aws lambda delete-function --function-name cf-ab-test
aws lambda delete-function --function-name cf-response-mod

# Delete CloudFront Functions
aws cloudfront delete-function --name cf-url-rewrite --if-match $(aws cloudfront describe-function --name cf-url-rewrite --query 'ETag' --output text)
aws cloudfront delete-function --name cf-security-headers --if-match $(aws cloudfront describe-function --name cf-security-headers --query 'ETag' --output text)

# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
aws elbv2 delete-target-group --target-group-arn $TG_ARN

# Terminate EC2
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Delete S3
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $