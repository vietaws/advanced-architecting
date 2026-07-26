## What is CloudWatch Alarm?

A CloudWatch Alarm monitors a metric and triggers actions when the metric crosses a threshold you define. It's the bridge between
monitoring (metrics) and automation (actions).

Alarm States:
- **OK** - Metric is within threshold
- **ALARM** - Metric breached threshold
- **INSUFFICIENT_DATA** - Not enough data to evaluate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How CloudWatch Alarms Work

Metric → Alarm Evaluates → State Change → Action Triggered


### Components:

1. Metric: What to monitor (CPU, memory, custom metric)
2. Statistic: How to aggregate (Average, Sum, Max, Min)
3. Period: Time window to evaluate (10 sec, 1 min, 5 min, etc.)
4. Threshold: Value that triggers alarm
5. Evaluation Periods: How many periods must breach before alarming
6. Datapoints to Alarm: How many of those periods must be breaching
7. Actions: What to do when alarm state changes (scale, notify, etc.)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Relationship with CloudWatch Metrics

CloudWatch Alarms REQUIRE CloudWatch Metrics - they monitor metrics and trigger actions based on metric values.

CloudWatch Metrics (data) → CloudWatch Alarms (evaluation) → Actions (response)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Basic Alarm Example

python
import boto3

cloudwatch = boto3.client('cloudwatch')

# Create alarm on EC2 CPU metric
cloudwatch.put_metric_alarm(
    AlarmName='HighCPUAlarm',
    ComparisonOperator='GreaterThanThreshold',
    EvaluationPeriods=2,
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=300,  # 5 minutes
    Statistic='Average',
    Threshold=80.0,
    ActionsEnabled=True,
    AlarmActions=[
        'arn:aws:sns:us-east-1:123456789012:alert-topic'
    ],
    AlarmDescription='Alert when CPU exceeds 80%',
    Dimensions=[
        {
            'Name': 'InstanceId',
            'Value': 'i-1234567890abcdef0'
        }
    ]
)


How it works:
1. Every 5 minutes, CloudWatch calculates average CPU
2. If average > 80% for 2 consecutive periods (10 minutes total)
3. Alarm state changes from OK → ALARM
4. SNS notification sent

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Impact of Standard vs High Resolution on Auto Scaling

### Standard Resolution Auto Scaling

python
# Standard resolution metric (60-second minimum)
cloudwatch.put_metric_alarm(
    AlarmName='ScaleUp',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=60,  # 1 minute (minimum for standard)
    EvaluationPeriods=2,  # 2 minutes total
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:...'
    ]
)


Timeline:
14:00:00 - Traffic spike starts, CPU jumps to 85%
14:00:30 - CPU still at 85%
14:01:00 - Period 1 complete: Avg CPU = 85% (threshold breached)
14:01:30 - CPU still at 85%
14:02:00 - Period 2 complete: Avg CPU = 85% (threshold breached again)
14:02:00 - ALARM triggered, scaling action initiated
14:02:05 - Auto Scaling starts launching new instances
14:03:00 - New instances launching (takes 2-3 minutes)
14:05:00 - New instances in service, load distributed


Total time from spike to relief: ~5 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Auto Scaling

python
# High resolution metric (1-second minimum)
cloudwatch.put_metric_alarm(
    AlarmName='ScaleUpFast',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=10,  # 10 seconds (can go as low as 10 for high-res)
    EvaluationPeriods=2,  # 20 seconds total
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:...'
    ]
)


Timeline:
14:00:00 - Traffic spike starts, CPU jumps to 85%
14:00:10 - Period 1 complete: Avg CPU = 85% (threshold breached)
14:00:20 - Period 2 complete: Avg CPU = 85% (threshold breached again)
14:00:20 - ALARM triggered, scaling action initiated
14:00:25 - Auto Scaling starts launching new instances
14:02:25 - New instances in service, load distributed


Total time from spike to relief: ~2.5 minutes

Improvement: 2.5 minutes faster response (50% reduction)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Detailed Comparison: Standard vs High Resolution

### Scenario: E-commerce site during flash sale

