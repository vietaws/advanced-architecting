## CloudWatch Dashboard Cost Breakdown

### Dashboard Components

Your dashboard includes:
1. ALB Request metric (AWS/ApplicationELB)
2. CPU Utilization metric (AWS/EC2)
3. Custom metric - Orders (your custom namespace)
4. Refresh rate: 10 seconds

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Calculation

### 1. Dashboard Cost

Pricing:
- First 3 dashboards: FREE
- Additional dashboards: $3.00/month each

Your cost: 
- If this is your 1st, 2nd, or 3rd dashboard: $0
- If this is your 4th+ dashboard: $3.00/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Metrics Cost

#### ALB Request Metric (FREE)
Namespace: AWS/ApplicationELB
MetricName: RequestCount (or similar)
Cost: $0 (AWS service metrics are free)


#### CPU Utilization (FREE)
Namespace: AWS/EC2
MetricName: CPUUtilization
Cost: $0 (AWS service metrics are free)


#### Custom Orders Metric
Namespace: YourApp (custom)
MetricName: Orders
Cost: $0.30/month per metric


Metrics subtotal: $0.30/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. API Request Cost (Dashboard Refresh)

This is the expensive part with 10-second refresh!

When dashboard refreshes, it calls GetMetricData or GetMetricStatistics API for each metric.

API Pricing: $0.01 per 1,000 requests

Your dashboard:
- 3 metrics
- Refresh every 10 seconds
- Requests per hour: 3 metrics × (3600 seconds / 10 seconds) = 1,080 requests/hour
- Requests per day: 1,080 × 24 = 25,920 requests/day
- Requests per month: 25,920 × 30 = 777,600 requests/month

API cost: 777,600 / 1,000 × $0.01 = $7.78/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Total Cost

### Scenario 1: First 3 Dashboards (Most Common)

Component                          Cost
─────────────────────────────────────────
Dashboard (1st-3rd)                $0.00
ALB Request metric                 $0.00
CPU Utilization metric             $0.00
Custom Orders metric               $0.30
API requests (10-sec refresh)      $7.78
─────────────────────────────────────────
TOTAL                              $8.08/month


### Scenario 2: 4th+ Dashboard

Component                          Cost
─────────────────────────────────────────
Dashboard (4th+)                   $3.00
ALB Request metric                 $0.00
CPU Utilization metric             $0.00
Custom Orders metric               $0.30
API requests (10-sec refresh)      $7.78
─────────────────────────────────────────
TOTAL                              $11.08/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization: Change Refresh Rate

The 10-second refresh is driving most of the cost. Here's how different refresh rates affect cost:

### 10-Second Refresh (Current)
Requests/month: 777,600
API cost: $7.78/month
Total: $8.08/month (or $11.08 if 4th+ dashboard)


### 1-Minute Refresh (RECOMMENDED)
Requests/month: 3 × 60 × 24 × 30 = 129,600
API cost: 129,600 / 1,000 × $0.01 = $1.30/month
Total: $1.60/month (or $4.60 if 4th+ dashboard)

Savings: $6.48/month (80% reduction)


### 5-Minute Refresh
Requests/month: 3 × 12 × 24 × 30 = 25,920
API cost: 25,920 / 1,000 × $0.01 = $0.26/month
Total: $0.56/month (or $3.56 if 4th+ dashboard)

Savings: $7.52/month (93% reduction)


### Auto Refresh (Default - 1 minute when viewing)
Only refreshes when dashboard is open
Typical usage: 2 hours/day viewing
Requests/month: 3 × 60 × 2 × 30 = 10,800
API cost: 10,800 / 1,000 × $0.01 = $0.11/month
Total: $0.41/month (or $3.41 if 4th+ dashboard)

Savings: $7.67/month (95% reduction)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison Table

| Refresh Rate | API Requests/Month | API Cost | Total Cost (1st-3rd) | Total Cost (4th+) |
|--------------|-------------------|----------|---------------------|------------------|
| 10 seconds | 777,600 | $7.78 | $8.08 | $11.08 |
| 30 seconds | 259,200 | $2.59 | $2.89 | $5.89 |
| 1 minute | 129,600 | $1.30 | $1.60 | $4.60 |
| 5 minutes | 25,920 | $0.26 | $0.56 | $3.56 |
| Auto (viewing only) | ~10,800 | $0.11 | $0.41 | $3.41 |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Example: Production Dashboard

