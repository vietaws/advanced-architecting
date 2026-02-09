## GetMetricData API Behavior

CloudWatch dashboards use GetMetricData API, which can retrieve multiple metrics in a single API call (up to 500 metrics per 
request).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Your Dashboard: 3 Metrics

Metrics:
1. ALB RequestCount
2. EC2 CPUUtilization  
3. Custom Orders metric

Key insight: All 3 metrics are retrieved in 1 API call per refresh, not 3 separate calls.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## API Call Count Calculation

### Formula
API calls per refresh = 1 (GetMetricData batches all metrics)
API calls per hour = (3600 seconds / refresh_interval)
API calls per month = API calls per hour × 24 hours × 30 days


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 1: 10-Second Refresh

API calls per refresh: 1
API calls per hour: 3600 / 10 = 360 calls
API calls per day: 360 × 24 = 8,640 calls
API calls per month: 8,640 × 30 = 259,200 calls

Cost: 259,200 / 1,000 × $0.01 = $2.59/month


Total dashboard cost:
Dashboard (1st-3rd): $0
Custom metric: $0.30
API calls: $2.59
─────────────────────
TOTAL: $2.89/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: 1-Minute Refresh (RECOMMENDED)

API calls per refresh: 1
API calls per hour: 3600 / 60 = 60 calls
API calls per day: 60 × 24 = 1,440 calls
API calls per month: 1,440 × 30 = 43,200 calls

Cost: 43,200 / 1,000 × $0.01 = $0.43/month


Total dashboard cost:
Dashboard (1st-3rd): $0
Custom metric: $0.30
API calls: $0.43
─────────────────────
TOTAL: $0.73/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 3: 5-Minute Refresh

API calls per refresh: 1
API calls per hour: 3600 / 300 = 12 calls
API calls per day: 12 × 24 = 288 calls
API calls per month: 288 × 30 = 8,640 calls

Cost: 8,640 / 1,000 × $0.01 = $0.09/month


Total dashboard cost:
Dashboard (1st-3rd): $0
Custom metric: $0.30
API calls: $0.09
─────────────────────
TOTAL: $0.39/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 4: Auto Refresh (Only When Viewing)

Assumption: Dashboard viewed 2 hours per day

API calls per hour: 60 (1-minute auto-refresh when viewing)
API calls per day: 60 × 2 hours = 120 calls
API calls per month: 120 × 30 = 3,600 calls

Cost: 3,600 / 1,000 × $0.01 = $0.04/month


Total dashboard cost:
Dashboard (1st-3rd): $0
Custom metric: $0.30
API calls: $0.04
─────────────────────
TOTAL: $0.34/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Comparison Table

| Refresh Rate | API Calls/Month | API Cost | Custom Metric | Total Cost |
|--------------|----------------|----------|---------------|------------|
| 10 seconds | 259,200 | $2.59 | $0.30 | $2.89 |
| 30 seconds | 86,400 | $0.86 | $0.30 | $1.16 |
| 1 minute | 43,200 | $0.43 | $0.30 | $0.73 |
| 5 minutes | 8,640 | $0.09 | $0.30 | $0.39 |
| Auto (2h/day) | 3,600 | $0.04 | $0.30 | $0.34 |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What If Dashboard Has More Metrics?

### Scenario: 10 Metrics in Dashboard

Metrics:
- 5 ALB metrics (RequestCount, TargetResponseTime, 5XX, 4XX, HealthyHostCount)
- 2 EC2 metrics (CPUUtilization, NetworkIn)
- 3 Custom metrics (Orders, Revenue, ActiveUsers)

API calls: Still 1 call per refresh (GetMetricData batches all 10 metrics)

1-minute refresh:
API calls per month: 43,200 (same as 3 metrics!)
API cost: $0.43/month
Custom metrics: 3 × $0.30 = $0.90
─────────────────────
TOTAL: $1.33/month


Key point: Adding more metrics to the same dashboard doesn't increase API calls (up to 500 metrics per call).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What If Dashboard Has Multiple Widgets?

### Scenario: Dashboard with 3 Separate Widgets

python
dashboard = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "RequestCount"]  # Widget 1
                ]
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization"]  # Widget 2
                ]
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["MyApp", "Orders"]  # Widget 3
                ]
            }
        }
    ]
}


API calls per refresh: 1 call (CloudWatch batches all widgets)

1-minute refresh:
API calls per month: 43,200
API cost: $0.43/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What If Metrics Have Different Time Ranges?

### Scenario: Different Time Windows

python
dashboard = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "RequestCount"]
                ],
                "period": 60,
                "start": "-PT1H"  # Last 1 hour
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization"]
                ],
                "period": 300,
                "start": "-PT3H"  # Last 3 hours
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["MyApp", "Orders"]
                ],
                "period": 60,
                "start": "-PT24H"  # Last 24 hours
            }
        }
    ]
}


API calls per refresh: 3 calls (different time ranges require separate API calls)

1-minute refresh:
API calls per month: 43,200 × 3 = 129,600
API cost: 129,600 / 1,000 × $0.01 = $1.30/month
Custom metric: $0.30
─────────────────────
TOTAL: $1.60/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What If Metrics Have Different Periods?