Traffic pattern:
Normal: 100 req/sec, CPU 30%
Flash sale starts: 1,000 req/sec, CPU spikes to 90%


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution (60-second period)

python
# Alarm configuration
Period=60  # 1 minute
EvaluationPeriods=2  # 2 consecutive minutes
Threshold=70.0


Evaluation:
Time        CPU%    Period Avg    Alarm State    Action
14:00:00    30%     -              OK             None
14:00:15    90%     -              OK             None (still in period)
14:00:30    90%     -              OK             None (still in period)
14:00:45    90%     -              OK             None (still in period)
14:01:00    90%     90%            OK             None (need 2 periods)
14:01:15    90%     -              OK             None
14:01:30    90%     -              OK             None
14:01:45    90%     -              OK             None
14:02:00    90%     90%            ALARM          Scale up triggered!
14:02:05    -       -              ALARM          Launching instances...
14:04:00    -       -              ALARM          Instances in service
14:05:00    60%     60%            OK             Load normalized


Impact:
- Users experience slow response for 2 minutes before scaling starts
- 4 minutes total before relief
- Potential lost sales, abandoned carts

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution (10-second period)

python
# Alarm configuration
Period=10  # 10 seconds
EvaluationPeriods=2  # 20 seconds total
Threshold=70.0


Evaluation:
Time        CPU%    Period Avg    Alarm State    Action
14:00:00    30%     30%            OK             None
14:00:10    90%     90%            OK             None (need 2 periods)
14:00:20    90%     90%            ALARM          Scale up triggered!
14:00:25    -       -              ALARM          Launching instances...
14:02:25    -       -              ALARM          Instances in service
14:03:00    60%     60%            OK             Load normalized


Impact:
- Users experience slow response for only 20 seconds
- 2.5 minutes total before relief
- Minimal impact on user experience

Benefit: 1 minute 40 seconds faster response

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Auto Scaling Example

### Setup: Web application with Auto Scaling Group

Infrastructure:
- Min instances: 2
- Max instances: 10
- Desired: 2
- Scale-up policy: Add 2 instances when CPU > 70%
- Scale-down policy: Remove 1 instance when CPU < 30%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Standard Resolution Configuration

python
# Scale-up alarm
cloudwatch.put_metric_alarm(
    AlarmName='WebApp-ScaleUp',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=60,  # 1 minute
    EvaluationPeriods=2,  # 2 minutes
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:policy-id:autoScalingGroupName/webapp-asg:policyName/scale-up'
    ]
)

# Scale-down alarm
cloudwatch.put_metric_alarm(
    AlarmName='WebApp-ScaleDown',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=300,  # 5 minutes (longer to avoid flapping)
    EvaluationPeriods=2,  # 10 minutes
    Threshold=30.0,
    ComparisonOperator='LessThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:policy-id:autoScalingGroupName/webapp-asg:policyName/scale-down'
    ]
)


Behavior during traffic spike:
Time        Instances    CPU%    Action
14:00       2            30%     Normal
14:01       2            85%     Monitoring...
14:02       2            85%     Monitoring...
14:03       2            85%     Scale-up alarm triggered
14:03       4            65%     Launching 2 instances
14:05       4            65%     Instances in service
14:10       4            25%     Monitoring...
14:15       4            25%     Monitoring...
14:20       4            25%     Monitoring...
14:25       4            25%     Scale-down alarm triggered
14:26       3            30%     Terminating 1 instance


Response time: 3 minutes to detect, 5 minutes to scale

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Configuration

python
# Scale-up alarm with high resolution
cloudwatch.put_metric_alarm(
    AlarmName='WebApp-ScaleUp-Fast',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=10,  # 10 seconds
    EvaluationPeriods=3,  # 30 seconds (3 datapoints)
    DatapointsToAlarm=2,  # 2 out of 3 must breach
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:policy-id:autoScalingGroupName/webapp-asg:policyName/scale-up'
    ]
)

# Scale-down alarm (can stay standard)
cloudwatch.put_metric_alarm(
    AlarmName='WebApp-ScaleDown',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=300,  # 5 minutes (no rush to scale down)
    EvaluationPeriods=2,
    Threshold=30.0,
    ComparisonOperator='LessThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:policy-id:autoScalingGroupName/webapp-asg:policyName/scale-down'
    ]
)