### Typical Production Setup

python
# Dashboard with multiple widgets
dashboard_config = {
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    # ALB metrics (FREE)
                    ["AWS/ApplicationELB", "RequestCount"],
                    ["AWS/ApplicationELB", "TargetResponseTime"],
                    ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"],
                    
                    # EC2 metrics (FREE)
                    ["AWS/EC2", "CPUUtilization", {"dimensions": {"AutoScalingGroupName": "webapp-asg"}}],
                    
                    # Custom metrics ($0.30 each)
                    ["MyApp", "Orders"],
                    ["MyApp", "Revenue"],
                    ["MyApp", "ActiveUsers"]
                ],
                "period": 60,  # 1-minute aggregation
                "stat": "Average",
                "region": "us-east-1"
            }
        }
    ]
}


Metrics: 7 total (4 AWS + 3 custom)
Refresh: 1 minute (recommended)

Cost calculation:
Dashboard: $0 (assuming 1st-3rd)
AWS metrics (4): $0
Custom metrics (3): 3 × $0.30 = $0.90
API requests: 7 metrics × 60 × 24 × 30 = 302,400 requests
API cost: 302,400 / 1,000 × $0.01 = $3.02

Total: $3.92/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Additional Considerations

### 1. Multiple Users Viewing Dashboard

If 5 people have the dashboard open simultaneously:

10-second refresh:
API requests: 777,600 × 5 = 3,888,000 requests/month
API cost: 3,888,000 / 1,000 × $0.01 = $38.88/month
Total: ~$39/month


1-minute refresh:
API requests: 129,600 × 5 = 648,000 requests/month
API cost: 648,000 / 1,000 × $0.01 = $6.48/month
Total: ~$7/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Dashboard with Many Metrics

If you add more metrics (e.g., 20 metrics total):

10-second refresh:
API requests: 20 × 360 × 24 × 30 = 5,184,000 requests/month
API cost: 5,184,000 / 1,000 × $0.01 = $51.84/month


1-minute refresh:
API requests: 20 × 60 × 24 × 30 = 864,000 requests/month
API cost: 864,000 / 1,000 × $0.01 = $8.64/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Using GetMetricData vs GetMetricStatistics

CloudWatch dashboards use GetMetricData API, which is more efficient:

GetMetricData (used by dashboards):
- Can retrieve multiple metrics in one call
- More efficient batching
- Same pricing: $0.01 per 1,000 requests

GetMetricStatistics (older API):
- One metric per call
- Less efficient
- Same pricing: $0.01 per 1,000 requests

Modern dashboards automatically use GetMetricData, so you're already optimized.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Recommendations

### For Your Specific Dashboard (3 metrics, 10-second refresh)

Current cost: $8.08/month

Recommended changes:

1. Change refresh to 1 minute
   - New cost: $1.60/month
   - Savings: $6.48/month (80%)
   - Impact: Minimal - 1 minute is still very responsive

2. Use auto-refresh (only when viewing)
   - New cost: $0.41/month
   - Savings: $7.67/month (95%)
   - Impact: Dashboard only refreshes when you're looking at it

3. If you need real-time monitoring
   - Keep 10-second refresh for critical metrics only
   - Use 1-minute or 5-minute for less critical metrics
   - Split into multiple dashboards

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How to Configure Refresh Rate

### In AWS Console
1. Open CloudWatch Dashboard
2. Click "Actions" → "Edit"
3. Top right: "Auto refresh" dropdown
4. Select: "Off", "10 Seconds", "1 Minute", "2 Minutes", "5 Minutes", "15 Minutes"
5. Click "Save dashboard"


### Via API/SDK
python
# Dashboard refresh is client-side, not stored in dashboard definition
# Users can change it in the console when viewing
# No API configuration needed


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

Your current setup:
- 1 dashboard with 3 metrics
- 10-second refresh
- **Cost: $8.08/month** (if 1st-3rd dashboard) or $11.08/month (if 4th+)

Recommended optimization:
- Change to 1-minute refresh
- **New cost: $1.60/month** (if 1st-3rd) or $4.60/month (if 4th+)
- **Savings: $6.48/month (80%)**

Best practice: Use 1-minute refresh for most dashboards. Reserve 10-second refresh for critical real-time monitoring dashboards 
only.