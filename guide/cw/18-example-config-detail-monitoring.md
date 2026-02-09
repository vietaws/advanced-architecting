## Real-World Configuration Strategy

For large EC2 fleets (hundreds of instances), you need a cost-optimized monitoring strategy that balances observability with 
budget.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Analysis: 100 EC2 Instances

### Option 1: Detailed Monitoring on All Instances

Cost: 100 instances × $2.10/month = $210/month = $2,520/year


Pros: Fast auto-scaling (2-minute detection)
Cons: Expensive at scale

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Option 2: Basic Monitoring on All Instances

Cost: $0/month


Pros: Free
Cons: Slow auto-scaling (10-minute detection), poor visibility

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Option 3: Hybrid Approach (RECOMMENDED)

Strategy: Use detailed monitoring selectively + aggregate metrics

Cost breakdown:
- Critical instances (10%): 10 × $2.10 = $21/month
- Custom aggregate metrics: 5 metrics × $0.30 = $1.50/month
- High-res alarms: 3 × $0.30 = $0.90/month

Total: ~$23.40/month (89% savings vs full detailed monitoring)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Recommended Architecture

### 1. Auto Scaling Group Level Metrics (FREE)

AWS provides aggregate metrics for Auto Scaling Groups automatically at no cost.

python
# These metrics are FREE and available at 1-minute intervals
# No need to enable detailed monitoring on individual instances

cloudwatch.put_metric_alarm(
    AlarmName='ASG-ScaleUp',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=60,  # 1-minute aggregation across ALL instances
    EvaluationPeriods=2,
    Threshold=70.0,
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'  # Aggregate across entire ASG
    }],
    AlarmActions=['arn:aws:autoscaling:...:scalingPolicy:.../scale-up']
)


Key insight: ASG-level metrics aggregate data from all instances, even with basic monitoring!

How it works:
- Each instance reports CPU every 5 minutes (basic monitoring)
- CloudWatch aggregates these into ASG-level metric
- ASG metric updates every 1 minute (interpolated)
- You get near-real-time ASG monitoring for FREE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Selective Detailed Monitoring

Enable detailed monitoring only where needed:

python
# Launch Template with MIXED monitoring strategy
ec2 = boto3.client('ec2')

# Template for regular instances (basic monitoring)
regular_template = ec2.create_launch_template(
    LaunchTemplateName='webapp-regular',
    LaunchTemplateData={
        'ImageId': 'ami-12345678',
        'InstanceType': 't3.medium',
        'Monitoring': {
            'Enabled': False  # Basic monitoring (FREE)
        },
        'TagSpecifications': [{
            'ResourceType': 'instance',
            'Tags': [
                {'Key': 'MonitoringLevel', 'Value': 'basic'},
                {'Key': 'Role', 'Value': 'worker'}
            ]
        }]
    }
)

# Template for critical instances (detailed monitoring)
critical_template = ec2.create_launch_template(
    LaunchTemplateName='webapp-critical',
    LaunchTemplateData={
        'ImageId': 'ami-12345678',
        'InstanceType': 't3.large',
        'Monitoring': {
            'Enabled': True  # Detailed monitoring ($2.10/month)
        },
        'TagSpecifications': [{
            'ResourceType': 'instance',
            'Tags': [
                {'Key': 'MonitoringLevel', 'Value': 'detailed'},
                {'Key': 'Role', 'Value': 'api-gateway'}
            ]
        }]
    }
)


When to use detailed monitoring:
- API gateways / load balancer targets
- Database instances
- Cache servers (Redis, Memcached)
- Payment processing servers
- First 2-3 instances in each ASG (canaries)

When basic monitoring is fine:
- Worker instances in large pools
- Batch processing instances
- Background job processors
- Instances behind load balancers (monitor LB instead)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Custom Application Metrics (Cost-Effective)

Instead of detailed EC2 monitoring, publish custom metrics from your application:

python
# In your application code (runs on each instance)
import boto3
import psutil
import time

cloudwatch = boto3.client('cloudwatch')

