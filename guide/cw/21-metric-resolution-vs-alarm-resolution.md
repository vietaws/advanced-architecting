## Key Concept: Metric Resolution vs Alarm Resolution

They are related but NOT the same thing.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 1. Metric Resolution (Storage)

Determines how CloudWatch STORES the metric data

### Standard Resolution Metric
python
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'RequestCount',
        'Value': 100,
        'StorageResolution': 60  # Standard: 60-second storage
    }]
)

- Data stored in 60-second buckets
- Can query at 60-second minimum granularity

### High Resolution Metric
python
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'RequestCount',
        'Value': 100,
        'StorageResolution': 1  # High-res: 1-second storage
    }]
)

- Data stored in 1-second buckets
- Can query at 1-second minimum granularity (for first 3 hours)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## 2. Alarm Resolution (Evaluation)

Determines how frequently CloudWatch EVALUATES the alarm

### Standard Resolution Alarm
python
cloudwatch.put_metric_alarm(
    AlarmName='StandardAlarm',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=60,  # Evaluate every 60 seconds
    Threshold=1000
)

- Evaluates metric every 60+ seconds
- Alarm cost: $0.10/month

### High Resolution Alarm
python
cloudwatch.put_metric_alarm(
    AlarmName='HighResAlarm',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=10,  # Evaluate every 10 seconds
    Threshold=1000
)

- Evaluates metric every 10 or 30 seconds
- Alarm cost: $0.30/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Relationship Matrix

| Metric Resolution | Alarm Period | Valid? | Alarm Type | Cost |
|------------------|--------------|--------|------------|------|
| Standard (60) | 60+ seconds | ✓ Yes | Standard | $0.10/month |
| Standard (60) | 10 or 30 seconds | ✗ No | N/A | N/A |
| High-res (1) | 60+ seconds | ✓ Yes | Standard | $0.10/month |
| High-res (1) | 10 or 30 seconds | ✓ Yes | High-res | $0.30/month |

Key Rule: 
- **Alarm period must match or exceed metric resolution**
- High-resolution metrics can use both standard and high-resolution alarms
- Standard metrics can ONLY use standard alarms (60+ second periods)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 1: Standard Metric + Standard Alarm

python
# Publish standard resolution metric
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'CPUUsage',
        'Value': 75.0,
        'StorageResolution': 60  # Standard metric
    }]
)

# Create standard resolution alarm
cloudwatch.put_metric_alarm(
    AlarmName='CPUAlarm',
    MetricName='CPUUsage',
    Namespace='MyApp',
    Period=60,  # ✓ Valid: 60 seconds
    EvaluationPeriods=2,
    Threshold=80.0,
    ComparisonOperator='GreaterThanThreshold'
)


Result: ✓ Works
- Metric stored every 60 seconds
- Alarm evaluates every 60 seconds
- Alarm cost: $0.10/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: Standard Metric + High-Res Alarm (INVALID)

python
# Publish standard resolution metric
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'CPUUsage',
        'Value': 75.0,
        'StorageResolution': 60  # Standard metric
    }]
)

# Try to create high-resolution alarm
cloudwatch.put_metric_alarm(
    AlarmName='CPUAlarmFast',
    MetricName='CPUUsage',
    Namespace='MyApp',
    Period=10,  # ✗ Invalid: metric only has 60-second data
    EvaluationPeriods=2,
    Threshold=80.0,
    ComparisonOperator='GreaterThanThreshold'
)


Result: ✗ Fails or goes to INSUFFICIENT_DATA
- Metric only has data every 60 seconds
- Alarm expects data every 10 seconds
- Alarm will be in INSUFFICIENT_DATA state most of the time

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 3: High-Res Metric + Standard Alarm

python
# Publish high-resolution metric
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'RequestLatency',
        'Value': 250,
        'StorageResolution': 1  # High-resolution metric
    }]
)

