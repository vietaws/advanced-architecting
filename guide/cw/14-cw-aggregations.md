## What is "CloudWatch Aggregates Your Data"?

Aggregation means CloudWatch combines multiple data points within a time period using statistical functions (Sum, Average, Min, 
Max, SampleCount).

When you send multiple data points in the same period, CloudWatch doesn't store each one individually - it calculates statistics
and stores those.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Differences: Standard vs High Resolution

| Aspect | Standard Resolution | High Resolution |
|--------|-------------------|-----------------|
| StorageResolution value | 60 | 1 |
| Minimum query period | 60 seconds | 1 second |
| Aggregation bucket | 1-minute buckets | 1-second buckets |
| Best for | Minute-level trends | Sub-minute spike detection |
| Data retention at native resolution | 15 days | 3 hours |
| Cost | $0.30/metric/month | $0.30/metric/month |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 1: Understanding Aggregation

### Scenario: API receives 10 requests in 1 minute

Data points sent (with response times in milliseconds):
14:00:05 → 100ms
14:00:12 → 150ms
14:00:18 → 200ms
14:00:25 → 120ms
14:00:33 → 180ms
14:00:41 → 140ms
14:00:48 → 160ms
14:00:52 → 130ms
14:00:56 → 190ms
14:00:59 → 110ms


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution (StorageResolution: 60)

How CloudWatch stores it:
Period: 14:00:00 - 14:01:00 (1-minute bucket)

Aggregated statistics:
- Sum: 1,480ms
- Average: 148ms
- Min: 100ms
- Max: 200ms
- SampleCount: 10


What you can query:
python
# Query with 1-minute period
response = cloudwatch.get_metric_statistics(
    Namespace='API',
    MetricName='ResponseTime',
    StartTime=datetime(2026, 2, 9, 14, 0),
    EndTime=datetime(2026, 2, 9, 14, 5),
    Period=60,  # Minimum 60 seconds
    Statistics=['Average', 'Maximum', 'Minimum']
)

# Result:
# Time: 14:00:00, Avg: 148ms, Max: 200ms, Min: 100ms
# Time: 14:01:00, Avg: 145ms, Max: 195ms, Min: 105ms
# ...


What you CANNOT see:
- Individual request response times
- Exact timestamp of the 200ms spike (was it at 14:00:18?)
- Sub-minute patterns

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution (StorageResolution: 1)

How CloudWatch stores it:
Period: 14:00:05 (1-second bucket)
- Value: 100ms

Period: 14:00:12 (1-second bucket)
- Value: 150ms

Period: 14:00:18 (1-second bucket)
- Value: 200ms

Period: 14:00:25 (1-second bucket)
- Value: 120ms

... and so on for each second


What you can query:
python
# Query with 1-second period
response = cloudwatch.get_metric_statistics(
    Namespace='API',
    MetricName='ResponseTime',
    StartTime=datetime(2026, 2, 9, 14, 0),
    EndTime=datetime(2026, 2, 9, 14, 1),
    Period=1,  # Can query at 1-second granularity
    Statistics=['Average', 'Maximum']
)

# Result:
# Time: 14:00:05, Avg: 100ms, Max: 100ms
# Time: 14:00:12, Avg: 150ms, Max: 150ms
# Time: 14:00:18, Avg: 200ms, Max: 200ms  ← Exact spike time!
# Time: 14:00:25, Avg: 120ms, Max: 120ms
# ...


What you CAN see:
- Exact second when spike occurred (14:00:18)
- Sub-minute patterns
- Rapid changes in metrics

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: Multiple Data Points in Same Period

### Scenario: High-traffic API, 100 requests per second

Sending data:
python
# 100 requests arrive at 14:00:05
for i in range(100):
    cloudwatch.put_metric_data(
        Namespace='API',
        MetricData=[{
            'MetricName': 'ResponseTime',
            'Value': random.randint(50, 200),
            'Timestamp': datetime(2026, 2, 9, 14, 0, 5),
            'StorageResolution': 1  # High resolution
        }]
    )


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution Behavior

CloudWatch aggregates all 100 values into 1-minute bucket:
Period: 14:00:00 - 14:01:00

If 6,000 requests in this minute (100/sec × 60 sec):
- Sum: 750,000ms
- Average: 125ms
- Min: 50ms
- Max: 200ms
- SampleCount: 6,000


Dashboard shows:
14:00 - 14:01: Avg 125ms
14:01 - 14:02: Avg 130ms
14:02 - 14:03: Avg 128ms


Problem: Can't see that at 14:00:05 there was a 5-second spike to 180ms average.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Behavior

