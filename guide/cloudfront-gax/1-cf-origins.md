## CloudFront with Multiple Origins

### Default Behavior: Active-Passive (Failover)

CloudFront with 2 origins is Active-Passive by default, NOT Active-Active.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How It Works

### Active-Passive (Failover)

CloudFront
├── Primary Origin (ALB us-east-1) ← Active
└── Secondary Origin (ALB eu-west-1) ← Passive (standby)

Normal operation:
- All requests → Primary Origin

Primary fails:
- CloudFront detects failure
- Switches to Secondary Origin
- All requests → Secondary Origin

Primary recovers:
- CloudFront switches back to Primary


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Configuration: Origin Groups (Failover)

### Create Origin Group

bash
# Create CloudFront distribution with origin group
aws cloudfront create-distribution \
  --distribution-config '{
    "Origins": {
      "Quantity": 2,
      "Items": [
        {
          "Id": "primary-alb",
          "DomainName": "alb-us-east-1.elb.amazonaws.com",
          "CustomOriginConfig": {
            "HTTPPort": 80,
            "HTTPSPort": 443,
            "OriginProtocolPolicy": "https-only"
          }
        },
        {
          "Id": "secondary-alb",
          "DomainName": "alb-eu-west-1.elb.amazonaws.com",
          "CustomOriginConfig": {
            "HTTPPort": 80,
            "HTTPSPort": 443,
            "OriginProtocolPolicy": "https-only"
          }
        }
      ]
    },
    "OriginGroups": {
      "Quantity": 1,
      "Items": [{
        "Id": "failover-group",
        "FailoverCriteria": {
          "StatusCodes": {
            "Quantity": 3,
            "Items": [500, 502, 503, 504]
          }
        },
        "Members": {
          "Quantity": 2,
          "Items": [
            {
              "OriginId": "primary-alb"
            },
            {
              "OriginId": "secondary-alb"
            }
          ]
        }
      }]
    },
    "DefaultCacheBehavior": {
      "TargetOriginId": "failover-group",
      "ViewerProtocolPolicy": "redirect-to-https"
    }
  }'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Failover Behavior

### When Failover Occurs

CloudFront switches to secondary when:
- Primary returns: 500, 502, 503, 504 (configurable)
- Primary times out
- Primary is unreachable

CloudFront does NOT failover for:
- 404 (Not Found)
- 403 (Forbidden)
- 401 (Unauthorized)

### Example Timeline

Time: 0s
Request → CloudFront → Primary ALB (us-east-1) → 200 OK
Status: Primary Active

Time: 60s
Request → CloudFront → Primary ALB → 503 Service Unavailable
Action: CloudFront tries Secondary ALB (eu-west-1)
Request → Secondary ALB → 200 OK
Status: Secondary Active (failover occurred)

Time: 120s
Request → CloudFront → Primary ALB → 200 OK (recovered)
Action: CloudFront switches back to Primary
Status: Primary Active


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Active-Active (NOT Default)

CloudFront does NOT support true Active-Active for origins.

You cannot:
- ❌ Load balance between origins
- ❌ Round-robin between origins
- ❌ Split traffic 50/50 between origins

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Workarounds for Active-Active

### Option 1: Use Global Accelerator

Users
  ↓
CloudFront (single origin)
  ↓
Global Accelerator (load balances)
  ├── ALB us-east-1 (50% traffic)
  └── ALB eu-west-1 (50% traffic)


### Option 2: Multiple CloudFront Distributions with Route 53

Users
  ↓
Route 53 (Geolocation/Latency routing)
  ├── CloudFront Distribution 1 → ALB us-east-1
  └── CloudFront Distribution 2 → ALB eu-west-1


### Option 3: ALB with Cross-Region Target Groups

Users
  ↓
CloudFront
  ↓
ALB (with cross-region targets)
  ├── EC2 us-east-1
  └── EC2 eu-west-1


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Example: Active-Passive Setup

### Step 1: Create Two ALBs

bash
# Primary ALB (us-east-1)
aws elbv2 create-load-balancer \
  --name primary-alb \
  --subnets subnet-us-east-1a subnet-us-east-1b \
  --region us-east-1

# Secondary ALB (eu-west-1)
aws elbv2 create-load-balancer \
  --name secondary-alb \
  --subnets subnet-eu-west-1a subnet-eu-west-1b \
  --region eu-west-1


### Step 2: Create CloudFront Distribution

json
{
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "primary-alb",
        "DomainName": "primary-alb-123.us-east-1.elb.amazonaws.com",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only",
          "OriginReadTimeout": 30,
          "OriginKeepaliveTimeout": 5
        }
      },
      {
        "Id": "secondary-alb",
        "DomainName": "secondary-alb-456.eu-west-1.elb.amazonaws.com",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only",
          "OriginReadTimeout": 30,
          "OriginKeepaliveTimeout": 5
        }
      }
    ]
  },
  "OriginGroups": {
    "Quantity": 1,
    "Items": [{
      "Id": "failover-group",
      "FailoverCriteria": {
        "StatusCodes": {
          "Quantity": 4,
          "Items": [500, 502, 503, 504]
        }
      },
      "Members": {
        "Quantity": 2,
        "Items": [
          { "OriginId": "primary-alb" },
          { "OriginId": "secondary-alb" }
        ]
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "failover-group",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    },
    "ForwardedValues": {
      "QueryString": true,
      "Cookies": { "Forward": "all" }
    },
    "MinTTL": 0,
    "DefaultTTL": 0,
    "MaxTTL": 0
  }
}


### Step 3: Test Failover

bash
# Normal request (goes to primary)
curl https://d1234.cloudfront.net/
# Response from us-east-1 ALB

# Simulate primary failure (stop primary ALB targets)
aws elbv2 deregister-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:... \
  --targets Id=i-xxxxx \
  --region us-east-1

# Request during failure (goes to secondary)
curl https://d1234.cloudfront.net/
# Response from eu-west-1 ALB (failover!)

# Restore primary
aws elbv2 register-targets \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:... \
  --targets Id=i-xxxxx \
  --region us-east-1

# Request after recovery (goes back to primary)
curl https://d1234.cloudfront.net/
# Response from us-east-1 ALB


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring Failover

bash
# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name OriginLatency \
  --dimensions Name=DistributionId,Value=E1234 Name=Region,Value=Global \
  --start-time 2026-02-08T00:00:00Z \
  --end-time 2026-02-08T20:00:00Z \
  --period 300 \
  --statistics Average

# Check which origin is active
aws cloudfront get-distribution --id E1234 \
  --query 'Distribution.ActiveTrustedSigners'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Feature | CloudFront with 2 Origins |
|---------|---------------------------|
| Default Behavior | Active-Passive (Failover) |
| Primary Origin | Handles all traffic normally |
| Secondary Origin | Standby, only used on failure |
| Failover Trigger | 500, 502, 503, 504 errors |
| Failback | Automatic when primary recovers |
| Active-Active | ❌ Not supported natively |
| Load Balancing | ❌ Not supported between origins |

Key Point: CloudFront with multiple origins is Active-Passive (failover), not Active-Active. Only one origin serves traffic at 
a time.

For true Active-Active, use Global Accelerator or Route 53 with multiple CloudFront distributions.