## How to Determine Metric Resolution

You can check a metric's resolution using the AWS CLI or SDK by examining the metric's metadata.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Method 1: Using AWS CLI (Quickest)

bash
# List metrics and check their properties
aws cloudwatch list-metrics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=abc \
  --region us-east-1


Output:
json
{
    "Metrics": [
        {
            "Namespace": "AWS/EC2",
            "MetricName": "CPUUtilization",
            "Dimensions": [
                {
                    "Name": "AutoScalingGroupName",
                    "Value": "abc"
                }
            ]
        }
    ]
}


Note: list-metrics doesn't show resolution directly. You need to check the metric statistics.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Method 2: Check Metric Statistics (Most Reliable)

bash
# Get metric statistics to see available periods
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=abc \
  --start-time 2026-02-09T10:00:00Z \
  --end-time 2026-02-09T11:00:00Z \
  --period 60 \
  --statistics Average \
  --region us-east-1


If it returns data: The metric supports 60-second resolution
If it returns empty or error: The metric might only support 300-second (5-minute) resolution

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Method 3: Try Different Periods (Definitive Test)

bash
# Test 1: Try 60-second period
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=abc \
  --start-time 2026-02-09T10:00:00Z \
  --end-time 2026-02-09T11:00:00Z \
  --period 60 \
  --statistics Average

# Test 2: Try 10-second period (high-resolution)
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=abc \
  --start-time 2026-02-09T10:00:00Z \
  --end-time 2026-02-09T10:10:00Z \
  --period 10 \
  --statistics Average


Results interpretation:
- **Returns data with period=60**: Standard resolution (or better)
- **Returns data with period=10**: High resolution
- **Returns empty with period=60**: Basic monitoring (5-minute only)
- **Error with period=10**: Not high resolution

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Method 4: Using Python Boto3

python
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')

# Check what data is available
def check_metric_resolution(namespace, metric_name, dimensions):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    # Test 1: Try 60-second period
    try:
        response_60 = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=start_time,
            EndTime=end_time,
            Period=60,
            Statistics=['Average']
        )
        has_60_sec = len(response_60['Datapoints']) > 0
    except Exception as e:
        has_60_sec = False
        print(f"60-second test failed: {e}")
    
    # Test 2: Try 10-second period (high-resolution)
    try:
        response_10 = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=end_time - timedelta(minutes=10),  # Only last 10 min for high-res
            EndTime=end_time,
            Period=10,
            Statistics=['Average']
        )
        has_10_sec = len(response_10['Datapoints']) > 0
    except Exception as e:
        has_10_sec = False
        print(f"10-second test failed: {e}")
    
    # Test 3: Try 300-second period (basic monitoring)
    try:
        response_300 = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        has_300_sec = len(response_300['Datapoints']) > 0
    except Exception as e:
        has_300_sec = False
        print(f"300-second test failed: {e}")
    
    # Determine resolution
    if has_10_sec:
        return "High Resolution (1-second storage, can query at 10-second intervals)"
    elif has_60_sec:
        return "Standard Resolution (60-second storage) or Detailed Monitoring"
    elif has_300_sec:
        return "Basic Monitoring (300-second/5-minute storage)"
    else:
        return "No data available or metric doesn't exist"

# Usage
dimensions = [
    {'Name': 'AutoScalingGroupName', 'Value': 'abc'}
]

resolution = check_metric_resolution(
    namespace='AWS/EC2',
    metric_name='CPUUtilization',
    dimensions=dimensions
)

print(f"Metric resolution: {resolution}")


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Method 5: Check EC2 Monitoring Type (For AWS/EC2 Metrics)

For AWS/EC2 namespace specifically, the resolution depends on the instance monitoring configuration:

bash
# Check if instances have detailed monitoring enabled
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=abc" \
  --query 'Reservations[*].Instances[*].[InstanceId,Monitoring.State]' \
  --output table