Behavior during traffic spike:
Time        Instances    CPU%    Action
14:00:00    2            30%     Normal
14:00:10    2            85%     Monitoring...
14:00:20    2            85%     Monitoring...
14:00:30    2            85%     Scale-up alarm triggered (30 sec)
14:00:30    4            65%     Launching 2 instances
14:02:30    4            65%     Instances in service
14:10:00    4            25%     Monitoring...
14:15:00    4            25%     Monitoring...
14:20:00    4            25%     Scale-down alarm triggered
14:21:00    3            30%     Terminating 1 instance


Response time: 30 seconds to detect, 2.5 minutes to scale

Improvement: 2.5 minutes faster detection and response

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Alarm Evaluation Logic

### Example: Understanding "M out of N" datapoints

python
cloudwatch.put_metric_alarm(
    AlarmName='FlexibleAlarm',
    MetricName='CPUUtilization',
    Period=60,
    EvaluationPeriods=5,  # Look at last 5 periods
    DatapointsToAlarm=3,  # 3 out of 5 must breach
    Threshold=80.0
)


Scenario:
Period    CPU%    Breached?    Evaluation
1         85%     Yes          1/5 breached (OK)
2         75%     No           1/5 breached (OK)
3         90%     Yes          2/5 breached (OK)
4         82%     Yes          3/5 breached (ALARM!)
5         78%     No           3/5 breached (ALARM)


Benefit: Reduces false alarms from temporary spikes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Implications

### Standard Resolution Alarm

python
Period=60  # 1 minute
EvaluationPeriods=2


Alarm cost: $0.10 per alarm per month (standard metric alarm)

Metric evaluation frequency: Every 60 seconds

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### High Resolution Alarm

python
Period=10  # 10 seconds
EvaluationPeriods=3


Alarm cost: $0.30 per alarm per month (high-resolution alarm)

Metric evaluation frequency: Every 10 seconds (6x more frequent)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Cost Comparison for Auto Scaling Setup

Standard Resolution:
- 1 scale-up alarm: $0.10
- 1 scale-down alarm: $0.10
- **Total: $0.20/month**

High Resolution:
- 1 scale-up alarm (high-res): $0.30
- 1 scale-down alarm (standard): $0.10
- **Total: $0.40/month**

Additional cost: $0.20/month per Auto Scaling Group

Value: 2+ minutes faster response time for $0.20/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Best Practices

### Use Standard Resolution Alarms When:
- Monitoring non-critical metrics
- Gradual changes expected (storage, daily users)
- Cost is primary concern
- Scaling can wait 2-5 minutes

Example:
python
# Non-critical: Database storage
cloudwatch.put_metric_alarm(
    AlarmName='LowDiskSpace',
    MetricName='FreeStorageSpace',
    Period=300,  # 5 minutes is fine
    Threshold=10737418240  # 10 GB
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Use High Resolution Alarms When:
- Performance-critical applications
- Need fast auto-scaling response
- Detecting brief spikes matters
- User experience depends on quick response

Example:
python
# Critical: API response time
cloudwatch.put_metric_alarm(
    AlarmName='HighLatency',
    MetricName='ResponseTime',
    Period=10,  # 10 seconds for fast detection
    Threshold=1000  # 1 second
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Aspect | Standard Resolution | High Resolution |
|--------|-------------------|-----------------|
| Minimum period | 60 seconds | 10 seconds (for alarms) |
| Detection time | 2-5 minutes typical | 20-60 seconds typical |
| Auto-scaling response | 3-5 minutes | 30 seconds - 2 minutes |
| Alarm cost | $0.10/month | $0.30/month |
| Best for | Non-critical, cost-sensitive | Performance-critical, fast response |
| False alarm risk | Lower (more data averaged) | Higher (more sensitive) |

Key Takeaway: High-resolution alarms enable 2-3x faster auto-scaling response for only $0.20 more per month. For performance-
critical applications, this is almost always worth it.