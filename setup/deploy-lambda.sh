#!/bin/bash
# Deploy Lambda function to process orders from SQS to DynamoDB

set -e

# Variables - UPDATE THESE
AWS_REGION="us-east-1"
FUNCTION_NAME="ProcessOrdersFunction"
ROLE_NAME="LambdaOrderProcessorRole"
SQS_QUEUE_NAME="sqs_queue_demo"

echo "Creating Lambda deployment package..."
cd lambda
zip -q function.zip process_orders.py
cd ..

echo "Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Creating IAM role for Lambda..."
cat > /tmp/trust-policy.json <<EOF
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

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --region $AWS_REGION 2>/dev/null || echo "Role already exists"

echo "Attaching basic execution policy..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

echo "Creating custom policy for SQS and DynamoDB..."
cat > /tmp/lambda-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${ACCOUNT_ID}:${SQS_QUEUE_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/orders_table"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name OrderProcessorPolicy \
  --policy-document file:///tmp/lambda-policy.json

echo "Waiting for IAM role to propagate..."
sleep 10

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "Creating Lambda function..."
aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --runtime python3.12 \
  --role $ROLE_ARN \
  --handler process_orders.lambda_handler \
  --zip-file fileb://lambda/function.zip \
  --timeout 30 \
  --memory-size 128 \
  --region $AWS_REGION 2>/dev/null || {
    echo "Function exists, updating code..."
    aws lambda update-function-code \
      --function-name $FUNCTION_NAME \
      --zip-file fileb://lambda/function.zip \
      --region $AWS_REGION
  }

echo "Getting SQS queue ARN..."
QUEUE_URL="https://sqs.${AWS_REGION}.amazonaws.com/${ACCOUNT_ID}/${SQS_QUEUE_NAME}"
QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text \
  --region $AWS_REGION)

echo "Creating event source mapping..."
aws lambda create-event-source-mapping \
  --function-name $FUNCTION_NAME \
  --event-source-arn $QUEUE_ARN \
  --batch-size 10 \
  --region $AWS_REGION 2>/dev/null || echo "Event source mapping already exists"

echo "✓ Lambda function deployed successfully!"
echo "Function Name: $FUNCTION_NAME"
echo "Queue: $SQS_QUEUE_NAME"
echo "Region: $AWS_REGION"
echo ""
echo "Test by generating orders in the application:"
echo "1. Go to Orders tab"
echo "2. Click 'Generate 10 Orders to SQS'"
echo "3. Wait a few seconds"
echo "4. Click 'Get Order Status' to see completed orders"