Output:
---------------------------------
|      DescribeInstances        |
+-------------------+-----------+
|  i-1234567890    |  enabled  |  ← Detailed monitoring (60-second)
|  i-0987654321    |  disabled |  ← Basic monitoring (300-second)
+-------------------+-----------+


Interpretation:
- Monitoring.State = enabled → Detailed monitoring → 60-second resolution
- Monitoring.State = disabled → Basic monitoring → 300-second resolution

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Quick Reference: AWS/EC2 CPUUtilization

### For Your Specific Example:

Namespace: AWS/EC2
MetricName: CPUUtilization
Dimension: AutoScalingGroupName=abc

Resolution depends on:
1. Individual instance monitoring settings
2. ASG-level aggregation

### ASG-Level Metric Behavior:

python
# ASG-level CPU metric
Dimensions=[{'Name': 'AutoScalingGroupName', 'Value': 'abc'}]


Important: ASG-level metrics are aggregated from individual instances:

- If all instances have basic monitoring (5-min) → ASG metric updates every 5 minutes
- If all instances have detailed monitoring (1-min) → ASG metric updates every 1 minute
- If mixed (some detailed, some basic) → ASG metric updates every 1 minute (interpolated)

Typical behavior: ASG-level CPU metrics usually have 60-second effective resolution even with basic monitoring on instances, 
because CloudWatch interpolates the data.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Practical Test for Your Metric

bash
# Test your specific metric
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=abc \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --region us-east-1 \
  --output json | jq '.Datapoints | length'


If output > 0: You have at least 60-second resolution
If output = 0: Try with --period 300 (5 minutes)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Visual Guide: Determining Resolution

┌─────────────────────────────────────────────────────────┐
│ Start: Check metric with different periods              │
└─────────────────────────────────────────────────────────┘
                        ↓
        ┌───────────────────────────────┐
        │ Try period=10 (10 seconds)    │
        └───────────────────────────────┘
                        ↓
                ┌───────┴────────┐
                │                │
            Returns data    No data/Error
                │                │
                ↓                ↓
        ┌──────────────┐  ┌──────────────────┐
        │ HIGH         │  │ Try period=60    │
        │ RESOLUTION   │  │ (1 minute)       │
        │ (1-second)   │  └──────────────────┘
        └──────────────┘         ↓
                          ┌──────┴───────┐
                          │              │
                      Returns data   No data/Error
                          │              │
                          ↓              ↓
                  ┌──────────────┐  ┌──────────────────┐
                  │ STANDARD     │  │ Try period=300   │
                  │ RESOLUTION   │  │ (5 minutes)      │
                  │ (60-second)  │  └──────────────────┘
                  └──────────────┘         ↓
                                    ┌──────┴───────┐
                                    │              │
                                Returns data   No data
                                    │              │
                                    ↓              ↓
                            ┌──────────────┐  ┌──────────────┐
                            │ BASIC        │  │ NO DATA      │
                            │ MONITORING   │  │ or metric    │
                            │ (300-second) │  │ doesn't exist│
                            └──────────────┘  └──────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary: Your Specific Metric

Namespace: AWS/EC2
MetricName: CPUUtilization
Dimension: AutoScalingGroupName=abc

Most likely resolution: 
- **60-second (standard)** if any instance in ASG has detailed monitoring
- **300-second (basic)** if all instances have basic monitoring

To confirm:
bash
# Quick test
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=abc \
  --start-time 2026-02-09T10:00:00Z \
  --end-time 2026-02-09T11:00:00Z \
  --period 60 \
  --statistics Average


- **Has datapoints**: 60-second or better resolution
- **Empty datapoints**: Try --period 300 for basic monitoring

Rule of thumb for AWS/EC2 metrics:
- Custom metrics: Check StorageResolution when published
- AWS service metrics: Check service monitoring configuration (detailed vs basic)
- ASG-level metrics: Usually 60-second effective resolution