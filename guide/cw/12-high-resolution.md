## What is High-Resolution Metrics?

High-resolution metrics in CloudWatch allow you to publish and store metrics at 1-second intervals instead of the standard 60-
second (1-minute) intervals.

### Resolution Types

Standard Resolution:
- Data points every 60 seconds (1 minute)
- Default for all AWS service metrics and custom metrics
- Retained for 15 months

High Resolution:
- Data points every 1 second
- Must be explicitly configured for custom metrics
- Retained for 3 hours at 1-second granularity
- After 3 hours, automatically aggregated to 1-minute resolution

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Why Use High-Resolution Metrics?

### Use Cases

1. Real-time monitoring - Detect issues within seconds, not minutes
2. Short-lived spikes - Catch brief performance problems that would be averaged out in 1-minute intervals
3. Gaming/Trading applications - Sub-second latency monitoring
4. Auto-scaling triggers - React faster to traffic changes
5. SLA monitoring - More accurate percentile calculations

### Example: Why It Matters

Scenario: API endpoint has a 10-second spike to 5000ms latency, then returns to normal 100ms

Standard resolution (60-second):
- Averages 10 seconds of 5000ms + 50 seconds of 100ms
- Reported average: ~900ms
- **Spike is hidden in the average**

High resolution (1-second):
- 10 data points at 5000ms, 50 data points at 100ms
- Can see the exact 10-second spike
- **Spike is clearly visible**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Default Setup

AWS Service Metrics: Always standard resolution (1-minute)
- EC2, RDS, Lambda, etc.
- Cannot be changed to high resolution

Custom Metrics: Standard resolution by default
- Must explicitly set StorageResolution=1 for high resolution

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing

Same as standard metrics: $0.30 per metric/month (first 10,000)

BUT: More API calls for querying
- GetMetricData: $0.01 per 1,000 requests
- High-resolution queries can be more expensive if you query frequently

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation Examples

### Example 1: Basic High-Resolution Metric (Python)

python
import boto3
import time

cloudwatch = boto3.client('cloudwatch')

# Publish high-resolution metric
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[
        {
            'MetricName': 'ResponseTime',
            'Value': 245.5,
            'Unit': 'Milliseconds',
            'StorageResolution': 1,  # 1 = high-resolution, 60 = standard
            'Timestamp': time.time(),
            'Dimensions': [
                {'Name': 'Service', 'Value': 'API'}
            ]
        }
    ]
)


Key: StorageResolution: 1 enables high resolution

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 2: Real-Time API Monitoring

python
import boto3
import time
from functools import wraps

cloudwatch = boto3.client('cloudwatch')

def monitor_latency(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        duration = (time.time() - start) * 1000
        
        # Publish every request with 1-second resolution
        cloudwatch.put_metric_data(
            Namespace='APIMonitoring',
            MetricData=[{
                'MetricName': 'RequestLatency',
                'Value': duration,
                'Unit': 'Milliseconds',
                'StorageResolution': 1,
                'Dimensions': [
                    {'Name': 'Endpoint', 'Value': func.__name__},
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            }]
        )
        
        return result
    return wrapper

@monitor_latency
def process_payment(payment_data):
    # Process payment
    time.sleep(0.5)  # Simulate processing
    return {'status': 'success'}

# Usage
process_payment({'amount': 100})


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 3: Batch Publishing for High Volume

python
import boto3
import time
from collections import deque
import threading

class HighResolutionMetricPublisher:
    def __init__(self, namespace, batch_size=20):
        self.cloudwatch = boto3.client('cloudwatch')
        self.namespace = namespace
        self.batch_size = batch_size
        self.queue = deque()
        self.lock = threading.Lock()
        
        # Start background thread to flush metrics
        self.flush_thread = threading.Thread(target=self._flush_loop, daemon=True)
        self.flush_thread.start()
    
    def publish(self, metric_name, value, unit='None', dimensions=None):
        metric_data = {
            'MetricName': metric_name,
            'Value': value,
            'Unit': unit,
            'StorageResolution': 1,
            'Timestamp': time.time()
        }
        
        if dimensions:
            metric_data['Dimensions'] = dimensions
        
        with self.lock:
            self.queue.append(metric_data)
            
            # Flush if batch is full
            if len(self.queue) >= self.batch_size:
                self._flush()
    
    def _flush(self):
        if not self.queue:
            return
        
        batch = []
        while self.queue and len(batch) < self.batch_size:
            batch.append(self.queue.popleft())
        
        try:
            self.cloudwatch.put_metric_data(
                Namespace=self.namespace,
                MetricData=batch
            )
        except Exception as e:
            print(f"Failed to publish metrics: {e}")
    
    def _flush_loop(self):
        while True:
            time.sleep(1)  # Flush every second
            with self.lock:
                self._flush()

# Usage
publisher = HighResolutionMetricPublisher('HighVolumeApp')

for i in range(100):
    publisher.publish(
        'RequestCount',
        1,
        'Count',
        [{'Name': 'Service', 'Value': 'API'}]
    )
    time.sleep(0.01)  # 100 requests per second


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 4: High-Resolution with EMF

python
import json
import time

def process_transaction(transaction):
    start = time.time()
    
    # Process transaction
    result = execute_transaction(transaction)
    
    duration = (time.time() - start) * 1000
    
    # EMF with high-resolution
    emf_log = {
        "_aws": {
            "Timestamp": int(time.time() * 1000),
            "CloudWatchMetrics": [{
                "Namespace": "TradingPlatform",
                "Dimensions": [["TransactionType"]],
                "Metrics": [{
                    "Name": "TransactionLatency",
                    "Unit": "Milliseconds",
                    "StorageResolution": 1  # High resolution
                }]
            }]
        },
        "TransactionType": transaction['type'],
        "TransactionLatency": duration,
        "TransactionID": transaction['id'],
        "Amount": transaction['amount'],
        "Success": result['success']
    }
    
    print(json.dumps(emf_log))
    return result


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 5: Auto-Scaling Based on High-Resolution Metrics

python
import boto3

cloudwatch = boto3.client('cloudwatch')
autoscaling = boto3.client('application-autoscaling')

# Create high-resolution alarm
cloudwatch.put_metric_alarm(
    AlarmName='HighLatencyAlarm',
    ComparisonOperator='GreaterThanThreshold',
    EvaluationPeriods=1,
    MetricName='RequestLatency',
    Namespace='APIMonitoring',
    Period=10,  # 10-second period (minimum for high-resolution)
    Statistic='Average',
    Threshold=1000.0,  # 1000ms
    ActionsEnabled=True,
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:...'
    ],
    AlarmDescription='Scale up when latency exceeds 1s for 10 seconds',
    Dimensions=[
        {'Name': 'Service', 'Value': 'API'}
    ]
)