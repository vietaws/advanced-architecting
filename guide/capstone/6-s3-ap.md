S3 Access Points and bucket policies work together in a layered permission model. Here's how they interact:

## Permission Model

Both must allow - For a request to succeed, permissions must be granted by:
1. The S3 bucket policy
2. The Access Point policy
3. IAM user/role policy (if applicable)

Think of it as multiple gates - the request must pass through ALL of them.

## Key Differences

Bucket Policy - Controls access to the bucket itself and applies to all access methods (direct bucket access, access points, 
etc.)

Access Point Policy - Controls access through that specific access point only. Each access point can have different policies for
different use cases.

## Example Scenario: Shared Data Lake

Let's say you have a bucket with data from multiple departments:

s3://company-data-lake/
  ├── finance/
  ├── marketing/
  └── engineering/


### Bucket Policy (Delegates to Access Points)

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::company-data-lake/*",
        "arn:aws:s3:::company-data-lake"
      ],
      "Condition": {
        "StringEquals": {
          "s3:DataAccessPointAccount": "123456789012"
        }
      }
    }
  ]
}


This says: "Only allow access through access points owned by this account."

### Finance Access Point Policy

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/FinanceTeam"
      },
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:us-east-1:123456789012:accesspoint/finance-ap/object/finance/*",
        "arn:aws:s3:us-east-1:123456789012:accesspoint/finance-ap"
      ]
    }
  ]
}


Finance team can only read objects in the finance/ prefix through this access point.

### Marketing Access Point Policy

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/MarketingTeam"
      },
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:us-east-1:123456789012:accesspoint/marketing-ap/object/marketing/*",
        "arn:aws:s3:us-east-1:123456789012:accesspoint/marketing-ap"
      ]
    }
  ]
}


Marketing team can read and write objects in the marketing/ prefix through this access point.

## Benefits of This Approach

- **Simplified management** - Each team manages their own access point policy instead of modifying a complex shared bucket 
policy
- **Isolation** - Teams can't accidentally affect other teams' access
- **Scalability** - Add new access points without touching existing policies
- **Security** - Restrict direct bucket access, force all access through controlled access points

## What Happens When...

Finance team tries to access marketing data through finance-ap: ❌ Denied by access point policy

Marketing team tries to access through the bucket directly: ❌ Denied by bucket policy (only allows access point access)

Engineering team without an access point: ❌ No access at all

This layered approach gives you fine-grained control while keeping policies manageable.