CloudWatch aggregates into 1-second buckets:
Period: 14:00:05 (100 requests in this second)
- Sum: 12,500ms
- Average: 125ms
- Min: 50ms
- Max: 200ms
- SampleCount: 100

Period: 14:00:06 (100 requests in this second)
- Sum: 18,000ms
- Average: 180ms  ← Spike detected!
- Min: 150ms
- Max: 200ms
- SampleCount: 100

Period: 14:00:07 (100 requests in this second)
- Sum: 12,000ms
- Average: 120ms
- Min: 50ms
- Max: 180ms
- SampleCount: 100


Dashboard shows (1-second granularity):
14:00:05: Avg 125ms
14:00:06: Avg 180ms  ← 5-second spike visible!
14:00:07: Avg 120ms
14:00:08: Avg 122ms
14:00:09: Avg 118ms
14:00:10: Avg 180ms  ← Another spike!
14:00:11: Avg 125ms


Benefit: You can see exactly when spikes occur and their duration.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 3: Real-World Comparison - Auto Scaling

### Scenario: Auto-scaling based on CPU utilization

Standard Resolution:
python
# CPU metric with standard resolution
cloudwatch.put_metric_data(
    Namespace='CustomApp',
    MetricData=[{
        'MetricName': 'CPUUtilization',
        'Value': cpu_percent,
        'StorageResolution': 60
    }]
)

# Auto-scaling alarm
cloudwatch.put_metric_alarm(
    AlarmName='HighCPU',
    MetricName='CPUUtilization',
    Namespace='CustomApp',
    Statistic='Average',
    Period=60,  # Minimum 1 minute
    EvaluationPeriods=2,
    Threshold=80.0
)


Timeline:
14:00:00-14:01:00: Avg CPU 75%
14:01:00-14:02:00: Avg CPU 85%  ← Alarm triggered after 2 minutes
14:02:00-14:03:00: Avg CPU 85%  ← Scaling action starts
14:03:00-14:04:00: New instances launching...


Problem: 
- Actual spike happened at 14:01:05 (lasted 10 seconds)
- Alarm triggered at 14:02:00 (55 seconds later)
- Users experienced slowness for ~2 minutes before scaling

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


High Resolution:
python
# CPU metric with high resolution
cloudwatch.put_metric_data(
    Namespace='CustomApp',
    MetricData=[{
        'MetricName': 'CPUUtilization',
        'Value': cpu_percent,
        'StorageResolution': 1  # High resolution
    }]
)

# Auto-scaling alarm with 10-second period
cloudwatch.put_metric_alarm(
    AlarmName='HighCPU',
    MetricName='CPUUtilization',
    Namespace='CustomApp',
    Statistic='Average',
    Period=10,  # Can use 10-second period
    EvaluationPeriods=2,
    Threshold=80.0
)


Timeline:
14:01:05-14:01:15: Avg CPU 85%
14:01:15-14:01:25: Avg CPU 87%  ← Alarm triggered after 20 seconds
14:01:25-14:01:35: Scaling action starts
14:01:35-14:02:35: New instances launching...


Benefit:
- Spike detected at 14:01:15 (10 seconds after it started)
- Alarm triggered at 14:01:25 (20 seconds total)
- Scaling starts 1 minute 35 seconds earlier than standard resolution
- Users experience less impact

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 4: Cost vs Benefit Analysis

### Scenario: E-commerce checkout service

Metrics tracked:
- CheckoutDuration
- PaymentProcessingTime
- InventoryCheckTime

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution

python
# Send metrics every request
cloudwatch.put_metric_data(
    Namespace='Checkout',
    MetricData=[
        {'MetricName': 'CheckoutDuration', 'Value': 1200, 'StorageResolution': 60},
        {'MetricName': 'PaymentProcessingTime', 'Value': 800, 'StorageResolution': 60},
        {'MetricName': 'InventoryCheckTime', 'Value': 150, 'StorageResolution': 60}
    ]
)


Cost: 3 metrics × $0.30 = $0.90/month

Dashboard (1-minute granularity):
Time        CheckoutDuration    PaymentTime    InventoryCheck
14:00-14:01      1,200ms          800ms           150ms
14:01-14:02      1,250ms          850ms           160ms
14:02-14:03      3,500ms          2,800ms         200ms  ← Problem detected
14:03-14:04      1,180ms          780ms           145ms


Analysis:
- Problem detected in 14:02-14:03 window
- Don't know if it was at start, middle, or end of minute
- Can't correlate with deployment that happened at 14:02:15

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution

python
# Same code, just change StorageResolution
cloudwatch.put_metric_data(
    Namespace='Checkout',
    MetricData=[
        {'MetricName': 'CheckoutDuration', 'Value': 1200, 'StorageResolution': 1},
        {'MetricName': 'PaymentProcessingTime', 'Value': 800, 'StorageResolution': 1},
        {'MetricName': 'InventoryCheckTime', 'Value': 150, 'StorageResolution': 1}
    ]
)


Cost: 3 metrics × $0.30 = $0.90/month (same!)

Dashboard (10-second granularity):
Time            CheckoutDuration    PaymentTime    InventoryCheck
14:02:00-14:02:10    1,200ms          800ms           150ms
14:02:10-14:02:20    1,250ms          850ms           155ms
14:02:20-14:02:30    3,500ms          2,800ms         200ms  ← Exact problem window
14:02:30-14:02:40    3,600ms          2,900ms         205ms
14:02:40-14:02:50    1,180ms          780ms           145ms  ← Recovered
14:02:50-14:03:00    1,150ms          770ms           140ms


Analysis:
- Problem started at 14:02:20 (5 seconds after deployment at 14:02:15)
- Lasted 20 seconds (14:02:20 to 14:02:40)
- Clear correlation with deployment
- Can rollback with confidence

Value: Same cost, but 10x better troubleshooting capability.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 5: Aggregation with Different Statistics

### Scenario: 10 API requests in 1 minute with these response times

100ms, 105ms, 110ms, 115ms, 120ms, 125ms, 130ms, 135ms, 140ms, 500ms


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution Query

python
response = cloudwatch.get_metric_statistics(
    Namespace='API',
    MetricName='ResponseTime',
    Period=60,
    Statistics=['Sum', 'Average', 'Minimum', 'Maximum', 'SampleCount']
)


Result:
json
{
  "Timestamp": "2026-02-09T14:00:00Z",
  "Sum": 1580.0,
  "Average": 158.0,
  "Minimum": 100.0,
  "Maximum": 500.0,
  "SampleCount": 10.0
}


Interpretation:
- Average looks okay (158ms)
- But one outlier (500ms) is hidden in the average
- Can't tell if it's a consistent problem or one-off

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Query

python
response = cloudwatch.get_metric_statistics(
    Namespace='API',
    MetricName='ResponseTime',
    Period=1,  # 1-second granularity
    Statistics=['Average', 'Maximum']
)


Result (showing each second):
json
[
  {"Timestamp": "2026-02-09T14:00:05Z", "Average": 100.0, "Maximum": 100.0},
  {"Timestamp": "2026-02-09T14:00:12Z", "Average": 105.0, "Maximum": 105.0},
  {"Timestamp": "2026-02-09T14:00:18Z", "Average": 110.0, "Maximum": 110.0},
  {"Timestamp": "2026-02-09T14:00:25Z", "Average": 115.0, "Maximum": 115.0},
  {"Timestamp": "2026-02-09T14:00:33Z", "Average": 120.0, "Maximum": 120.0},
  {"Timestamp": "2026-02-09T14:00:41Z", "Average": 125.0, "Maximum": 125.0},
  {"Timestamp": "2026-02-09T14:00:48Z", "Average": 130.0, "Maximum": 130.0},
  {"Timestamp": "2026-02-09T14:00:52Z", "Average": 135.0, "Maximum": 135.0},
  {"Timestamp": "2026-02-09T14:00:56Z", "Average": 140.0, "Maximum": 140.0},
  {"Timestamp": "2026-02-09T14:00:59Z", "Average": 500.0, "Maximum": 500.0}
]


Interpretation:
- Clear pattern: response times gradually increasing
- Spike at 14:00:59 (exactly 1 second before minute boundary)
- Can investigate what happened at that specific second

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## When to Use Each

### Use Standard Resolution When:
- Monitoring daily/hourly trends
- Metrics change slowly (database size, user count)
- Cost is primary concern
- Don't need sub-minute visibility

Examples:
- Daily active users
- Storage utilization
- Batch job duration
- Monthly revenue

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use High Resolution When:
- Need real-time monitoring
- Detecting brief spikes/anomalies
- Auto-scaling decisions
- Performance-critical applications
- Troubleshooting production issues

Examples:
- API response times
- Request rates
- CPU/memory spikes
- Payment processing latency
- Real-time gaming metrics

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Aggregation = CloudWatch combines multiple data points in a time period using statistics (Sum, Avg, Min, Max, Count)

Standard Resolution (60):
- Aggregates into 1-minute buckets
- Good for trends, costs the same
- Can't see sub-minute details

High Resolution (1):
- Aggregates into 1-second buckets
- Perfect for spike detection, costs the same
- Can query at 1-second granularity (for 3 hours)

Key insight: Same price, different granularity. Use high resolution for anything performance-critical where you need to detect 
and respond to issues quickly.