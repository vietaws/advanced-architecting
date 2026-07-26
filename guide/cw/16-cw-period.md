## CloudWatch Alarm Period Limits

The Period in CloudWatch alarms determines the time window for evaluating metrics. The valid range depends on the metric's 
storage resolution.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Period Limits by Metric Type

### Standard Resolution Metrics (StorageResolution: 60)

Minimum Period: 60 seconds (1 minute)
Maximum Period: 86,400 seconds (1 day)

Valid values: Must be a multiple of 60
- 60, 120, 180, 240, 300, 600, 900, 1800, 3600, 7200, 14400, 21600, 43200, 86400

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Metrics (StorageResolution: 1)

Minimum Period: 10 seconds (for alarms)
Maximum Period: 86,400 seconds (1 day)

Valid values: 
- **10 or 30 seconds** (for high-resolution alarms)
- **Any multiple of 60** (60, 120, 180, etc.)

Important: You can only use 10 or 30-second periods for the first 3 hours after the metric is published (high-resolution 
retention window).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Examples

### Standard Resolution - Valid Periods

python
# Valid: 60 seconds (minimum)
cloudwatch.put_metric_alarm(
    AlarmName='Alarm1',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=60,  # ✓ Valid
    Statistic='Average',
    Threshold=80.0
)

# Valid: 5 minutes
cloudwatch.put_metric_alarm(
    AlarmName='Alarm2',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=300,  # ✓ Valid (5 minutes)
    Statistic='Average',
    Threshold=80.0
)

