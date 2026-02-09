 ## CloudWatch Logs vs CloudWatch Metrics

They are different services with different purposes, though they can work together.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Quick Comparison

| Aspect | CloudWatch Logs | CloudWatch Metrics |
|--------|----------------|-------------------|
| Purpose | Store and search log data | Store and visualize numeric time-series data |
| Data type | Text/JSON (unstructured) | Numbers (structured) |
| Use case | Debugging, audit trails, troubleshooting | Monitoring, alerting, auto-scaling |
| Query language | CloudWatch Logs Insights (SQL-like) | GetMetricStatistics, GetMetricData |
| Retention | Configurable (1 day to forever) | Fixed (15 months max) |
| Ingestion cost | $0.50/GB | Included in metric cost |
| Storage cost | $0.03/GB/month | Included in metric cost ($0.30/metric/month) |
| Typical size | Large (GBs to TBs) | Small (thousands of data points) |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudWatch Logs

### What It Stores
Raw text or JSON log entries

json
{
  "timestamp": "2026-02-09T18:00:00Z",
  "level": "ERROR",
  "message": "Database connection timeout",
  "user_id": "user-12345",
  "request_id": "req-abc-123",
  "duration_ms": 5000,
  "endpoint": "/api/orders",
  "error_code": "DB_TIMEOUT"
}


### Use Cases
- Application logs (errors, warnings, info)
- Access logs (who accessed what, when)
- Audit trails (compliance, security)
- Debugging (stack traces, detailed context)
- Transaction details

### Example: Application Logging

python
import json
import logging

# Configure logging to CloudWatch
logger = logging.getLogger()

def process_order(order):
    try:
        result = save_to_database(order)
        
        # Log detailed information
        logger.info(json.dumps({
            "event": "order_processed",
            "order_id": order['id'],
            "customer_id": order['customer_id'],
            "amount": order['total'],
            "items": order['items'],
            "payment_method": order['payment_method'],
            "processing_time_ms": 250,
            "status": "success"
        }))
        
    except Exception as e:
        # Log error with full context
        logger.error(json.dumps({
            "event": "order_failed",
            "order_id": order['id'],
            "error": str(e),
            "stack_trace": traceback.format_exc(),
            "customer_id": order['customer_id'],
            "retry_count": order.get('retry_count', 0)
        }))


### Querying Logs

sql
-- CloudWatch Logs Insights query
fields @timestamp, order_id, customer_id, amount, status
| filter event = "order_processed"
| filter amount > 1000
| stats count() as high_value_orders by customer_id
| sort high_value_orders desc
| limit 10


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## CloudWatch Metrics

### What It Stores
Numeric time-series data points

python
{
  "Timestamp": "2026-02-09T18:00:00Z",
  "MetricName": "OrderCount",
  "Value": 150,
  "Unit": "Count",
  "Dimensions": {
    "Environment": "production",
    "Region": "us-east-1"
  }
}


### Use Cases
- Performance monitoring (CPU, memory, latency)
- Business metrics (orders, revenue, users)
- Auto-scaling triggers
- Alerting on thresholds
- Dashboards and visualization

### Example: Publishing Metrics

python
import boto3

cloudwatch = boto3.client('cloudwatch')

