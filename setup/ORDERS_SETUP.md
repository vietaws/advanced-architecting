# Orders Table Setup Guide

## Create DynamoDB Orders Table

### Using AWS CLI

```bash
aws dynamodb create-table \
  --table-name orders_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Using AWS Console

1. Go to **DynamoDB Console**: https://console.aws.amazon.com/dynamodb
2. Click **Create table**
3. Configure:
   - **Table name**: `orders_table`
   - **Partition key**: `id` (String)
   - **Table settings**: On-demand (or Provisioned with 5 RCU/WCU)
4. Click **Create table**

### Verify Table Creation

```bash
# Check table status
aws dynamodb describe-table \
  --table-name orders_table \
  --region us-east-1 \
  --query 'Table.[TableName,TableStatus,ItemCount]'

# List all tables
aws dynamodb list-tables --region us-east-1
```

## Create SQS Queue

```bash
# Create SQS queue
aws sqs create-queue \
  --queue-name sqs_queue_demo \
  --region us-east-1

# Get queue URL (save this for app_config.json)
aws sqs get-queue-url \
  --queue-name sqs_queue_demo \
  --region us-east-1
```

## Update Configuration

Update `app_config.json` with your queue URL:

```json
{
  "dynamodb": {
    "region": "us-east-1",
    "tableName": "demo_table",
    "ordersTableName": "orders_table"
  },
  "sqs": {
    "region": "us-east-1",
    "queueUrl": "https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/sqs_queue_demo"
  }
}
```

## IAM Permissions Required

Ensure your EC2 IAM role has these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/orders_table"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage"
      ],
      "Resource": "arn:aws:sqs:us-east-1:*:sqs_queue_demo"
    }
  ]
}
```

## Test Orders Feature

1. Access application: `http://<EC2-IP>:3000`
2. Click **Orders** tab
3. Click **Generate 10 Orders to SQS** - sends orders to SQS
4. Click **Get Order Status** - retrieves orders from DynamoDB

## Order Data Structure

Each order contains:
- `id` - Unique order ID (Primary Key)
- `product_name` - Product name
- `qty` - Quantity (1-10)
- `price` - Price ($10-$1010)
- `customer_id` - Customer ID
- `status` - Order status (default: "in-processing")
- `time` - Timestamp (ISO format)

## Troubleshooting

**Orders not appearing in DynamoDB?**
- Check if SQS messages are being sent
- Verify you have a Lambda or consumer processing SQS messages to DynamoDB
- Check IAM permissions

**Can't send to SQS?**
```bash
# Test SQS manually
aws sqs send-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/sqs_queue_demo \
  --message-body '{"test":"message"}' \
  --region us-east-1
```

**Check application logs:**
```bash
sudo journalctl -u demo-app -f
```
