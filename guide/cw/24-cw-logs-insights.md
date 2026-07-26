## What is CloudWatch Logs Insights?

CloudWatch Logs Insights is a fully managed log analytics service that lets you search and analyze log data using a SQL-like 
query language.

Key features:
- Interactive log analytics
- Purpose-built query language
- Automatic field discovery
- Visualization (time series, bar charts)
- Fast queries across millions of log events
- No infrastructure to manage

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing

Simple model: Pay only for data scanned

Cost: $0.005 per GB scanned

Important:
- You're charged for the amount of compressed log data scanned, not the query time
- Queries that scan less data cost less
- No charge for query execution time or result size
- No minimum charge

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Pricing Examples

### Example 1: Small Query

Scenario: Query 1 GB of log data

Data scanned: 1 GB
Cost: 1 GB × $0.005 = $0.005 (half a cent)


### Example 2: Daily Analysis

Scenario: Analyze 100 GB of logs per day

Data scanned per day: 100 GB
Cost per day: 100 × $0.005 = $0.50
Cost per month: $0.50 × 30 = $15/month


### Example 3: Large Investigation

Scenario: Troubleshooting issue, scan 1 TB of logs

Data scanned: 1,000 GB
Cost: 1,000 × $0.005 = $5.00 (one-time)


### Example 4: Regular Monitoring

Scenario: Run 10 queries per day, each scanning 10 GB

Data scanned per day: 10 queries × 10 GB = 100 GB
Cost per day: 100 × $0.005 = $0.50
Cost per month: $0.50 × 30 = $15/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How to Use CloudWatch Logs Insights

### Basic Query Syntax

sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20


Commands:
- fields - Select fields to display
- filter - Filter log events
- stats - Aggregate data
- sort - Sort results
- limit - Limit number of results
- parse - Extract fields from text

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 1: Find Errors

### Query
sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100


What it does: Find last 100 error messages

Cost: Depends on log volume
- If log group has 10 GB: $0.05
- If log group has 100 GB: $0.50

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 2: Count Errors by Type

### Query
sql
fields @timestamp, @message
| filter @message like /ERROR/
| parse @message /ERROR: (?<error_type>.*)/
| stats count() by error_type
| sort count() desc


What it does: Count and group errors by type

Sample output:
error_type                    count()
─────────────────────────────────────
DatabaseConnectionTimeout     1,245
InvalidAPIKey                 892
RateLimitExceeded            456


Cost: Same as Example 1 (scans same data)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 3: API Latency Analysis

### Log Format (JSON)
json
{
  "timestamp": "2026-02-09T12:00:00Z",
  "request_id": "abc-123",
  "method": "GET",
  "path": "/api/orders",
  "status": 200,
  "duration": 245
}


### Query
sql
fields @timestamp, path, duration
| filter status = 200
| stats avg(duration) as avg_latency, 
        max(duration) as max_latency, 
        pct(duration, 95) as p95_latency 
  by path
| sort avg_latency desc


Sample output:
path              avg_latency  max_latency  p95_latency
──────────────────────────────────────────────────────
/api/checkout     1,250        5,000        2,800
/api/orders       245          1,200        450
/api/products     120          800          250


Cost: If scanning 50 GB of logs: 50 × $0.005 = $0.25

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 4: Time Series Analysis

### Query
sql
fields @timestamp, status
| filter status >= 500
| stats count() as error_count by bin(5m)


What it does: Count 5XX errors in 5-minute buckets

Sample output (visualized as time series):
Time        error_count
─────────────────────────
12:00       5
12:05       12
12:10       45  ← Spike detected
12:15       8
12:20       3


Cost: If scanning 20 GB: 20 × $0.005 = $0.10

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 5: User Activity Analysis

### Log Format
json
{
  "timestamp": "2026-02-09T12:00:00Z",
  "user_id": "user-123",
  "action": "purchase",
  "amount": 99.99
}


### Query
sql
fields @timestamp, user_id, action, amount
| filter action = "purchase"
| stats sum(amount) as total_revenue, 
        count() as purchase_count 
  by user_id
| sort total_revenue desc
| limit 10


Sample output:
user_id      total_revenue  purchase_count
────────────────────────────────────────────
user-456     5,432.10       54
user-789     3,210.50       32
user-123     2,890.00       29


Cost: If scanning 30 GB: 30 × $0.005 = $0.15

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 6: Filter by Time Range (Cost Optimization)

### Query with Time Filter
sql
fields @timestamp, @message
| filter @timestamp >= 1707465600000 and @timestamp <= 1707469200000
| filter @message like /ERROR/
| stats count() by bin(1m)


What it does: Only scan logs from specific 1-hour window

Cost optimization:
- Without time filter: Scans all logs (e.g., 100 GB) = $0.50
- With 1-hour filter: Scans ~4 GB = $0.02
- **Savings: 96%**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 7: Parse Unstructured Logs

### Log Format (Plain Text)
2026-02-09 12:00:00 INFO User user-123 logged in from 192.168.1.1
2026-02-09 12:01:00 ERROR Database connection failed: timeout after 30s
2026-02-09 12:02:00 INFO User user-456 purchased item-789 for $99.99


### Query
sql
fields @timestamp, @message
| parse @message /User (?<user_id>\S+) purchased item-(?<item_id>\S+) for \$(?<amount>[\d.]+)/
| filter amount > 50
| stats sum(amount) as total_revenue, count() as purchase_count by user_id


What it does: Extract structured data from unstructured logs

