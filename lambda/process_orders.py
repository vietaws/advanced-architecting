import json
import random
import boto3
from datetime import datetime, timezone
import time

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('orders_table')

FINAL_STATUSES = ['completed', 'delivering']

def lambda_handler(event, context):
    for record in event['Records']:
        # Parse order from SQS message
        order = json.loads(record['body'])

        # Randomly assign final status
        order['status'] = random.choice(FINAL_STATUSES)

        # Only set completion_date when the order is fully completed
        if order['status'] == 'completed':
            order['completion_date'] = datetime.now(timezone.utc).isoformat()
        else:
            order.pop('completion_date', None)  # remove if present from a prior run

        # Put order into DynamoDB
        table.put_item(Item=order)

        # Simulate processing time
        time.sleep(5) # Simulate a 5-second processing time for each order

        print(f"Order {order['id']} processed — status: {order['status']}")

    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(event["Records"])} orders')
    }