def publish_custom_metrics():
    # Collect metrics
    cpu_percent = psutil.cpu_percent(interval=1)
    memory_percent = psutil.virtual_memory().percent
    active_connections = get_active_connections()  # Your app metric
    
    # Publish to CloudWatch with high resolution
    cloudwatch.put_metric_data(
        Namespace='MyApp/Performance',
        MetricData=[
            {
                'MetricName': 'ActiveConnections',
                'Value': active_connections,
                'Unit': 'Count',
                'StorageResolution': 1,  # High resolution
                'Dimensions': [
                    {'Name': 'AutoScalingGroup', 'Value': 'webapp-asg'},
                    {'Name': 'InstanceType', 'Value': 't3.medium'}
                ]
            },
            {
                'MetricName': 'MemoryUtilization',
                'Value': memory_percent,
                'Unit': 'Percent',
                'StorageResolution': 1,
                'Dimensions': [
                    {'Name': 'AutoScalingGroup', 'Value': 'webapp-asg'}
                ]
            }
        ]
    )

# Run every 60 seconds
while True:
    publish_custom_metrics()
    time.sleep(60)


Cost:
- 2 custom metrics × $0.30 = $0.60/month (regardless of instance count!)
- Metrics are aggregated at ASG level
- High-resolution capability for critical metrics

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. Use Application Load Balancer Metrics (FREE)

ALB provides rich metrics at no extra cost:

python
# Monitor ALB metrics instead of individual EC2 instances
cloudwatch.put_metric_alarm(
    AlarmName='ALB-HighLatency',
    MetricName='TargetResponseTime',
    Namespace='AWS/ApplicationELB',
    Statistic='Average',
    Period=60,
    EvaluationPeriods=2,
    Threshold=1.0,  # 1 second
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'LoadBalancer',
        'Value': 'app/my-alb/1234567890abcdef'
    }],
    AlarmActions=['arn:aws:autoscaling:...:scalingPolicy:.../scale-up']
)

# Monitor request count for scaling
cloudwatch.put_metric_alarm(
    AlarmName='ALB-HighRequestCount',
    MetricName='RequestCountPerTarget',
    Namespace='AWS/ApplicationELB',
    Statistic='Sum',
    Period=60,
    EvaluationPeriods=2,
    Threshold=1000,  # 1000 requests per target per minute
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'TargetGroup',
        'Value': 'targetgroup/my-tg/1234567890abcdef'
    }],
    AlarmActions=['arn:aws:autoscaling:...:scalingPolicy:.../scale-up']
)


Available ALB metrics (FREE):
- TargetResponseTime
- RequestCount
- RequestCountPerTarget
- HTTPCode_Target_2XX_Count
- HTTPCode_Target_4XX_Count
- HTTPCode_Target_5XX_Count
- UnHealthyHostCount
- HealthyHostCount

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Real-World Setup

### Infrastructure Code (Terraform-style)

python
import boto3

ec2 = boto3.client('ec2')
autoscaling = boto3.client('autoscaling')
cloudwatch = boto3.client('cloudwatch')
elbv2 = boto3.client('elbv2')

# 1. Create Launch Template (Basic Monitoring)
launch_template = ec2.create_launch_template(
    LaunchTemplateName='webapp-template',
    LaunchTemplateData={
        'ImageId': 'ami-12345678',
        'InstanceType': 't3.medium',
        'Monitoring': {
            'Enabled': False  # Basic monitoring - FREE
        },
        'UserData': '''#!/bin/bash
# Install CloudWatch agent for custom metrics
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "metrics": {
    "namespace": "MyApp/Performance",
    "metrics_collected": {
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MemoryUtilization", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DiskUtilization", "unit": "Percent"}
        ],
        "metrics_collection_interval": 300
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
'''
    }
)

# 2. Create Auto Scaling Group
autoscaling.create_auto_scaling_group(
    AutoScalingGroupName='webapp-asg',
    LaunchTemplate={
        'LaunchTemplateName': 'webapp-template',
        'Version': '$Latest'
    },
    MinSize=10,
    MaxSize=200,
    DesiredCapacity=50,
    TargetGroupARNs=['arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/webapp-tg/abc123'],
    HealthCheckType='ELB',
    HealthCheckGracePeriod=300,
    Tags=[
        {
            'Key': 'Environment',
            'Value': 'production',
            'PropagateAtLaunch': True
        }
    ]
)