# Valid: 1 day (maximum)
cloudwatch.put_metric_alarm(
    AlarmName='Alarm3',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=86400,  # ✓ Valid (1 day)
    Statistic='Average',
    Threshold=80.0
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution - Invalid Periods

python
# Invalid: Less than 60 seconds
cloudwatch.put_metric_alarm(
    AlarmName='InvalidAlarm1',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=30,  # ✗ Error: Period must be >= 60 for standard metrics
    Statistic='Average',
    Threshold=80.0
)

# Invalid: Not a multiple of 60
cloudwatch.put_metric_alarm(
    AlarmName='InvalidAlarm2',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=90,  # ✗ Error: Must be multiple of 60
    Statistic='Average',
    Threshold=80.0
)

# Invalid: Greater than 1 day
cloudwatch.put_metric_alarm(
    AlarmName='InvalidAlarm3',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=172800,  # ✗ Error: Maximum is 86400 (1 day)
    Statistic='Average',
    Threshold=80.0
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution - Valid Periods

python
# Valid: 10 seconds (minimum for high-res alarms)
cloudwatch.put_metric_alarm(
    AlarmName='HighResAlarm1',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=10,  # ✓ Valid (high-resolution)
    Statistic='Sum',
    Threshold=1000
)

# Valid: 30 seconds
cloudwatch.put_metric_alarm(
    AlarmName='HighResAlarm2',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=30,  # ✓ Valid (high-resolution)
    Statistic='Sum',
    Threshold=1000
)

# Valid: 60 seconds and above (any multiple of 60)
cloudwatch.put_metric_alarm(
    AlarmName='HighResAlarm3',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=60,  # ✓ Valid
    Statistic='Sum',
    Threshold=1000
)

# Valid: 5 minutes
cloudwatch.put_metric_alarm(
    AlarmName='HighResAlarm4',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=300,  # ✓ Valid
    Statistic='Sum',
    Threshold=1000
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution - Invalid Periods

python
# Invalid: Less than 10 seconds
cloudwatch.put_metric_alarm(
    AlarmName='InvalidHighRes1',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=5,  # ✗ Error: Minimum is 10 seconds
    Statistic='Sum',
    Threshold=1000
)

# Invalid: Between 10 and 30 (only 10 or 30 allowed)
cloudwatch.put_metric_alarm(
    AlarmName='InvalidHighRes2',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=20,  # ✗ Error: Must be 10, 30, or multiple of 60
    Statistic='Sum',
    Threshold=1000
)

# Invalid: Between 30 and 60
cloudwatch.put_metric_alarm(
    AlarmName='InvalidHighRes3',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=45,  # ✗ Error: Must be 10, 30, or multiple of 60
    Statistic='Sum',
    Threshold=1000
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Valid Period Values Summary

### For Standard Resolution Metrics:
60, 120, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720, 780, 840, 900,
960, 1020, 1080, 1140, 1200, 1260, 1320, 1380, 1440, 1500, 1560, 1620, 1680,
1740, 1800, 1860, 1920, 1980, 2040, 2100, 2160, 2220, 2280, 2340, 2400, 2460,
2520, 2580, 2640, 2700, 2760, 2820, 2880, 2940, 3000, 3060, 3120, 3180, 3240,
3300, 3360, 3420, 3480, 3540, 3600, ..., 86400

(Any multiple of 60 up to 86,400)

### For High Resolution Metrics:
10, 30, 60, 120, 180, 240, 300, 360, 420, 480, 540, 600, ..., 86400

(10, 30, or any multiple of 60 up to 86,400)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Common Period Values

| Period (seconds) | Duration | Use Case |
|-----------------|----------|----------|
| 10 | 10 seconds | Critical real-time monitoring (high-res only) |
| 30 | 30 seconds | Fast response auto-scaling (high-res only) |
| 60 | 1 minute | Standard monitoring |
| 300 | 5 minutes | General application monitoring |
| 600 | 10 minutes | Less critical metrics |
| 900 | 15 minutes | Slow-changing metrics |
| 3600 | 1 hour | Daily trend monitoring |
| 21600 | 6 hours | Long-term trends |
| 86400 | 1 day | Daily aggregations (maximum) |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Practical Examples

### Example 1: Auto-Scaling with Different Periods

python
# Fast scale-up (high-resolution, 10-second period)
cloudwatch.put_metric_alarm(
    AlarmName='FastScaleUp',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=10,  # Minimum for high-res
    EvaluationPeriods=3,  # 30 seconds total
    Threshold=80.0,
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=['arn:aws:autoscaling:...:scalingPolicy:.../scale-up']
)

# Slow scale-down (standard, 5-minute period)
cloudwatch.put_metric_alarm(
    AlarmName='SlowScaleDown',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=300,  # 5 minutes
    EvaluationPeriods=4,  # 20 minutes total
    Threshold=30.0,
    ComparisonOperator='LessThanThreshold',
    AlarmActions=['arn:aws:autoscaling:...:scalingPolicy:.../scale-down']
)


Rationale: 
- Scale up quickly (30 seconds) to handle traffic spikes
- Scale down slowly (20 minutes) to avoid flapping

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 2: Multi-Tier Monitoring

python
# Tier 1: Immediate alert (10-second period)
cloudwatch.put_metric_alarm(
    AlarmName='CriticalLatency',
    MetricName='ResponseTime',
    Namespace='MyApp',
    Period=10,  # Fastest detection
    EvaluationPeriods=2,  # 20 seconds
    Threshold=5000,  # 5 seconds
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=['arn:aws:sns:...:critical-alerts']
)

# Tier 2: Warning alert (1-minute period)
cloudwatch.put_metric_alarm(
    AlarmName='WarningLatency',
    MetricName='ResponseTime',
    Namespace='MyApp',
    Period=60,  # 1 minute
    EvaluationPeriods=3,  # 3 minutes
    Threshold=2000,  # 2 seconds
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=['arn:aws:sns:...:warning-alerts']
)

# Tier 3: Trend monitoring (1-hour period)
cloudwatch.put_metric_alarm(
    AlarmName='TrendLatency',
    MetricName='ResponseTime',
    Namespace='MyApp',
    Period=3600,  # 1 hour
    EvaluationPeriods=2,  # 2 hours
    Threshold=1000,  # 1 second
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=['arn:aws:sns:...:trend-alerts']
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 3: Daily Aggregation (Maximum Period)

python
# Monitor daily error count
cloudwatch.put_metric_alarm(
    AlarmName='DailyErrorThreshold',
    MetricName='ErrorCount',
    Namespace='MyApp',
    Period=86400,  # 1 day (maximum)
    EvaluationPeriods=1,  # 1 day
    Statistic='Sum',
    Threshold=1000,  # Max 1000 errors per day
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=['arn:aws:sns:...:daily-report']
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Important Constraints

### 1. Period Must Match Metric Resolution

python
# This will work but won't give you 10-second granularity
# if the metric has standard resolution (60)
cloudwatch.put_metric_alarm(
    AlarmName='WontWork',
    MetricName='CPUUtilization',  # Standard AWS metric (60-second resolution)
    Namespace='AWS/EC2',
    Period=10,  # ✗ Will error or fall back to 60 seconds
    Threshold=80.0
)


Solution: Use high-resolution custom metrics if you need 10 or 30-second periods.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. High-Resolution Data Retention

High-resolution data (1-second) is only retained for 3 hours. After that, it's aggregated to 1-minute resolution.

python
# This alarm works for first 3 hours
cloudwatch.put_metric_alarm(
    AlarmName='HighResAlarm',
    MetricName='RequestCount',
    Namespace='MyApp',
    Period=10,  # Works for 3 hours
    Threshold=1000
)

# After 3 hours, effectively becomes:
# Period=60 (minimum available granularity)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Evaluation Period Calculation

Total evaluation time = Period × EvaluationPeriods

python
# Example: 10-second period, 6 evaluation periods
Period=10
EvaluationPeriods=6
# Total evaluation time = 10 × 6 = 60 seconds (1 minute)

# Example: 5-minute period, 3 evaluation periods
Period=300
EvaluationPeriods=3
# Total evaluation time = 300 × 3 = 900 seconds (15 minutes)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary Table

| Metric Type | Min Period | Max Period | Valid Values |
|-------------|-----------|-----------|--------------|
| Standard Resolution | 60 seconds | 86,400 seconds | Multiples of 60 |
| High Resolution | 10 seconds | 86,400 seconds | 10, 30, or multiples of 60 |

Key Points:
- Standard metrics: 60 seconds minimum
- High-resolution metrics: 10 seconds minimum (for alarms)
- Maximum for both: 86,400 seconds (1 day)
- High-resolution periods (10, 30 seconds) only work for first 3 hours of data
- After 3 hours, high-resolution data is aggregated to 1-minute resolution