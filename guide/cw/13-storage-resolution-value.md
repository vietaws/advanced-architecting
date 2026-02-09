## Valid Storage Resolution Values

CloudWatch supports only 2 values for StorageResolution:

1. 60 (default) - Standard resolution, 1-minute granularity
2. 1 - High resolution, 1-second granularity

No other values are allowed.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What Happens When Data Points Don't Match Resolution?

CloudWatch aggregates data points based on the storage resolution, regardless of how frequently you send them.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 1: Send More Frequently Than Resolution

### Setup: Standard Resolution (60 seconds)

python
import boto3
import time

cloudwatch = boto3.client('cloudwatch')

# Publish metric every 10 seconds
for i in range(6):
    cloudwatch.put_metric_data(
        Namespace='MyApp',
        MetricData=[{
            'MetricName': 'RequestCount',
            'Value': 1,
            'Unit': 'Count',
            'StorageResolution': 60,  # 1-minute resolution
            'Timestamp': time.time()
        }]
    )
    time.sleep(10)  # Send every 10 seconds


What happens:
- You send 6 data points in 1 minute (every 10 seconds)
- CloudWatch aggregates them into a single 1-minute data point
- When you query with Sum statistic: returns 6
- When you query with Average: returns 1
- When you query with SampleCount: returns 6

Result: All 6 values are stored and aggregated into 1-minute buckets.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: Send Less Frequently Than Resolution

### Setup: High Resolution (1 second)

python
# Publish metric every 30 seconds
for i in range(4):
    cloudwatch.put_metric_data(
        Namespace='MyApp',
        MetricData=[{
            'MetricName': 'ResponseTime',
            'Value': 100 + i * 10,  # 100, 110, 120, 130
            'Unit': 'Milliseconds',
            'StorageResolution': 1,  # 1-second resolution
            'Timestamp': time.time()
        }]
    )
    time.sleep(30)  # Send every 30 seconds


What happens:
- You send 1 data point every 30 seconds
- CloudWatch stores each data point at its timestamp
- When querying with 1-second period: you see data points at 0s, 30s, 60s, 90s (sparse)
- When querying with 1-minute period: CloudWatch aggregates available points

Result: You pay for high-resolution storage but don't get the benefit of 1-second granularity.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Visual Example: API Frequency vs Storage Resolution

### Scenario: Monitoring API requests over 2 minutes

Timeline: 0s → 120s

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Case A: Standard Resolution (60s), Send Every 10s

Send:     10s   20s   30s   40s   50s   60s   70s   80s   90s   100s  110s  120s
Values:   5     3     7     2     8     4     6     9     3     5     7     2

Storage Resolution: 60 seconds
Stored as:
  Minute 1 (0-60s):  [5, 3, 7, 2, 8, 4]  → Sum=29, Avg=4.83, Count=6
  Minute 2 (60-120s): [6, 9, 3, 5, 7, 2]  → Sum=32, Avg=5.33, Count=6


Query with 1-minute period:
Time        Sum    Avg    Count
0-60s       29     4.83   6
60-120s     32     5.33   6


Cost: Standard resolution = $0.30/month per metric

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Case B: High Resolution (1s), Send Every 10s

Send:     10s   20s   30s   40s   50s   60s   70s   80s   90s   100s  110s  120s
Values:   5     3     7     2     8     4     6     9     3     5     7     2

Storage Resolution: 1 second
Stored as:
  10s: 5
  20s: 3
  30s: 7
  40s: 2
  50s: 8
  60s: 4
  70s: 6
  80s: 9
  90s: 3
  100s: 5
  110s: 7
  120s: 2


Query with 1-second period (shows sparse data):
Time    Value
10s     5
20s     3
30s     7
...


Query with 10-second period:
Time      Sum    Avg    Count
0-10s     5      5      1
10-20s    3      3      1
20-30s    7      7      1
...


Cost: High resolution = $0.30/month per metric (same price, but can query at finer granularity)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Case C: High Resolution (1s), Send Every 1s

Send:     1s  2s  3s  4s  5s  ... 120s
Values:   5   3   7   2   8   ... 2

Storage Resolution: 1 second
Stored as:
  1s: 5
  2s: 3
  3s: 7
  4s: 2
  5s: 8
  ...
  120s: 2


