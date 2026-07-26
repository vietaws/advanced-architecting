Custom metrics are counted based on the unique combination of namespace, metric name, and dimensions - not by which service 
sends them.

## How Metrics Are Counted

A unique metric is defined by:
1. Namespace (e.g., MyApp)
2. Metric Name (e.g., RequestCount)
3. Dimension combination (e.g., Service=A vs Service=B)

## Example Scenarios

### Scenario 1: Different Dimension Values (2 Metrics)

Service A sends:
json
Namespace: "MyApp"
MetricName: "RequestCount"
Dimensions: {"Service": "A"}
Value: 100


Service B sends:
json
Namespace: "MyApp"
MetricName: "RequestCount"
Dimensions: {"Service": "B"}
Value: 150


Result: 2 custom metrics (different dimension values create separate metrics)
- Cost: 2 × $0.30 = $0.60/month

### Scenario 2: Same Dimensions (1 Metric)

Service A sends:
json
Namespace: "MyApp"
MetricName: "RequestCount"
Dimensions: {"Environment": "Production"}
Value: 100


Service B sends:
json
Namespace: "MyApp"
MetricName: "RequestCount"
Dimensions: {"Environment": "Production"}
Value: 150


Result: 1 custom metric (same namespace, name, and dimensions)
- CloudWatch aggregates the values (100 + 150 = 250)
- Cost: 1 × $0.30 = $0.30/month

### Scenario 3: Multiple Dimensions (More Metrics)

Service A sends:
json
Namespace: "MyApp"
MetricName: "RequestCount"
Dimensions: {"Service": "A", "Region": "us-east-1"}
Value: 100


Service B sends:
json
Namespace: "MyApp"
MetricName: "RequestCount"
Dimensions: {"Service": "B", "Region": "us-west-2"}
Value: 150


Result: 2 custom metrics (different dimension combinations)
- Cost: 2 × $0.30 = $0.60/month

### Scenario 4: Dimension Combinations Explosion

Service A sends with 2 dimensions:
json
Dimensions: {"Service": "A", "Environment": "prod"}


CloudWatch automatically creates metrics for ALL dimension combinations:
1. {Service: A, Environment: prod} - the full combination
2. {Service: A} - Service only
3. {Environment: prod} - Environment only
4. {} - No dimensions (aggregate)

Result: 4 custom metrics from one PutMetricData call
- Cost: 4 × $0.30 = $1.20/month

If Service B sends the same:
json
Dimensions: {"Service": "B", "Environment": "prod"}


Additional metrics:
1. {Service: B, Environment: prod}
2. {Service: B}
3. {Environment: prod} - SHARED with Service A (same dimension value)
4. {} - SHARED with Service A (aggregate)

Total unique metrics: 6
- Cost: 6 × $0.30 = $1.80/month

## Real-World Example

100 services each sending:
json
Namespace: "MyApp"
MetricName: "ResponseTime"
Dimensions: {"ServiceName": "<service-name>"}


Result: 100 custom metrics (one per unique ServiceName value)
- Cost: 100 × $0.30 = $30/month

## Cost Optimization Strategy

### Bad: High Cardinality Dimensions
python
# DON'T: Using user ID as dimension
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricName='RequestCount',
    Dimensions=[{'Name': 'UserID', 'Value': user_id}]  # 1M users = 1M metrics!
)
# Cost: 1,000,000 × $0.30 = $300,000/month


### Good: Low Cardinality Dimensions
python
# DO: Use service/environment dimensions
cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricName='RequestCount',
    Dimensions=[
        {'Name': 'Service', 'Value': 'API'},
        {'Name': 'Environment', 'Value': 'prod'}
    ]
)
# Cost: Few services × few environments = manageable


## Key Takeaway

Billing is based on unique metric identity, not the source:
- Same namespace + metric name + dimensions = 1 metric (regardless of how many services send it)
- Different dimension values = different metrics
- Be careful with dimension cardinality - it multiplies your metric count quickly