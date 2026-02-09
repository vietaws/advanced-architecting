CloudWatch Metrics pricing has different tiers based on metric type and volume. Here's a breakdown with examples:

## Pricing Components (US East - N. Virginia)

### 1. Standard Metrics
- **AWS service metrics**: FREE (EC2, RDS, Lambda, etc.)
- **Standard resolution**: 1-minute intervals

### 2. Custom Metrics
- **First 10,000 metrics**: $0.30 per metric/month
- **Next 240,000 metrics**: $0.10 per metric/month
- **Next 750,000 metrics**: $0.05 per metric/month
- **Over 1,000,000 metrics**: $0.02 per metric/month

### 3. High-Resolution Metrics
- **Custom metrics at 1-second intervals**: Same price as custom metrics
- **API calls**: $0.01 per 1,000 GetMetricData or GetMetricStatistics requests

### 4. Metric Streams
- **Metric updates**: $0.003 per 1,000 metric updates
- **Data transfer**: Standard AWS data transfer rates

### 5. API Requests
- **GetMetricData**: $0.01 per 1,000 requests
- **GetMetricStatistics**: $0.01 per 1,000 requests
- **ListMetrics**: $0.01 per 1,000 requests

## Example 1: Small Application

Scenario: Web app with 10 EC2 instances, 5 RDS databases, 20 Lambda functions

Standard AWS Metrics (FREE):
- EC2: ~70 metrics per instance × 10 = 700 metrics
- RDS: ~50 metrics per DB × 5 = 250 metrics
- Lambda: ~10 metrics per function × 20 = 200 metrics
- **Total: 1,150 standard metrics = $0/month**

Custom Metrics: 50 application-specific metrics
- 50 metrics × $0.30 = $15/month

Dashboard API calls: 10 dashboards refreshing every minute
- 10 dashboards × 20 metrics × 60 min × 24 hrs × 30 days = 8,640,000 requests
- 8,640 (thousands) × $0.01 = $86.40/month

Total: ~$101.40/month

## Example 2: Microservices Architecture

Scenario: 100 microservices, each publishing 10 custom metrics

Custom Metrics: 100 services × 10 metrics = 1,000 metrics
- 1,000 metrics × $0.30 = $300/month

High-Resolution Metrics: 20 critical services with 5 metrics each at 1-second resolution
- 20 × 5 = 100 metrics × $0.30 = $30/month

API Requests: Monitoring dashboards and alarms
- 5,000,000 GetMetricData requests/month
- 5,000 (thousands) × $0.01 = $50/month

Total: ~$380/month

## Example 3: Large-Scale Application

Scenario: 1,000 containers, each with 15 custom metrics

Custom Metrics: 1,000 × 15 = 15,000 metrics
- First 10,000: 10,000 × $0.30 = $3,000
- Next 5,000: 5,000 × $0.10 = $500
- **Total: $3,500/month**

Metric Streams (streaming to S3 for analysis):
- 15,000 metrics × 60 updates/hour × 24 hrs × 30 days = 648,000,000 updates
- 648,000 (thousands) × $0.003 = $1,944/month

Total: ~$5,444/month

## Example 4: Cost Optimization Strategy

Before Optimization: 5,000 custom metrics
- 5,000 metrics × $0.30 = $1,500/month

After Optimization:

1. Aggregate metrics: Combine similar metrics
   - Reduced to 2,000 metrics
   - 2,000 × $0.30 = $600/month

2. Use metric math: Calculate derived metrics on-demand instead of storing
   - No additional storage cost
   - Small API cost: $5/month

3. Increase resolution only where needed: Use standard 1-minute for most, 1-second for critical
   - 1,900 standard + 100 high-res = still 2,000 metrics
   - Same $600/month

4. Use CloudWatch Embedded Metric Format (EMF): Publish metrics via logs
   - Reduces API calls
   - Saves ~$50/month in API costs

Total After: ~$605/month (saves $895/month)

## Example 5: Real-World Breakdown

E-commerce platform with 200 services:

| Component | Metrics | Cost |
|-----------|---------|------|
| Standard AWS metrics (EC2, RDS, ALB) | 3,000 | $0 |
| Custom application metrics | 8,000 | $2,400 |
| High-resolution (checkout, payment) | 200 | $60 |
| API requests (dashboards, alarms) | 10M/month | $100 |
| Metric Streams to S3 | 8,000 metrics | $1,036 |
| Total | | $3,596/month |

## Cost Reduction Tips

1. Use Metric Filters on Logs
bash
# Extract metrics from existing logs instead of publishing separately
# Saves custom metric costs if you're already paying for logs


2. Aggregate at Source
bash
# Instead of: 100 containers × 10 metrics = 1,000 metrics ($300)
# Aggregate to: 10 service-level metrics = 10 metrics ($3)
# Savings: $297/month


3. Use Percentiles Wisely
bash
# Publishing p50, p90, p99 separately = 3 metrics
# Use metric statistics instead = 1 metric
# Savings: $0.60/month per metric set


4. Leverage EMF (Embedded Metric Format)
json
{
  "_aws": {
    "Timestamp": 1234567890,
    "CloudWatchMetrics": [{
      "Namespace": "MyApp",
      "Dimensions": [["Service"]],
      "Metrics": [{"Name": "RequestCount"}]
    }]
  },
  "Service": "API",
  "RequestCount": 1
}

- Publish via logs, extracted as metrics automatically
- Can reduce API call costs

5. Set Metric Retention
bash
# Metrics are retained for 15 months by default
# You pay for storage throughout
# Consider exporting old metrics to S3 for long-term storage


## Key Takeaway

- **Standard AWS metrics**: Free and comprehensive
- **Custom metrics**: Main cost driver (starts at $0.30/metric/month)
- **API requests**: Can add up with frequent dashboard refreshes
- **Optimization focus**: Reduce number of custom metrics through aggregation