Query with 1-second period (full granularity):
Time    Value
1s      5
2s      3
3s      7
4s      2
5s      8
...


Query with 10-second period:
Time      Sum    Avg    Count
0-10s     45     4.5    10
10-20s    52     5.2    10
...


Cost: High resolution = $0.30/month per metric

Benefit: Can see second-by-second trends, detect sub-minute spikes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Practical Example: API Response Time Monitoring

### Without High Resolution (Standard 60s)

python
# Send response time every request (hundreds per second)
cloudwatch.put_metric_data(
    Namespace='API',
    MetricData=[{
        'MetricName': 'ResponseTime',
        'Value': 245,  # milliseconds
        'Unit': 'Milliseconds',
        'StorageResolution': 60  # Standard resolution
    }]
)


Dashboard shows:
Time        Avg Response Time
14:00-14:01    250ms
14:01-14:02    245ms
14:02-14:03    800ms  ← Spike detected, but when exactly?
14:03-14:04    240ms


Problem: You know there was a spike in minute 14:02-14:03, but not the exact second.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### With High Resolution (1s)

python
# Same code, just change StorageResolution
cloudwatch.put_metric_data(
    Namespace='API',
    MetricData=[{
        'MetricName': 'ResponseTime',
        'Value': 245,
        'Unit': 'Milliseconds',
        'StorageResolution': 1  # High resolution
    }]
)


Dashboard shows (with 1-second period):
Time          Avg Response Time
14:02:00         240ms
14:02:01         245ms
14:02:02         250ms
14:02:03         255ms
14:02:04        2500ms  ← Exact spike at 14:02:04
14:02:05         260ms
14:02:06         245ms


Benefit: You know the spike happened exactly at 14:02:04, can correlate with deployment or other events.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Implications

### Scenario: 100 API endpoints, each tracked with ResponseTime metric

Standard Resolution:
- 100 metrics × $0.30 = $30/month
- Can query at 1-minute granularity

High Resolution:
- 100 metrics × $0.30 = $30/month (same price!)
- Can query at 1-second granularity

Key Point: High resolution costs the same, but gives you finer granularity when you need it.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Data Retention by Resolution

CloudWatch automatically aggregates data over time:

| Period | Retention |
|--------|-----------|
| 1 second (high-res) | 3 hours |
| 1 minute | 15 days |
| 5 minutes | 63 days |
| 1 hour | 455 days |

Example: High-resolution data sent today
- **0-3 hours**: Query at 1-second granularity
- **3 hours - 15 days**: Aggregated to 1-minute, query at 1-minute minimum
- **15 days - 63 days**: Aggregated to 5-minute, query at 5-minute minimum
- **63 days - 455 days**: Aggregated to 1-hour, query at 1-hour minimum

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices

### Use Standard Resolution (60) When:
- Monitoring trends over hours/days
- Cost-sensitive applications
- Metrics don't change rapidly (daily batch jobs, hourly reports)

python
# Example: Daily batch job duration
cloudwatch.put_metric_data(
    Namespace='BatchJobs',
    MetricData=[{
        'MetricName': 'JobDuration',
        'Value': 3600,
        'StorageResolution': 60  # Standard is fine
    }]
)


### Use High Resolution (1) When:
- Need sub-minute visibility
- Detecting short-lived spikes
- Real-time monitoring dashboards
- Auto-scaling decisions based on second-level metrics

python
# Example: Real-time API monitoring
cloudwatch.put_metric_data(
    Namespace='API',
    MetricData=[{
        'MetricName': 'RequestRate',
        'Value': 1500,
        'StorageResolution': 1  # High resolution for real-time
    }]
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Aspect | Standard (60) | High Resolution (1) |
|--------|---------------|---------------------|
| Valid value | 60 | 1 |
| Granularity | 1 minute | 1 second |
| Cost | $0.30/metric/month | $0.30/metric/month (same!) |
| Retention | 15 days at 1-min | 3 hours at 1-sec, then aggregated |
| Send more frequently | Aggregated into 1-min buckets | Stored at timestamp |
| Send less frequently | Works fine | Wastes high-res capability |
| Best for | Trends, cost-sensitive | Real-time, spike detection |

Key takeaway: Storage resolution defines how CloudWatch stores and aggregates your data, not how often you send it. You can send
data at any frequency, but it will be stored according to the resolution you specify.