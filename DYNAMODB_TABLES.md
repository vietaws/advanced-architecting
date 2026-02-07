# DynamoDB Tables Configuration

## Application uses 2 DynamoDB Tables:

### 1. products_table
**Purpose**: Store product information

**Schema**:
- **Partition Key**: `product_id` (String)
- **Attributes**:
  - `product_name` (String)
  - `description` (String)
  - `price` (Number)
  - `remaining_sku` (Number)
  - `image_key` (String) - S3 object key

**Create Command**:
```bash
aws dynamodb create-table \
  --table-name products_table \
  --attribute-definitions AttributeName=product_id,AttributeType=S \
  --key-schema AttributeName=product_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. orders_table
**Purpose**: Store order information from SQS

**Schema**:
- **Partition Key**: `id` (String)
- **Attributes**:
  - `product_name` (String)
  - `qty` (Number)
  - `price` (String)
  - `customer_id` (String)
  - `status` (String) - default: "in-processing"
  - `time` (String) - ISO timestamp

**Create Command**:
```bash
aws dynamodb create-table \
  --table-name orders_table \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Configuration File (app_config.json)

```json
{
  "dynamodb": {
    "region": "us-east-1",
    "productsTableName": "products_table",
    "ordersTableName": "orders_table"
  }
}
```

## Verify Tables

```bash
# List all tables
aws dynamodb list-tables --region us-east-1

# Check products_table
aws dynamodb describe-table --table-name products_table --region us-east-1

# Check orders_table
aws dynamodb describe-table --table-name orders_table --region us-east-1

# Scan products
aws dynamodb scan --table-name products_table --region us-east-1

# Scan orders
aws dynamodb scan --table-name orders_table --region us-east-1
```

## IAM Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:us-east-1:*:table/products_table",
        "arn:aws:dynamodb:us-east-1:*:table/orders_table"
      ]
    }
  ]
}
```
