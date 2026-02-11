## Cost Calculation

### Custom Metrics Cost

Pricing: $0.30 per metric per month

Your metrics: 2 custom metrics

2 metrics × $0.30 = $0.60/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### PutMetricData API Cost

Important: PutMetricData API calls are FREE - they're included in the custom metric pricing.

Your API calls: 1,000 calls per minute

API calls per month: 1,000 × 60 min × 24 hrs × 30 days = 43,200,000 calls
API cost: $0 (FREE - included in metric cost)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Total Cost

Component                          Cost
─────────────────────────────────────────
Custom metrics (2 metrics)         $0.60
PutMetricData API calls            $0.00 (FREE)
─────────────────────────────────────────
TOTAL                              $0.60/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Important Notes

### 1. PutMetricData is FREE
Unlike GetMetricData/GetMetricStatistics (used for queries), PutMetricData is free - you only pay for the number of unique 
metrics, not the API calls.

### 2. What You Pay For
You're charged based on unique metric identity:
- Namespace + MetricName + Dimension combination = 1 metric

### 3. Example Breakdown

If your 1,000 API calls per minute are:

Scenario A: All calls for same 2 metrics
javascript
// Call 1-500: Metric 1
putMetricData({ MetricName: 'OrderSuccess', Dimensions: {Type: 'standard'} })

// Call 501-1000: Metric 2  
putMetricData({ MetricName: 'OrderFailure', Dimensions: {Type: 'standard'} })

Cost: 2 metrics × $0.30 = $0.60/month

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Scenario B: Different dimension values create more metrics
javascript
// 1000 calls with different dimension values
putMetricData({ MetricName: 'OrderSuccess', Dimensions: {OrderID: 'order-1'} })
putMetricData({ MetricName: 'OrderSuccess', Dimensions: {OrderID: 'order-2'} })
// ... 998 more unique OrderIDs

Cost: 1,000 unique metrics × $0.30 = $300/month ⚠️

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. API Rate Limits

PutMetricData limits:
- **150 TPS** (transactions per second) per account per region (default)
- Can request increase via AWS Support

Your usage: 1,000 calls/minute = ~16.7 calls/second ✓ Within limit

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

For 2 custom metrics with 1,000 API calls per minute:

| Component | Cost |
|-----------|------|
| 2 custom metrics | $0.60/month |
| 43M API calls | $0.00 (FREE) |
| Total | $0.60/month |

Key takeaway: You only pay for the number of unique metrics ($0.30 each), not the number of API calls to publish them.