# 3. Scale-Up Alarm (ASG-level CPU - FREE)
cloudwatch.put_metric_alarm(
    AlarmName='ASG-ScaleUp-CPU',
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
    ],
    AlarmDescription='Scale up when average CPU > 70% for 2 minutes'
)

# 4. Scale-Up Alarm (ALB Request Count - FREE)
cloudwatch.put_metric_alarm(
    AlarmName='ALB-ScaleUp-RequestCount',
    MetricName='RequestCountPerTarget',
    Namespace='AWS/ApplicationELB',
    Statistic='Sum',
    Period=60,
    EvaluationPeriods=2,
    Threshold=1000,  # 1000 req/min per target
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'TargetGroup',
        'Value': 'targetgroup/webapp-tg/abc123'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:policy-id:autoScalingGroupName/webapp-asg:policyName/scale-up'
    ],
    AlarmDescription='Scale up when request rate > 1000/min per instance'
)

# 5. Scale-Down Alarm (Conservative)
cloudwatch.put_metric_alarm(
    AlarmName='ASG-ScaleDown-CPU',
    MetricName='CPUUtilization',
    Namespace='AWS/EC2',
    Statistic='Average',
    Period=300,  # 5 minutes
    EvaluationPeriods=4,  # 20 minutes
    Threshold=30.0,
    ComparisonOperator='LessThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroupName',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:autoscaling:us-east-1:123456789012:scalingPolicy:policy-id:autoScalingGroupName/webapp-asg:policyName/scale-down'
    ],
    AlarmDescription='Scale down when average CPU < 30% for 20 minutes'
)

# 6. Custom Application Metric Alarm (High Resolution)
cloudwatch.put_metric_alarm(
    AlarmName='App-HighMemory',
    MetricName='MemoryUtilization',
    Namespace='MyApp/Performance',
    Statistic='Average',
    Period=60,
    EvaluationPeriods=3,
    Threshold=85.0,
    ComparisonOperator='GreaterThanThreshold',
    Dimensions=[{
        'Name': 'AutoScalingGroup',
        'Value': 'webapp-asg'
    }],
    AlarmActions=[
        'arn:aws:sns:us-east-1:123456789012:ops-alerts'
    ],
    AlarmDescription='Alert when memory > 85%'
)

# 7. ALB Health Alarm (FREE)
cloudwatch.put_metric_alarm(
    AlarmName='ALB-UnhealthyHosts',
    MetricName='UnHealthyHostCount',
    Namespace='AWS/ApplicationELB',
    Statistic='Average',
    Period=60,
    EvaluationPeriods=2,
    Threshold=1.0,
    ComparisonOperator='GreaterThanOrEqualToThreshold',
    Dimensions=[{
        'Name': 'TargetGroup',
        'Value': 'targetgroup/webapp-tg/abc123'
    }],
    AlarmActions=[
        'arn:aws:sns:us-east-1:123456789012:critical-alerts'
    ],
    AlarmDescription='Alert when any instance is unhealthy'
)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Breakdown: 100 Instances

### Traditional Approach (All Detailed Monitoring)
100 instances × $2.10/month = $210/month = $2,520/year


### Optimized Approach
Component                                    Cost/Month
─────────────────────────────────────────────────────
EC2 Basic Monitoring (100 instances)        $0
ASG-level metrics (automatic)               $0
ALB metrics (automatic)                     $0
Custom app metrics (5 metrics)              $1.50
CloudWatch agent (included)                 $0
Standard alarms (5 alarms)                  $0.50
High-resolution alarms (2 alarms)           $0.60
Detailed monitoring (5 critical instances)  $10.50
─────────────────────────────────────────────────────
TOTAL                                       $13.10/month

Annual savings: $2,520 - $157 = $2,363 (94% reduction)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring Strategy by Instance Role

### Web/API Servers (Behind ALB)
- **Monitoring**: Basic (FREE)
- **Reason**: ALB metrics provide sufficient visibility
- **Alarms**: ALB TargetResponseTime, RequestCountPerTarget

