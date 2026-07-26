## What is CloudWatch Dashboard?

A CloudWatch Dashboard is a customizable visual interface that displays metrics, logs, and alarms in real-time. It provides a 
unified view of your AWS resources and applications.

Key Features:
- Display multiple metrics in graphs, numbers, and text widgets
- Monitor resources across multiple AWS accounts and regions
- Auto-refresh at configurable intervals
- Share dashboards with team members
- Embed in web applications

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing

### Dashboard Costs

First 3 dashboards: FREE
Additional dashboards: $3.00 per dashboard per month

What counts as "one dashboard":
- A dashboard is counted if it exists for more than 1 hour in a month
- Dashboards with 0 widgets still count
- Deleted dashboards (within 1 hour) don't count

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing Examples

### Example 1: Small Team (3 Dashboards)

Dashboards:
- Production Overview (1 dashboard)
- Application Performance (1 dashboard)  
- Database Monitoring (1 dashboard)

Cost: $0/month (first 3 are free)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 2: Medium Team (10 Dashboards)

Dashboards:
- Production Overview (1)
- Staging Overview (1)
- Development Overview (1)
- API Performance (1)
- Database Monitoring (1)
- Lambda Functions (1)
- S3 & Storage (1)
- Network & VPC (1)
- Security & Compliance (1)
- Cost Monitoring (1)

Cost calculation:
- First 3 dashboards: $0
- Additional 7 dashboards: 7 × $3 = $21/month

Total: $21/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 3: Large Organization (50 Dashboards)

Dashboards:
- 10 production service dashboards
- 10 staging environment dashboards
- 10 regional dashboards (multi-region)
- 10 team-specific dashboards
- 10 infrastructure dashboards

Cost calculation:
- First 3 dashboards: $0
- Additional 47 dashboards: 47 × $3 = $141/month

Total: $141/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 4: Dashboard Lifecycle (Partial Month)

Scenario: Create and delete dashboards during the month

Day 1: Create Dashboard A (exists for 30 days)
Day 5: Create Dashboard B (exists for 25 days)
Day 10: Create Dashboard C (exists for 20 days)
Day 15: Create Dashboard D, delete after 30 minutes (< 1 hour)
Day 20: Create Dashboard E (exists for 10 days)

Billable dashboards: 4 (A, B, C, E)
Dashboard D doesn't count (deleted within 1 hour)

Cost:
- First 3: $0 (A, B, C)
- Additional 1: 1 × $3 = $3/month (E)

Total: $3/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Creating a Dashboard

### Example 1: Basic Dashboard (Python)

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
                    ["AWS/EC2", "CPUUtilization", {"stat": "Average"}]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "EC2 CPU Utilization",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        }
    ]
}

cloudwatch.put_dashboard(
    DashboardName='production-overview',
    DashboardBody=json.dumps(dashboard_body)
)


Cost: Free (first dashboard)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 2: Multi-Widget Dashboard

python
dashboard_body = {
    "widgets": [
        # Widget 1: EC2 CPU
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", {
                        "stat": "Average",
                        "dimensions": {
                            "AutoScalingGroupName": "webapp-asg"
                        }
                    }]
                ],
                "period": 60,
                "stat": "Average",
                "region": "us-east-1",
                "title": "ASG CPU Utilization"
            }
        },
        # Widget 2: ALB Request Count
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "RequestCount", {
                        "stat": "Sum",
                        "dimensions": {
                            "LoadBalancer": "app/my-alb/abc123"
                        }
                    }]
                ],
                "period": 60,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "ALB Request Count"
            }
        },
        # Widget 3: ALB Response Time
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/ApplicationELB", "TargetResponseTime", {
                        "stat": "Average",
                        "dimensions": {
                            "LoadBalancer": "app/my-alb/abc123"
                        }
                    }]
                ],
                "period": 60,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Response Time",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        # Widget 4: Number widget (current value)
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 6,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", {
                        "stat": "Average",
                        "dimensions": {
                            "AutoScalingGroupName": "webapp-asg"
                        }
                    }]
                ],
                "period": 60,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Current CPU",
                "view": "singleValue"
            }
        },
        # Widget 5: Alarm status
        {
            "type": "alarm",
            "x": 18,
            "y": 6,
            "width": 6,
            "height": 6,
            "properties": {
                "title": "Alarm Status",
                "alarms": [
                    "arn:aws:cloudwatch:us-east-1:123456789012:alarm:HighCPU",
                    "arn:aws:cloudwatch:us-east-1:123456789012:alarm:HighLatency"
                ]
            }
        },
        # Widget 6: Text widget
        {
            "type": "text",
            "x": 0,
            "y": 12,
            "width": 24,
            "height": 2,
            "properties": {
                "markdown": "# Production Environment\n\nLast updated: 2026-02-09\n\n**On-call**: ops-team@example.com"
            }
        }
    ]
}

