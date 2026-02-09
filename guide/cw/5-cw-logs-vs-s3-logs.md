## CloudWatch Logs vs S3 for Application Logs

### CloudWatch Logs

Use Cases:
- Real-time monitoring and alerting
- Active troubleshooting and debugging
- Live log tailing during incidents
- Operational dashboards
- Short-term retention (days to weeks)

Pros:
- Real-time streaming and querying
- Built-in Logs Insights for ad-hoc queries
- Native integration with CloudWatch Alarms and Metrics
- Automatic log aggregation from multiple sources
- Live tail capability
- Metric filters for custom metrics

Cons:
- Expensive for long-term storage
- High ingestion costs ($0.50/GB)
- Query costs add up with heavy usage
- Limited retention options (max 10 years)
- Not ideal for bulk analytics

Cost (100 GB/month):
- Ingestion: $50/month
- Storage (30 days): ~$4.50/month
- Queries: Variable, ~$5-20/month
- **Total: ~$60-75/month**

Implementation:
python
# Easy - AWS SDKs handle it
import boto3
logs = boto3.client('logs')
logs.put_log_events(
    logGroupName='/app/production',
    logStreamName='instance-1',
    logEvents=[{'timestamp': 1234567890, 'message': 'Error occurred'}]
)


### S3

Use Cases:
- Long-term archival (months to years)
- Compliance and audit requirements
- Bulk analytics with Athena/EMR
- Cost-effective storage
- Infrequent access patterns

Pros:
- Very cheap storage ($0.023/GB standard, $0.004/GB Glacier)
- No ingestion fees
- Unlimited retention
- Great for big data analytics (Athena, Spark)
- Lifecycle policies for automatic tiering
- Immutable with Object Lock

Cons:
- No real-time querying
- No live tailing
- Requires separate tools for analysis (Athena, etc.)
- Query costs with Athena ($5/TB scanned)
- More complex to implement streaming
- Delayed access (especially with Glacier)

Cost (100 GB/month):
- Ingestion: $0 (you write directly)
- Storage (S3 Standard): 100 GB × $0.023 = $2.30/month
- Storage (S3 Glacier): 100 GB × $0.004 = $0.40/month
- **Total: $0.40-2.30/month**

Implementation:
python
# More work - need to handle batching, compression, partitioning
import boto3
import gzip
from datetime import datetime

s3 = boto3.client('s3')
logs = [...]  # Your log entries

# Compress and partition by date
date_path = datetime.now().strftime('%Y/%m/%d')
compressed = gzip.compress('\n'.join(logs).encode())

s3.put_object(
    Bucket='my-logs-bucket',
    Key=f'logs/{date_path}/app-{timestamp}.log.gz',