# Create standard resolution alarm
cloudwatch.put_metric_alarm(
    AlarmName='LatencyAlarm',
    MetricName='RequestLatency',
    Namespace='MyApp',
    Period=60,  # ✓ Valid: can use 60-second period on high-res metric
    EvaluationPeriods=2,
    Threshold=500,
    ComparisonOperator='GreaterThanThreshold'
)


Result: ✓ Works
- Metric stored every 1 second
- Alarm evaluates every 60 seconds (aggregates 60 data points)
- Alarm cost: $0.10/month (standard alarm)
- **You're paying for high-res metric storage but not using it**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 4: High-Res Metric + High-Res Alarm (OPTIMAL)

python
# Publish high-resolution metric
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[{
        'MetricName': 'RequestLatency',
        'Value': 250,
        'StorageResolution': 1  # High-resolution metric
    }]
)

# Create high-resolution alarm
cloudwatch.put_metric_alarm(
    AlarmName='LatencyAlarmFast',
    MetricName='RequestLatency',
    Namespace='MyApp',
    Period=10,  # ✓ Valid: 10-second evaluation
    EvaluationPeriods=3,  # 30 seconds total
    Threshold=500,
    ComparisonOperator='GreaterThanThreshold'
)


Result: ✓ Works optimally
- Metric stored every 1 second
- Alarm evaluates every 10 seconds (aggregates 10 data points)
- Alarm cost: $0.30/month (high-resolution alarm)
- **Full benefit of high-resolution monitoring**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Visual Comparison

### Scenario: Publishing metric every second for 1 minute

Time (seconds): 0  5  10  15  20  25  30  35  40  45  50  55  60
Data points:    ●  ●  ●   ●   ●   ●   ●   ●   ●   ●   ●   ●   ●


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Metric (StorageResolution: 60)

How it's stored:
Bucket 0-60 seconds: Aggregated (Sum, Avg, Min, Max, Count)


Standard Alarm (Period: 60):
Evaluation at 60 seconds: ✓ Checks aggregated value


High-Res Alarm (Period: 10) - DOESN'T WORK:
Evaluation at 10 seconds: ✗ No data (INSUFFICIENT_DATA)
Evaluation at 20 seconds: ✗ No data (INSUFFICIENT_DATA)
Evaluation at 30 seconds: ✗ No data (INSUFFICIENT_DATA)
Evaluation at 40 seconds: ✗ No data (INSUFFICIENT_DATA)
Evaluation at 50 seconds: ✗ No data (INSUFFICIENT_DATA)
Evaluation at 60 seconds: ✓ Has data (but defeats purpose)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High-Res Metric (StorageResolution: 1)

How it's stored:
Bucket 0-1s: ●
Bucket 1-2s: ●
Bucket 2-3s: ●
... (60 individual buckets)


Standard Alarm (Period: 60):
Evaluation at 60 seconds: ✓ Aggregates all 60 data points


High-Res Alarm (Period: 10):
Evaluation at 10 seconds: ✓ Aggregates 10 data points (0-10s)
Evaluation at 20 seconds: ✓ Aggregates 10 data points (10-20s)
Evaluation at 30 seconds: ✓ Aggregates 10 data points (20-30s)
Evaluation at 40 seconds: ✓ Aggregates 10 data points (30-40s)
Evaluation at 50 seconds: ✓ Aggregates 10 data points (40-50s)
Evaluation at 60 seconds: ✓ Aggregates 10 data points (50-60s)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Implications

### Scenario: Monitoring API latency

Option 1: Standard Metric + Standard Alarm
python
# Metric
StorageResolution=60
Cost: $0.30/month per metric

# Alarm
Period=60
Cost: $0.10/month per alarm

Total: $0.40/month
Detection time: 2-5 minutes


Option 2: High-Res Metric + Standard Alarm (WASTEFUL)
python
# Metric
StorageResolution=1
Cost: $0.30/month per metric