### Database Instances
- **Monitoring**: Detailed ($2.10/month each)
- **Reason**: Critical, need fast detection
- **Alarms**: CPU, Memory, Disk I/O, Connections

### Cache Servers (Redis/Memcached)
- **Monitoring**: Detailed ($2.10/month each)
- **Reason**: Performance-critical
- **Alarms**: Memory, Evictions, Hit Rate

### Worker/Batch Instances
- **Monitoring**: Basic (FREE)
- **Reason**: Not user-facing, can tolerate delays
- **Alarms**: ASG-level CPU, custom queue depth metric

### Bastion/Jump Hosts
- **Monitoring**: Basic (FREE)
- **Reason**: Low utilization, not critical
- **Alarms**: None (optional: SSH login alerts)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Advanced: Target Tracking Scaling (RECOMMENDED)

Instead of manual alarms, use Target Tracking - it's simpler and often more effective:

python
# Target Tracking Policy - maintains target CPU automatically
autoscaling.put_scaling_policy(
    AutoScalingGroupName='webapp-asg',
    PolicyName='target-tracking-cpu',
    PolicyType='TargetTrackingScaling',
    TargetTrackingConfiguration={
        'PredefinedMetricSpecification': {
            'PredefinedMetricType': 'ASGAverageCPUUtilization'
        },
        'TargetValue': 60.0,  # Maintain 60% CPU
        'ScaleInCooldown': 300,  # 5 minutes before scale down
        'ScaleOutCooldown': 60   # 1 minute before scale up again
    }
)

# Target Tracking on ALB Request Count
autoscaling.put_scaling_policy(
    AutoScalingGroupName='webapp-asg',
    PolicyName='target-tracking-requests',
    PolicyType='TargetTrackingScaling',
    TargetTrackingConfiguration={
        'PredefinedMetricSpecification': {
            'PredefinedMetricType': 'ALBRequestCountPerTarget',
            'ResourceLabel': 'app/my-alb/abc123/targetgroup/my-tg/def456'
        },
        'TargetValue': 1000.0,  # 1000 requests per target per minute
        'ScaleInCooldown': 300,
        'ScaleOutCooldown': 60
    }
)


Benefits:
- No manual alarm creation
- Automatically scales up AND down
- Predictive scaling (optional)
- Works with basic monitoring
- FREE (no alarm costs)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Monitoring Dashboard (Cost-Effective)

python
# Create dashboard with FREE metrics
cloudwatch.put_dashboard(
    DashboardName='webapp-production',
    DashboardBody='''{
        "widgets": [
            {
                "type": "metric",
                "properties": {
                    "metrics": [
                        ["AWS/EC2", "CPUUtilization", {"stat": "Average", "dimensions": {"AutoScalingGroupName": "webapp-asg"}}],
                        ["AWS/ApplicationELB", "TargetResponseTime", {"dimensions": {"LoadBalancer": "app/my-alb/abc123"}}],
                        ["AWS/ApplicationELB", "RequestCount", {"stat": "Sum", "dimensions": {"LoadBalancer": "app/my-alb/abc123"}}],
                        ["MyApp/Performance", "MemoryUtilization", {"dimensions": {"AutoScalingGroup": "webapp-asg"}}]
                    ],
                    "period": 60,
                    "stat": "Average",
                    "region": "us-east-1",
                    "title": "Application Performance"
                }
            }
        ]
    }'''
)


Dashboard cost: First 3 dashboards FREE, then $3/month per dashboard

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary: Cost-Optimized Strategy

### For 100 Instances:

1. Use basic monitoring on 95% of instances (FREE)
2. Use ASG-level metrics for auto-scaling (FREE)
3. Use ALB metrics for request monitoring (FREE)
4. Add 3-5 custom metrics for app-specific data ($1.50/month)
5. Enable detailed monitoring on 5-10 critical instances ($10-20/month)
6. Use Target Tracking instead of manual alarms (FREE)

Total cost: ~$15-25/month vs $210/month (90%+ savings)

Trade-off: Slightly slower individual instance visibility, but ASG-level monitoring is usually sufficient for auto-scaling 
decisions.