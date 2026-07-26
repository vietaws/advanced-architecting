## EC2 Monitoring Types

EC2 instances have two monitoring modes that directly affect CloudWatch alarm periods:

### Basic Monitoring (Default)
- **Metric frequency**: Every 5 minutes
- **Cost**: FREE
- **Storage resolution**: 300 seconds (5 minutes)
- **Minimum alarm period**: 300 seconds (5 minutes)

### Detailed Monitoring
- **Metric frequency**: Every 1 minute
- **Cost**: $2.10 per instance per month
- **Storage resolution**: 60 seconds (1 minute)
- **Minimum alarm period**: 60 seconds (1 minute)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Impact on Auto Scaling Alarms

The monitoring type determines the minimum period you can use in CloudWatch alarms for auto-scaling.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 1: Basic Monitoring (5-minute periods)

### EC2 Configuration
python
# Launch Configuration with Basic Monitoring (default)
autoscaling = boto3.client('autoscaling')

autoscaling.create_launch_configuration(
    LaunchConfigurationName='basic-monitoring-lc',
    ImageId='ami-12345678',
    InstanceType='t3.medium',
    InstanceMonitoring={
        'Enabled': False  # Basic monitoring (5-minute intervals)
    }
)

autoscaling.create_auto_scaling_group(
    AutoScalingGroupName='webapp-asg',
    LaunchConfigurationName='basic-monitoring-lc',
    MinSize=2,
    MaxSize=10,
    DesiredCapacity=2
)


### Scale-Up Alarm (Basic Monitoring)
python
cloudwatch = boto3.client('cloudwatch')

# With basic monitoring, minimum period is 300 seconds
cloudwatch.put_metric_alarm(
    AlarmName='ScaleUp-Basic',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=300,  # 5 minutes (minimum for basic monitoring)
    EvaluationPeriods=2,  # 10 minutes total
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:...'
    ]
)


### Timeline: Traffic Spike with Basic Monitoring
Time        CPU%    Metric Reported    Alarm Evaluation    Action
14:00:00    30%     -                  -                   Normal
14:01:00    85%     -                  -                   (no data yet)
14:02:00    85%     -                  -                   (no data yet)
14:03:00    85%     -                  -                   (no data yet)
14:04:00    85%     -                  -                   (no data yet)
14:05:00    85%     85% (avg 14:00-14:05)  Period 1 breached   Monitoring...
14:06:00    85%     -                  -                   (no data yet)
14:07:00    85%     -                  -                   (no data yet)
14:08:00    85%     -                  -                   (no data yet)
14:09:00    85%     -                  -                   (no data yet)
14:10:00    85%     85% (avg 14:05-14:10)  Period 2 breached   ALARM! Scale up
14:10:05    -       -                  -                   Launching instances
14:12:00    -       -                  -                   Instances in service


Detection time: 10 minutes from spike start
Total time to scale: ~12 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: Detailed Monitoring (1-minute periods)

### EC2 Configuration
python
# Launch Configuration with Detailed Monitoring
autoscaling.create_launch_configuration(
    LaunchConfigurationName='detailed-monitoring-lc',
    ImageId='ami-12345678',
    InstanceType='t3.medium',
    InstanceMonitoring={
        'Enabled': True  # Detailed monitoring (1-minute intervals)
    }
)

autoscaling.create_auto_scaling_group(
    AutoScalingGroupName='webapp-asg-detailed',
    LaunchConfigurationName='detailed-monitoring-lc',
    MinSize=2,
    MaxSize=10,
    DesiredCapacity=2
)


### Scale-Up Alarm (Detailed Monitoring)
python
# With detailed monitoring, minimum period is 60 seconds
cloudwatch.put_metric_alarm(
    AlarmName='ScaleUp-Detailed',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=60,  # 1 minute (minimum for detailed monitoring)
    EvaluationPeriods=2,  # 2 minutes total
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg-detailed'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:...'
    ]
)


### Timeline: Traffic Spike with Detailed Monitoring
Time        CPU%    Metric Reported    Alarm Evaluation    Action
14:00:00    30%     30%                OK                  Normal
14:01:00    85%     85%                Period 1 breached   Monitoring...
14:02:00    85%     85%                Period 2 breached   ALARM! Scale up
14:02:05    -       -                  -                   Launching instances
14:04:00    -       -                  -                   Instances in service


Detection time: 2 minutes from spike start
Total time to scale: ~4 minutes

Improvement: 8 minutes faster than basic monitoring

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Side-by-Side Comparison

### Scenario: E-commerce flash sale, CPU spikes to 90%

| Aspect | Basic Monitoring | Detailed Monitoring |
|--------|-----------------|-------------------|
| Metric interval | 5 minutes | 1 minute |
| Minimum alarm period | 300 seconds | 60 seconds |
| Typical alarm config | Period=300, Eval=2 | Period=60, Eval=2 |
| Detection time | 10 minutes | 2 minutes |
| Time to scale | ~12 minutes | ~4 minutes |
| Cost per instance | FREE | $2.10/month |
| Cost for 10 instances | $0 | $21/month |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What Happens If You Use Wrong Period?

### Attempt 1: 60-second period with Basic Monitoring

python
# EC2 has basic monitoring (5-minute intervals)
cloudwatch.put_metric_alarm(
    AlarmName='WontWorkWell',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=60,  # ✗ Trying to use 1-minute period
    EvaluationPeriods=2,
    Threshold=70.0,
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'  # Basic monitoring ASG
    }]
)