Sample output:
user_id      total_revenue  purchase_count
────────────────────────────────────────────
user-456     299.97         3
user-789     150.00         2


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Example 8: Real-World Production Query

### Scenario: Investigate API 5XX errors

sql
fields @timestamp, @message, request_id, path, status, duration
| filter status >= 500
| filter @timestamp >= ago(1h)
| parse @message /ERROR: (?<error_message>.*)/
| stats count() as error_count, 
        avg(duration) as avg_duration,
        max(duration) as max_duration
  by path, status, error_message
| sort error_count desc
| limit 20


Sample output:
path              status  error_message                error_count  avg_duration  max_duration
──────────────────────────────────────────────────────────────────────────────────────────────
/api/checkout     503     Service Unavailable          145          2,500         5,000
/api/payment      500     Database timeout             89           3,200         8,000
/api/orders       502     Bad Gateway                  34           1,800         3,500


Cost: Scanning 1 hour of logs (~5 GB): 5 × $0.005 = $0.025

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Optimization Strategies

### 1. Use Time Filters

sql
-- BAD: Scans all logs (expensive)
fields @timestamp, @message
| filter @message like /ERROR/

-- GOOD: Only scans last hour (cheap)
fields @timestamp, @message
| filter @timestamp >= ago(1h)
| filter @message like /ERROR/


Savings: 95%+ if you have 30 days of logs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Query Specific Log Groups

sql
-- BAD: Query all log groups
-- Cost: Scans 500 GB across all groups = $2.50

-- GOOD: Query only relevant log group
-- Cost: Scans 10 GB from one group = $0.05


Savings: 95%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 3. Use Sampling for Exploration

sql
-- Sample 10% of logs for quick analysis
fields @timestamp, @message
| filter @timestamp >= ago(1h)
| filter ispresent(@message)
| limit 1000  -- Sample first 1000 events


Cost: Minimal (stops scanning after 1000 events found)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 4. Save Frequent Queries

CloudWatch Logs Insights lets you save queries for reuse - no additional cost.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Using CloudWatch Logs Insights

### Via AWS Console

1. Open CloudWatch Console
2. Navigate to "Logs" → "Insights"
3. Select log group(s)
4. Enter query
5. Select time range
6. Click "Run query"

### Via AWS CLI

bash
aws logs start-query \
  --log-group-name /aws/lambda/my-function \
  --start-time 1707465600 \
  --end-time 1707469200 \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 20'


### Via SDK (Python)

python
import boto3
import time

logs = boto3.client('logs')

# Start query
response = logs.start_query(
    logGroupName='/aws/lambda/my-function',
    startTime=int((datetime.now() - timedelta(hours=1)).timestamp()),
    endTime=int(datetime.now().timestamp()),
    queryString='''
        fields @timestamp, @message
        | filter @message like /ERROR/
        | stats count() by bin(5m)
    '''
)

query_id = response['queryId']

# Wait for query to complete
while True:
    result = logs.get_query_results(queryId=query_id)
    if result['status'] == 'Complete':
        break
    time.sleep(1)

# Print results
for row in result['results']:
    print(row)

# Check how much data was scanned
print(f"Data scanned: {result['statistics']['bytesScanned'] / (1024**3):.2f} GB")
print(f"Cost: ${result['statistics']['bytesScanned'] / (1024**3) * 0.005:.4f}")


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Real-World Cost Scenarios

### Scenario 1: Small Startup

Usage:
- 10 GB logs per day
- 5 queries per day, each scanning 2 GB

Cost:
Log storage: 10 GB × 30 days × $0.03 = $9/month
Log ingestion: 300 GB × $0.50 = $150/month
Logs Insights: 5 × 2 GB × 30 days × $0.005 = $1.50/month
─────────────────────────────────────────────────────
TOTAL: $160.50/month


Logs Insights: Only 1% of total cost

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Scenario 2: Medium Company

Usage:
- 500 GB logs per day
- 50 queries per day, each scanning 10 GB

Cost:
Log storage: 500 GB × 30 days × $0.03 = $450/month
Log ingestion: 15,000 GB × $0.50 = $7,500/month
Logs Insights: 50 × 10 GB × 30 days × $0.005 = $75/month
─────────────────────────────────────────────────────
TOTAL: $8,025/month


Logs Insights: Less than 1% of total cost

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Scenario 3: Large Enterprise

Usage:
- 10 TB logs per day
- 200 queries per day, each scanning 50 GB

Cost:
Log storage: 10,000 GB × 30 days × $0.03 = $9,000/month
Log ingestion: 300,000 GB × $0.50 = $150,000/month
Logs Insights: 200 × 50 GB × 30 days × $0.005 = $1,500/month
─────────────────────────────────────────────────────
TOTAL: $160,500/month


Logs Insights: Less than 1% of total cost

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Insights

1. Logs Insights is cheap compared to log storage and ingestion
2. Time filters are critical for cost optimization
3. Query specific log groups instead of all logs
4. Use sampling for exploratory analysis
5. No infrastructure cost - fully serverless

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

CloudWatch Logs Insights:
- Interactive log analytics with SQL-like queries
- **Pricing**: $0.005 per GB scanned
- **Cost optimization**: Use time filters, query specific log groups
- **Typical cost**: <1% of total CloudWatch Logs cost
- **Best for**: Troubleshooting, analysis, monitoring

Example costs:
- Query 10 GB: $0.05
- Query 100 GB: $0.50
- Query 1 TB: $5.00

Recommendation: Use Logs Insights freely for troubleshooting - the cost is minimal compared to the value of fast log analysis.