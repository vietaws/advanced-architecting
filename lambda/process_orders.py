import json
import boto3
from datetime import datetime
import time

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('orders_table')

def lambda_handler(event, context):
    for record in event['Records']:
        # Parse order from SQS message
        order = json.loads(record['body'])
        
        # Update order with completion status and date
        order['status'] = 'completed'
        order['completion_date'] = datetime.utcnow().isoformat()
        
        # Put order into DynamoDB
        table.put_item(Item=order)

        #processing time
        time.sleep(7)
        
        print(f"Order {order['id']} processed and saved to DynamoDB")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(event["Records"])} orders')
    }