def process_order(order):
    start_time = time.time()
    result = save_to_database(order)
    duration = (time.time() - start_time) * 1000
    
    # Publish metrics (numeric only)
    cloudwatch.put_metric_data(
        Namespace='OrderService',
        MetricData=[
            {
                'MetricName': 'OrderCount',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            },
            {
                'MetricName': 'OrderValue',
                'Value': order['total'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            },
            {
                'MetricName': 'ProcessingDuration',
                'Value': duration,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            }
        ]
    )


### Querying Metrics

python
# Get metric statistics
response = cloudwatch.get_metric_statistics(
    Namespace='OrderService',
    MetricName='OrderCount',
    Dimensions=[
        {'Name': 'Environment', 'Value': 'production'}
    ],
    StartTime=datetime.utcnow() - timedelta(hours=1),
    EndTime=datetime.utcnow(),
    Period=300,  # 5-minute buckets
    Statistics=['Sum', 'Average']
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Side-by-Side Example

### Scenario: Processing 1,000 orders

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### CloudWatch Logs Approach

python
# Log every order with full details
for order in orders:
    logger.info(json.dumps({
        "timestamp": datetime.utcnow().isoformat(),
        "order_id": order['id'],
        "customer_id": order['customer_id'],
        "amount": order['total'],
        "items": order['items'],
        "payment_method": order['payment_method'],
        "shipping_address": order['address'],
        "processing_time_ms": 250,
        "status": "success"
    }))


Data stored: 1,000 log entries (detailed JSON)
Size: ~500 KB (500 bytes per log entry)
Cost: 
- Ingestion: 0.5 MB × $0.50/GB = $0.00025
- Storage: 0.5 MB × $0.03/GB/month = $0.000015/month

What you can query:
- Which customer placed order X?
- What items were in order Y?
- Show all orders with payment method "credit_card"
- Find orders to specific shipping address
- Get full details of failed orders

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### CloudWatch Metrics Approach

python
# Publish aggregated metrics
cloudwatch.put_metric_data(
    Namespace='OrderService',
    MetricData=[
        {
            'MetricName': 'OrderCount',
            'Value': 1000,
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'TotalRevenue',
            'Value': 150000.00,
            'Unit': 'None',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'AverageOrderValue',
            'Value': 150.00,
            'Unit': 'None',
            'Timestamp': datetime.utcnow()
        }
    ]
)


Data stored: 3 data points (numbers only)
Size: Negligible
Cost: 3 metrics × $0.30 = $0.90/month

What you can query:
- How many orders in last hour?
- What's the total revenue?
- What's the average order value?
- Is order count above threshold?

What you CANNOT query:
- Which customer placed order X? ❌
- What items were in order Y? ❌
- Order details ❌

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## When to Use Each

### Use CloudWatch Logs When:
- Need detailed context (who, what, where, why)
- Debugging errors
- Audit trails
- Compliance requirements
- Searching for specific transactions
- Need to see raw data

Examples:
- "Show me all failed login attempts for user X"
- "What was the stack trace for error Y?"
- "Which orders included product Z?"
- "Show API requests from IP address A"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use CloudWatch Metrics When:
- Monitoring trends over time
- Alerting on thresholds
- Auto-scaling decisions
- Dashboards
- Performance monitoring
- Aggregated statistics

Examples:
- "Alert when CPU > 80%"
- "Scale up when request count > 1000/min"
- "Show average response time over last 24 hours"
- "How many orders per hour?"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Using Both Together

### Best Practice: Logs + Metrics

python
def process_order(order):
    start_time = time.time()
    
    try:
        result = save_to_database(order)
        duration = (time.time() - start_time) * 1000
        
        # 1. Log detailed information (for debugging)
        logger.info(json.dumps({
            "event": "order_processed",
            "order_id": order['id'],
            "customer_id": order['customer_id'],
            "amount": order['total'],
            "items": order['items'],
            "payment_method": order['payment_method'],
            "processing_time_ms": duration,
            "status": "success"
        }))
        
        # 2. Publish metrics (for monitoring/alerting)
        cloudwatch.put_metric_data(
            Namespace='OrderService',
            MetricData=[
                {
                    'MetricName': 'OrderCount',
                    'Value': 1,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'ProcessingDuration',
                    'Value': duration,
                    'Unit': 'Milliseconds'
                }
            ]
        )
        
    except Exception as e:
        # Log error details
        logger.error(json.dumps({
            "event": "order_failed",
            "order_id": order['id'],
            "error": str(e),
            "stack_trace": traceback.format_exc()
        }))
        
        # Publish error metric
        cloudwatch.put_metric_data(
            Namespace='OrderService',
            MetricData=[{
                'MetricName': 'OrderErrors',
                'Value': 1,
                'Unit': 'Count'
            }]
        )


Workflow:
1. Metric alarm triggers: "OrderErrors > 10 in 5 minutes"
2. Check dashboard: See spike in error rate
3. Query logs: Find specific failed orders and error details
4. Debug: Use log context to identify root cause

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Embedded Metric Format (EMF): Best of Both

Combines logs and metrics in one

python
# Single log entry creates both log and metrics
emf_log = {
    "_aws": {
        "Timestamp": int(time.time() * 1000),
        "CloudWatchMetrics": [{
            "Namespace": "OrderService",
            "Dimensions": [["Environment"]],
            "Metrics": [
                {"Name": "OrderCount", "Unit": "Count"},
                {"Name": "ProcessingDuration", "Unit": "Milliseconds"}
            ]
        }]
    },
    "Environment": "production",
    "OrderCount": 1,
    "ProcessingDuration": 250,
    # Additional context (logged but not metrics)
    "OrderID": order['id'],
    "CustomerID": order['customer_id'],
    "Amount": order['total'],
    "Items": order['items']
}

print(json.dumps(emf_log))  # Automatically creates logs AND metrics


Benefits:
- One log entry creates both logs and metrics
- Full context in logs
- Automatic metric extraction
- No separate PutMetricData calls

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison: 1 Million Orders/Month

### Logs Only
Log size: 500 bytes per order
Total: 1M × 500 bytes = 500 GB
Ingestion: 500 GB × $0.50 = $250/month
Storage: 500 GB × $0.03 = $15/month
Total: $265/month

Can query: Everything (full details)
Can alert: Via metric filters (limited)


### Metrics Only
Metrics: 3 metrics (OrderCount, Revenue, Duration)
Cost: 3 × $0.30 = $0.90/month