cloudwatch.put_dashboard(
    DashboardName='production-detailed',
    DashboardBody=json.dumps(dashboard_body)
)


Cost: Free (if this is your 2nd or 3rd dashboard)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Example 3: Cross-Region Dashboard

python
dashboard_body = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", {
                        "region": "us-east-1",
                        "label": "US East"
                    }],
                    ["AWS/EC2", "CPUUtilization", {
                        "region": "eu-west-1",
                        "label": "EU West"
                    }],
                    ["AWS/EC2", "CPUUtilization", {
                        "region": "ap-southeast-1",
                        "label": "Asia Pacific"
                    }]
                ],
                "period": 300,
                "stat": "Average",
                "title": "Global CPU Utilization"
            }
        }
    ]
}

cloudwatch.put_dashboard(
    DashboardName='global-overview',
    DashboardBody=json.dumps(dashboard_body)
)


Cost: Free (if within first 3 dashboards)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Widget Types

### 1. Line Graph (Time Series)
python
{
    "type": "metric",
    "properties": {
        "metrics": [["AWS/EC2", "CPUUtilization"]],
        "view": "timeSeries"  # Default
    }
}


### 2. Stacked Area
python
{
    "type": "metric",
    "properties": {
        "metrics": [
            ["AWS/EC2", "CPUUtilization", {"label": "CPU"}],
            ["AWS/EC2", "NetworkIn", {"label": "Network"}]
        ],
        "view": "timeSeries",
        "stacked": True
    }
}


### 3. Number (Single Value)
python
{
    "type": "metric",
    "properties": {
        "metrics": [["AWS/EC2", "CPUUtilization"]],
        "view": "singleValue"
    }
}


### 4. Gauge
python
{
    "type": "metric",
    "properties": {
        "metrics": [["AWS/EC2", "CPUUtilization"]],
        "view": "gauge",
        "yAxis": {
            "left": {"min": 0, "max": 100}
        }
    }
}


### 5. Bar Chart
python
{
    "type": "metric",
    "properties": {
        "metrics": [["AWS/Lambda", "Invocations"]],
        "view": "bar"
    }
}


### 6. Pie Chart
python
{
    "type": "metric",
    "properties": {
        "metrics": [
            ["AWS/Lambda", "Invocations", {"label": "Function A"}],
            ["AWS/Lambda", "Invocations", {"label": "Function B"}]
        ],
        "view": "pie"
    }
}


### 7. Logs Widget
python
{
    "type": "log",
    "properties": {
        "query": "SOURCE '/aws/lambda/my-function' | fields @timestamp, @message | sort @timestamp desc | limit 20",
        "region": "us-east-1",
        "title": "Recent Logs"
    }
}


### 8. Alarm Widget
python
{
    "type": "alarm",
    "properties": {
        "title": "Critical Alarms",
        "alarms": [
            "arn:aws:cloudwatch:us-east-1:123456789012:alarm:HighCPU"
        ]
    }
}


### 9. Text/Markdown Widget
python
{
    "type": "text",
    "properties": {
        "markdown": "# Dashboard Title\n\nDescription here"
    }
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization Strategies

### Strategy 1: Consolidate Dashboards

Before (10 dashboards):
- Production-EC2
- Production-RDS
- Production-Lambda
- Production-S3
- Staging-EC2
- Staging-RDS
- Staging-Lambda
- Staging-S3
- Dev-EC2
- Dev-RDS

Cost: 7 × $3 = $21/month (first 3 free)


After (3 dashboards):
- Production (all services in one dashboard)
- Staging (all services in one dashboard)
- Development (all services in one dashboard)

Cost: $0/month (all free)


Savings: $21/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Strategy 2: Use Dashboard Variables

Instead of creating separate dashboards per environment, use one dashboard with filters:

python
dashboard_body = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/EC2", "CPUUtilization", {
                        "dimensions": {
                            "AutoScalingGroupName": "${Environment}-asg"
                        }
                    }]
                ],
                "title": "CPU - ${Environment}"
            }
        }
    ]
}


Result: 1 dashboard instead of 3 (prod, staging, dev)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Strategy 3: Delete Unused Dashboards

bash
# List all dashboards
aws cloudwatch list-dashboards