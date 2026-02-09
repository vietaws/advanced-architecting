 CloudWatch Logs pricing has several components. Here are practical examples to illustrate the costs:

## Pricing Components (US East - N. Virginia)

1. Data Ingestion: $0.50 per GB
2. Storage: $0.03 per GB/month
3. Data Scanned (Logs Insights queries): $0.005 per GB scanned
4. Vended Logs: Free ingestion, standard storage applies

## Example 1: Small Application

Scenario: Web application generating 10 GB of logs per day

- **Ingestion**: 10 GB/day × 30 days = 300 GB/month
  - Cost: 300 GB × $0.50 = $150/month

- **Storage** (keeping 30 days):
  - Average storage: ~450 GB (accumulates over month)
  - Cost: 450 GB × $0.03 = $13.50/month

- **Queries**: Run 20 queries/day, each scanning 5 GB
  - 20 × 5 GB × 30 days = 3,000 GB scanned
  - Cost: 3,000 GB × $0.005 = $15/month

Total: ~$178.50/month

## Example 2: Cost Optimization with Retention

Same app, but with tiered retention:

- Keep 7 days in CloudWatch Logs: 70 GB average
  - Storage: 70 GB × $0.03 = $2.10/month

- Archive older logs to S3: 300 GB/month
  - S3 Standard: 300 GB × $0.023 = $6.90/month
  - (Or S3 Glacier: 300 GB × $0.004 = $1.20/month)

- Ingestion: Still $150/month

Total with S3 Standard: ~$159/month (saves $19.50)
Total with S3 Glacier: ~$153.30/month (saves $25.20)

## Example 3: High-Volume Microservices

Scenario: 50 microservices, each generating 5 GB/day

- **Ingestion**: 50 × 5 GB × 30 days = 7,500 GB/month
  - Cost: 7,500 GB × $0.50 = $3,750/month

- **Storage** (7-day retention): ~1,750 GB average
  - Cost: 1,750 GB × $0.03 = $52.50/month

Total: ~$3,802.50/month

## Example 4: VPC Flow Logs (Vended Logs)

Scenario: VPC with 100 ENIs generating flow logs

- **Ingestion**: FREE (vended logs)
- **Data volume**: ~50 GB/day = 1,500 GB/month
- **Storage**: 1,500 GB × $0.03 = $45/month

Total: $45/month (much cheaper due to free ingestion)

## Cost Reduction Strategies

1. Use Log Filters
bash
# Only send ERROR logs instead of all logs
# Reduces ingestion from 10 GB/day to 1 GB/day
# Savings: 9 GB × 30 × $0.50 = $135/month


2. Subscription Filters to S3
bash
# Stream logs directly to S3, bypass CloudWatch storage
# Ingestion: $150/month (still applies)
# Storage: S3 instead of CloudWatch = $6.90 vs $13.50
# Savings: $6.60/month


3. Sampling
bash
# Log only 10% of requests for high-traffic apps
# 100 GB/day → 10 GB/day
# Savings: 90 GB × 30 × $0.50 = $1,350/month


4. Use CloudWatch Logs Insights Efficiently
bash
# Query specific time ranges and log groups
# Scanning 1 GB vs 10 GB per query
# Savings per query: 9 GB × $0.005 = $0.045


## Real-World Cost Breakdown

For a typical production application:
- **Ingestion**: 70-80% of total cost
- **Storage**: 10-15% of total cost  
- **Queries**: 5-10% of total cost

The key to controlling costs is managing ingestion volume through filtering, sampling, and log level optimization.

For detailed pricing calculations for your specific use case, use the [AWS Pricing Calculator](https://calculator.aws).