# Alarm
Period=60
Cost: $0.10/month per alarm

Total: $0.40/month
Detection time: 2-5 minutes (same as Option 1!)

Problem: Paying for high-res metric but not using it

Option 3: High-Res Metric + High-Res Alarm (OPTIMAL)
python
# Metric
StorageResolution=1
Cost: $0.30/month per metric

# Alarm
Period=10
Cost: $0.30/month per alarm

Total: $0.60/month
Detection time: 20-30 seconds

Benefit: 5-10x faster detection for $0.20 more

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Example: API Monitoring

### Standard Resolution Setup

python
# Application publishes metric every request
def handle_request():
    start = time.time()
    response = process_request()
    latency = (time.time() - start) * 1000
    
    # Publish standard resolution
    cloudwatch.put_metric_data(
        Namespace='API',
        MetricData=[{
            'MetricName': 'Latency',
            'Value': latency,
            'Unit': 'Milliseconds',
            'StorageResolution': 60  # Standard
        }]
    )
    return response

# Standard alarm
cloudwatch.put_metric_alarm(
    AlarmName='HighLatency',
    MetricName='Latency',
    Namespace='API',
    Period=60,  # 1 minute
    EvaluationPeriods=3,  # 3 minutes
    Statistic='Average',
    Threshold=1000,
    ComparisonOperator='GreaterThanThreshold'
)


Timeline:
14:00:00  Latency spike to 2000ms
14:01:00  Period 1: Avg 2000ms (breached)
14:02:00  Period 2: Avg 2000ms (breached)
14:03:00  Period 3: Avg 2000ms (breached) → ALARM

Detection time: 3 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Setup

python
# Application publishes metric every request
def handle_request():
    start = time.time()
    response = process_request()
    latency = (time.time() - start) * 1000
    
    # Publish high resolution
    cloudwatch.put_metric_data(
        Namespace='API',
        MetricData=[{
            'MetricName': 'Latency',
            'Value': latency,
            'Unit': 'Milliseconds',
            'StorageResolution': 1  # High-resolution
        }]
    )
    return response

# High-resolution alarm
cloudwatch.put_metric_alarm(
    AlarmName='HighLatencyFast',
    MetricName='Latency',
    Namespace='API',
    Period=10,  # 10 seconds
    EvaluationPeriods=3,  # 30 seconds
    Statistic='Average',
    Threshold=1000,
    ComparisonOperator='GreaterThanThreshold'
)


Timeline:
14:00:00  Latency spike to 2000ms
14:00:10  Period 1: Avg 2000ms (breached)
14:00:20  Period 2: Avg 2000ms (breached)
14:00:30  Period 3: Avg 2000ms (breached) → ALARM

Detection time: 30 seconds (6x faster!)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary Table

| Aspect | Metric Resolution | Alarm Resolution |
|--------|------------------|------------------|
| What it controls | How data is STORED | How often alarm EVALUATES |
| Standard value | StorageResolution=60 | Period=60+ |
| High-res value | StorageResolution=1 | Period=10 or 30 |
| Cost (metric) | $0.30/month | N/A |
| Cost (alarm) | N/A | $0.10 (standard) or $0.30 (high-res) |
| Can mix? | Yes (high-res metric + standard alarm) | No (standard metric + high-res alarm fails) |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Takeaways

1. Metric resolution = storage granularity (60 or 1 second)
2. Alarm resolution = evaluation frequency (60+ or 10/30 seconds)
3. They are NOT the same but must be compatible
4. High-res metric can use standard OR high-res alarm
5. Standard metric can ONLY use standard alarm
6. High-res alarm REQUIRES high-res metric
7. Use high-res metric + high-res alarm together for fastest detection
8. Using high-res metric with standard alarm wastes the metric's capability

Best Practice: If you need fast detection, use BOTH high-resolution metric AND high-resolution alarm. If you only need one, you'
re not getting the full benefit.