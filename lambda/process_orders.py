import json
import random
import boto3
import logging
import asyncio
import concurrent.futures
from datetime import datetime, timezone
import time

# Structured JSON logging for CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def log(level, msg, **kwargs):
    entry = {"message": msg, "timestamp": datetime.now(timezone.utc).isoformat(), **kwargs}
    getattr(logger, level)(json.dumps(entry))

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('orders_table')

FINAL_STATUSES = ['completed', 'delivering']


def process_single_order(index, record, batch_size):
    """Process one SQS record. Returns (message_id, success, error)."""
    sqs_message_id = record.get('messageId', 'unknown')
    order_id = None

    try:
        # Step 1: Parse SQS message
        order = json.loads(record['body'])
        order_id = order.get('id', 'unknown')

        log('info', 'Processing order',
            step='parse',
            order_index=index + 1,
            batch_size=batch_size,
            order_id=order_id,
            sqs_message_id=sqs_message_id
        )

        # Step 2: Assign final status
        order['status'] = random.choice(FINAL_STATUSES)
        if order['status'] == 'completed':
            order['completion_date'] = datetime.now(timezone.utc).isoformat()
        else:
            order.pop('completion_date', None)

        log('info', 'Status assigned',
            step='status',
            order_id=order_id,
            status=order['status'],
            has_completion_date='completion_date' in order
        )

        # Step 3: Simulate processing time (per order, runs in parallel)
        time.sleep(2)

        # Step 4: Write to DynamoDB
        start_time = time.time()
        table.put_item(Item=order)
        latency_ms = round((time.time() - start_time) * 1000)

        log('info', 'Order saved to DynamoDB',
            step='dynamodb_write',
            order_id=order_id,
            status=order['status'],
            latency_ms=latency_ms
        )

        return sqs_message_id, True, None

    except Exception as e:
        log('error', 'Failed to process order',
            step='error',
            order_id=order_id,
            order_index=index + 1,
            sqs_message_id=sqs_message_id,
            error=str(e)
        )
        return sqs_message_id, False, str(e)


def lambda_handler(event, context):
    records = event['Records']
    batch_size = len(records)

    log('info', 'Batch received',
        batch_size=batch_size,
        function=context.function_name,
        request_id=context.aws_request_id,
        remaining_time_ms=context.get_remaining_time_in_millis()
    )

    success_count = 0
    fail_count = 0
    batch_item_failures = []

    # Process all orders in parallel using a thread pool
    # Max workers = batch size so all orders run concurrently (sleep overlaps)
    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = {
            executor.submit(process_single_order, i, record, batch_size): record
            for i, record in enumerate(records)
        }

        for future in concurrent.futures.as_completed(futures):
            sqs_message_id, success, error = future.result()
            if success:
                success_count += 1
            else:
                fail_count += 1
                # Return failed message IDs back to SQS for retry
                batch_item_failures.append({'itemIdentifier': sqs_message_id})

    log('info', 'Batch completed',
        batch_size=batch_size,
        success_count=success_count,
        fail_count=fail_count,
        failed_message_ids=[f['itemIdentifier'] for f in batch_item_failures],
        request_id=context.aws_request_id,
        remaining_time_ms=context.get_remaining_time_in_millis()
    )

    # Return failed items to SQS for retry — only failed messages become visible again.
    # Requires "Report batch item failures" enabled on the SQS event source mapping.
    return {
        'batchItemFailures': batch_item_failures
    }