### Scenario: Different Aggregation Periods

python
dashboard = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "RequestCount", {"period": 60}],  # 1-min
                    ["AWS/EC2", "CPUUtilization", {"period": 300}],  # 5-min
                    ["MyApp", "Orders", {"period": 60}]  # 1-min
                ],
                "start": "-PT1H"  # Same time range
            }
        }
    ]
}


API calls per refresh: 1 call (GetMetricData handles different periods in one call)

1-minute refresh:
API calls per month: 43,200
API cost: $0.43/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Example: Production Dashboard

### Dashboard Configuration

python
import boto3
import json

cloudwatch = boto3.client('cloudwatch')

dashboard_body = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    # All metrics with same time range
                    ["AWS/ApplicationELB", "RequestCount", {"stat": "Sum"}],
                    ["AWS/ApplicationELB", "TargetResponseTime", {"stat": "Average"}],
                    ["AWS/EC2", "CPUUtilization", {"stat": "Average", "dimensions": {"AutoScalingGroupName": "webapp-asg"}}],
                    ["MyApp", "Orders", {"stat": "Sum"}],
                    ["MyApp", "Revenue", {"stat": "Sum"}],
                    ["MyApp", "ActiveUsers", {"stat": "Average"}]
                ],
                "period": 60,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Application Overview",
                "start": "-PT1H",  # Last 1 hour
                "end": "P0D"  # Now
            }
        }
    ]
}

cloudwatch.put_dashboard(
    DashboardName='production-overview',
    DashboardBody=json.dumps(dashboard_body)
)


Metrics: 6 total (3 AWS + 3 custom)
Widgets: 1 widget with all metrics
Time range: Same for all (last 1 hour)
Period: Same for all (60 seconds)

API calls per refresh: 1 call

Cost with 1-minute refresh:
API calls per month: 43,200
API cost: $0.43/month
Custom metrics: 3 × $0.30 = $0.90/month
Dashboard: $0 (1st-3rd)
─────────────────────
TOTAL: $1.33/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## GetMetricData API Call Example

Here's what actually happens when dashboard refreshes:

python
# Single API call retrieves all 3 metrics
response = cloudwatch.get_metric_data(
    MetricDataQueries=[
        {
            'Id': 'm1',
            'MetricStat': {
                'Metric': {
                    'Namespace': 'AWS/ApplicationELB',
                    'MetricName': 'RequestCount',
                    'Dimensions': [
                        {'Name': 'LoadBalancer', 'Value': 'app/my-alb/abc123'}
                    ]
                },
                'Period': 60,
                'Stat': 'Sum'
            }
        },
        {
            'Id': 'm2',
            'MetricStat': {
                'Metric': {
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'CPUUtilization',
                    'Dimensions': [
                        {'Name': 'AutoScalingGroupName', 'Value': 'webapp-asg'}
                    ]
                },
                'Period': 60,
                'Stat': 'Average'
            }
        },
        {
            'Id': 'm3',
            'MetricStat': {
                'Metric': {
                    'Namespace': 'MyApp',
                    'MetricName': 'Orders'
                },
                'Period': 60,
                'Stat': 'Sum'
            }
        }
    ],
    StartTime=datetime.utcnow() - timedelta(hours=1),
    EndTime=datetime.utcnow()
)

# This counts as 1 API call, not 3!


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization Tips

### 1. Group Metrics in Same Widget
python
# GOOD: 1 API call
{
    "widgets": [
        {
            "metrics": [
                ["AWS/ApplicationELB", "RequestCount"],
                ["AWS/EC2", "CPUUtilization"],
                ["MyApp", "Orders"]
            ]
        }
    ]
}

# AVOID: 3 API calls (if different time ranges)
{
    "widgets": [
        {"metrics": [["AWS/ApplicationELB", "RequestCount"]], "start": "-PT1H"},
        {"metrics": [["AWS/EC2", "CPUUtilization"]], "start": "-PT3H"},
        {"metrics": [["MyApp", "Orders"]], "start": "-PT24H"}
    ]
}


### 2. Use Consistent Time Ranges
All metrics with same time range = 1 API call

### 3. Adjust Refresh Rate Based on Need
- Critical dashboards: 1 minute
- Monitoring dashboards: 5 minutes
- Historical dashboards: Auto refresh (only when viewing)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Your dashboard (3 metrics, same time range):

| Refresh Rate | API Calls/Month | API Cost | Custom Metric | Total |
|--------------|----------------|----------|---------------|-------|
| 10 seconds | 259,200 | $2.59 | $0.30 | $2.89 |
| 1 minute | 43,200 | $0.43 | $0.30 | $0.73 |
| 5 minutes | 8,640 | $0.09 | $0.30 | $0.39 |

Key points:
1. GetMetricData batches multiple metrics into 1 API call
2. API calls = refreshes per month (not metrics × refreshes)
3. Different time ranges = separate API calls
4. Same time range + different periods = still 1 API call
5. Up to 500 metrics can be retrieved in 1 API call

Recommendation: Use 1-minute refresh for $0.73/month total cost.