# Lambda Function: Process Orders from SQS to DynamoDB

## Overview
This Lambda function processes orders from SQS queue, updates their status to "completed", adds completion date, and stores them in DynamoDB `orders_table`.

## Function Details

**File**: `lambda/process_orders.py`

**Trigger**: SQS Queue (`sqs_queue_demo`)

**Runtime**: Python 3.12

## Setup Instructions

### 1. Create Lambda Function

**Using AWS Console:**
1. Go to Lambda Console: https://console.aws.amazon.com/lambda
2. Click **Create function**
3. Choose **Author from scratch**
4. Configure:
   - **Function name**: `ProcessOrdersFunction`
   - **Runtime**: Python 3.12
   - **Architecture**: x86_64
5. Click **Create function**
6. Copy code from `lambda/process_orders.py` into the code editor
7. Click **Deploy**

**Using AWS CLI:**
```bash
# Create deployment package
cd lambda
zip function.zip process_orders.py

# Create Lambda function
aws lambda create-function \
  --function-name ProcessOrdersFunction \
  --runtime python3.12 \
  --role arn:aws:iam::YOUR_ACCOUNT_ID:role/LambdaExecutionRole \
  --handler process_orders.lambda_handler \
  --zip-file fileb://function.zip \
  --region us-east-1
```

### 2. Create IAM Role for Lambda

**Required Permissions:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:us-east-1:*:sqs_queue_demo"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/orders_table"
    }
  ]
}
```

**Create Role via CLI:**
```bash
# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name LambdaOrderProcessorRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name LambdaOrderProcessorRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create and attach custom policy (save the JSON above as lambda-policy.json)
aws iam put-role-policy \
  --role-name LambdaOrderProcessorRole \
  --policy-name OrderProcessorPolicy \
  --policy-document file://lambda-policy.json
```

### 3. Configure SQS Trigger

**Using AWS Console:**
1. In Lambda function, click **Add trigger**
2. Select **SQS**
3. Choose your SQS queue: `sqs_queue_demo`
4. Set **Batch size**: 10
5. Click **Add**

**Using AWS CLI:**
```bash
# Get SQS queue ARN
QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/sqs_queue_demo \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)

# Create event source mapping
aws lambda create-event-source-mapping \
  --function-name ProcessOrdersFunction \
  --event-source-arn $QUEUE_ARN \
  --batch-size 10 \
  --region us-east-1
```

### 4. Update Frontend to Display Completion Date

Add completion date column to the orders table in `public/app.js`:

```javascript
<th style="padding:10px;border:1px solid #ddd;">Completion Date</th>

// In the tbody:
<td style="padding:10px;border:1px solid #ddd;">
  ${order.completion_date ? new Date(order.completion_date).toLocaleString() : 'N/A'}
</td>
```

## Testing

### 1. Generate Orders
1. Go to application: `http://<EC2-IP>:3000`
2. Click **Orders** tab
3. Click **Generate 10 Orders to SQS**

### 2. Verify Lambda Processing
```bash
# Check Lambda logs
aws logs tail /aws/lambda/ProcessOrdersFunction --follow

# Check SQS queue (should be empty after processing)
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT_ID/sqs_queue_demo \
  --attribute-names ApproximateNumberOfMessages
```

### 3. View Orders in DynamoDB
```bash
# Scan orders table
aws dynamodb scan --table-name orders_table --region us-east-1

# Or click "Get Order Status" in the application
```

## Order Flow

1. **Generate Orders** → Orders sent to SQS queue with status "in-processing"
2. **Lambda Triggered** → Automatically processes messages from SQS
3. **Update Status** → Changes status to "completed" and adds completion_date
4. **Save to DynamoDB** → Stores order in orders_table
5. **View Orders** → Click "Get Order Status" to see all orders

## Monitoring

**CloudWatch Logs:**
```bash
aws logs tail /aws/lambda/ProcessOrdersFunction --follow
```

**Lambda Metrics:**
- Invocations
- Duration
- Error count
- Throttles

**SQS Metrics:**
- Messages sent
- Messages received
- Messages deleted
- Age of oldest message

## Troubleshooting

**Orders not appearing in DynamoDB:**
- Check Lambda execution role has DynamoDB PutItem permission
- Check CloudWatch logs for errors
- Verify SQS trigger is enabled

**Lambda not triggered:**
- Verify event source mapping is active
- Check SQS queue has messages
- Review Lambda function configuration

**Permission errors:**
```bash
# Update Lambda execution role
aws lambda update-function-configuration \
  --function-name ProcessOrdersFunction \
  --role arn:aws:iam::YOUR_ACCOUNT_ID:role/LambdaOrderProcessorRole
```
