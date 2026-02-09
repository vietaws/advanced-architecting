There are 4 main approaches to send custom metrics to CloudWatch. Here's each method with pros/cons:

## 1. AWS SDK / CLI (PutMetricData API)

### Example (AWS CLI)
bash
aws cloudwatch put-metric-data \
  --namespace "MyApp" \
  --metric-name "PageLoadTime" \
  --value 245 \
  --unit Milliseconds \
  --dimensions Service=WebApp,Environment=Production


### Example (Python SDK)
python
import boto3

cloudwatch = boto3.client('cloudwatch')

cloudwatch.put_metric_data(
    Namespace='MyApp',
    MetricData=[
        {
            'MetricName': 'PageLoadTime',
            'Value': 245,
            'Unit': 'Milliseconds',
            'Dimensions': [
                {'Name': 'Service', 'Value': 'WebApp'},
                {'Name': 'Environment', 'Value': 'Production'}
            ]
        }
    ]
)


### Pros
- Direct and straightforward
- Full control over metric properties
- Can batch up to 1,000 metrics per API call
- Supports high-resolution metrics (1-second intervals)
- Works from anywhere (EC2, Lambda, on-premises)

### Cons
- Requires AWS credentials/IAM permissions
- API throttling limits (150 TPS per region by default)
- Network latency for each API call
- Need to handle retries and error handling
- Can impact application performance if not async

## 2. CloudWatch Agent

### Example Configuration
json
{
  "metrics": {
    "namespace": "MyApp",
    "metrics_collected": {
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MemoryUsed", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DiskUsed", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}


### Custom Metrics via StatsD
python
# Application code
from statsd import StatsD

statsd = StatsD(host='localhost', port=8125)
statsd.gauge('custom.page_load_time', 245)


### Pros
- Automatic batching and retry logic
- Collects system metrics (CPU, memory, disk) automatically
- Supports StatsD and collectd protocols
- Buffers metrics locally (resilient to network issues)
- Lower overhead than direct API calls
- Built-in aggregation

### Cons
- Requires agent installation and management
- Additional infrastructure to maintain
- Configuration complexity
- Resource overhead (CPU, memory for agent)
- Only works on EC2/on-premises (not Lambda)

## 3. Embedded Metric Format (EMF)

### Example (Lambda)
python
import json

def lambda_handler(event, context):
    # Your business logic
    response_time = 245
    
    # EMF format - printed to stdout
    print(json.dumps({
        "_aws": {
            "Timestamp": 1234567890000,
            "CloudWatchMetrics": [{
                "Namespace": "MyApp",
                "Dimensions": [["Service"]],
                "Metrics": [
                    {"Name": "ResponseTime", "Unit": "Milliseconds"}
                ]
            }]
        },
        "Service": "API",
        "ResponseTime": response_time
    }))


### Example (Using aws-embedded-metrics library)
python
from aws_embedded_metrics import metric_scope

@metric_scope
def lambda_handler(event, context, metrics):
    metrics.set_namespace("MyApp")
    metrics.set_dimensions({"Service": "API"})
    metrics.put_metric("ResponseTime", 245, "Milliseconds")
    
    return {"statusCode": 200}


### Pros
- No direct API calls (metrics extracted from logs)
- Perfect for Lambda (no cold start impact)
- Automatic batching via logs
- No IAM permissions needed beyond log writing
- Can query both logs and metrics
- Asynchronous (no performance impact)
- Works with CloudWatch Logs Insights

### Cons
- Pays for both logs ingestion ($0.50/GB) AND metric storage ($0.30/metric)
- More expensive for high-volume metrics
- Limited to CloudWatch Logs destinations
- JSON format overhead in logs
- Less intuitive than direct API calls

## 4. Metric Filters on Existing Logs

### Example Log Entry
2026-02-09 16:00:00 INFO Request completed in 245ms


### Create Metric Filter
bash
aws logs put-metric-filter \
  --log-group-name /aws/lambda/my-function \
  --filter-name ResponseTimeMetric \
  --filter-pattern '[time, level, msg, duration_value, duration_unit="ms"]' \
  --metric-transformations \
    metricName=ResponseTime,\
    metricNamespace=MyApp,\
    metricValue='$duration_value',\
    unit=Milliseconds


### Pros
- No code changes needed
- Leverages existing logs
- No additional API calls
- Free metric extraction (only pay for metric storage)
- Retroactive (can apply to existing logs)
- Centralized metric definition

### Cons
- Requires structured log format
- Limited to simple extractions (no complex calculations)
- Depends on log ingestion (if logs fail, metrics fail)
- Pattern matching can be tricky
- Less flexible than programmatic approaches
- Already paying for log ingestion

## 5. CloudWatch Metric Streams (for forwarding, not publishing)

### Example
bash
aws cloudwatch put-metric-stream \
  --name my-metric-stream \