Result: 
- Alarm will be in INSUFFICIENT_DATA state most of the time
- Metrics only arrive every 5 minutes, but alarm expects data every 1 minute
- Auto-scaling won't work reliably

Timeline:
Time        Metric Available?    Alarm State
14:00:00    Yes (from 13:55-14:00)    OK
14:01:00    No                   INSUFFICIENT_DATA
14:02:00    No                   INSUFFICIENT_DATA
14:03:00    No                   INSUFFICIENT_DATA
14:04:00    No                   INSUFFICIENT_DATA
14:05:00    Yes (from 14:00-14:05)    OK or ALARM (unreliable)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Attempt 2: 5-minute period with Detailed Monitoring

python
# EC2 has detailed monitoring (1-minute intervals)
cloudwatch.put_metric_alarm(
    AlarmName='WorksButSlow',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Period=300,  # ✓ Valid but not optimal
    EvaluationPeriods=2,
    Threshold=70.0,
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg-detailed'  # Detailed monitoring ASG
    }]
)


Result: 
- Works correctly
- But you're paying for detailed monitoring ($2.10/instance/month) without getting the benefit
- Still takes 10 minutes to detect issues

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Auto Scaling Setup

### Production Configuration: Detailed Monitoring

python
# Launch Template with Detailed Monitoring
ec2 = boto3.client('ec2')

launch_template = ec2.create_launch_template(
    LaunchTemplateName='webapp-template',
    LaunchTemplateData={
        'ImageId': 'ami-12345678',
        'InstanceType': 't3.medium',
        'Monitoring': {
            'Enabled': True  # Detailed monitoring
        }
    }
)

# Auto Scaling Group
autoscaling.create_auto_scaling_group(
    AutoScalingGroupName='webapp-asg',
    LaunchTemplate={
        'LaunchTemplateName': 'webapp-template',
        'Version': '$Latest'
    },
    MinSize=2,
    MaxSize=20,
    DesiredCapacity=2,
    TargetGroupARNs=['arn:aws:elasticloadbalancing:...'],
    HealthCheckType='ELB',
    HealthCheckGracePeriod=300
)

# Scale-up alarm (aggressive)
cloudwatch.put_metric_alarm(
    AlarmName='ScaleUp-Fast',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=60,  # 1 minute
    EvaluationPeriods=2,  # 2 minutes total
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

# Scale-down alarm (conservative)
cloudwatch.put_metric_alarm(
    AlarmName='ScaleDown-Slow',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=300,  # 5 minutes (can use longer even with detailed monitoring)
    EvaluationPeriods=4,  # 20 minutes total
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


Strategy:
- Scale up fast (2 minutes) to handle traffic
- Scale down slow (20 minutes) to avoid flapping
- Use detailed monitoring for fast response

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost-Benefit Analysis

### Scenario: Auto Scaling Group with 5 instances average

Basic Monitoring:
- Cost: $0
- Detection time: 10 minutes
- Potential impact: Users experience slowness for 10-12 minutes

Detailed Monitoring:
- Cost: 5 instances × $2.10 = $10.50/month
- Detection time: 2 minutes
- Potential impact: Users experience slowness for 2-4 minutes

Value calculation:
- If 1 minute of downtime costs $100 in lost revenue
- Basic monitoring: 10 minutes × $100 = $1,000 potential loss
- Detailed monitoring: 2 minutes × $100 = $200 potential loss
- Savings: $800 per incident
- Break-even: 1 incident every 76 months (detailed monitoring pays for itself)

For most production workloads: Detailed monitoring is worth it.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Enabling Detailed Monitoring

### For Existing Instances
bash
# Enable detailed monitoring on running instance
aws ec2 monitor-instances --instance-ids i-1234567890abcdef0

# Disable detailed monitoring
aws ec2 unmonitor-instances --instance-ids i-1234567890abcdef0


### For Auto Scaling Group (Launch Template)
python
ec2.create_launch_template(
    LaunchTemplateName='my-template',
    LaunchTemplateData={
        'ImageId': 'ami-12345678',
        'InstanceType': 't3.medium',
        'Monitoring': {
            'Enabled': True  # Detailed monitoring for all new instances
        }
    }
)


### For Auto Scaling Group (Launch Configuration - Legacy)
python
autoscaling.create_launch_configuration(
    LaunchConfigurationName='my-lc',
    ImageId='ami-12345678',
    InstanceType='t3.medium',
    InstanceMonitoring={
        'Enabled': True  # Detailed monitoring
    }
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Monitoring Type | Metric Interval | Min Alarm Period | Detection Time | Cost/Instance | Best For |
|----------------|----------------|------------------|----------------|---------------|----------|
| Basic | 5 minutes | 300 seconds | 10+ minutes | FREE | Dev/test, non-critical |
| Detailed | 1 minute | 60 seconds | 2+ minutes | $2.10/month | Production, critical apps |

Key Relationships:
- **Basic monitoring** → 5-minute metrics → 5-minute minimum alarm period → Slow auto-scaling
- **Detailed monitoring** → 1-minute metrics → 1-minute minimum alarm period → Fast auto-scaling

Best Practice: 
- Use detailed monitoring for production Auto Scaling Groups
- Use basic monitoring for dev/test environments to save costs
- Always match alarm period to monitoring type (300s for basic, 60s for detailed)