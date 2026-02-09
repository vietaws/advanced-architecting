Vended Logs are logs that AWS services automatically publish to CloudWatch Logs on your behalf. The key benefit: ingestion is 
free - you only pay for storage.

## Common Vended Log Types

1. VPC Flow Logs - Network traffic metadata for your VPCs
2. Route 53 Query Logs - DNS queries to your hosted zones
3. Lambda Extension Logs - Logs from Lambda extensions
4. AWS Network Firewall Logs - Firewall traffic logs

## Cost Difference

Regular Logs (your application logs):
- Ingestion: $0.50/GB
- Storage: $0.03/GB/month

Vended Logs:
- Ingestion: FREE
- Storage: $0.03/GB/month

## Example: VPC Flow Logs

If you enable VPC Flow Logs generating 100 GB/month:

As vended logs:
- Ingestion: $0 (free)
- Storage: 100 GB × $0.03 = $3/month
- **Total: $3/month**

If these were regular logs:
- Ingestion: 100 GB × $0.50 = $50/month
- Storage: 100 GB × $0.03 = $3/month
- **Total: $53/month**

## How to Enable VPC Flow Logs (Example)

bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-12345678 \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/flowlogsRole


The logs appear in CloudWatch Logs automatically, and you're only charged for storage, not ingestion.

## Why AWS Does This

AWS wants to encourage you to enable these logs for security and troubleshooting without the high ingestion costs being a 
barrier. It makes monitoring your infrastructure more affordable.



Here are the AWS services that support vended logs to CloudWatch Logs (free ingestion):

## Network & Security

1. VPC Flow Logs - Network traffic for VPCs, subnets, and ENIs
2. AWS Network Firewall - Firewall alert and flow logs
3. Route 53 Resolver Query Logs - DNS queries handled by Route 53 Resolver
4. AWS WAF - Web application firewall logs
5. AWS Shield Advanced - DDoS protection logs

## Compute & Containers

6. Lambda Extension Logs - Logs from Lambda extensions (not function logs)
7. ECS FireLens - Container log routing (when configured to CloudWatch)

## Database & Analytics

8. RDS/Aurora - Database audit logs, error logs, slow query logs, general logs
9. Amazon Redshift - Audit logs, connection logs, user logs
10. Amazon OpenSearch Service - Error logs, search slow logs, index slow logs

## Application Integration

11. API Gateway - Execution logs and access logs
12. AppSync - GraphQL API logs

## Management & Governance

13. AWS CloudTrail - API activity logs (when delivered to CloudWatch)
14. AWS Config - Configuration change logs
15. AWS Systems Manager - Session Manager logs, Run Command logs

## Storage

16. Amazon S3 - Server access logs (when delivered to CloudWatch via subscription)
17. AWS Storage Gateway - Gateway audit logs

## Machine Learning

18. Amazon SageMaker - Training job logs, endpoint logs, processing job logs

## Other Services

19. AWS Glue - ETL job logs
20. AWS Step Functions - Execution logs
21. Amazon MQ - Broker logs
22. AWS App Runner - Application and service logs
23. Amazon MSK (Managed Kafka) - Broker logs

## Important Notes

- **Not all logs from these services are vended** - some may still incur ingestion charges depending on how they're configured
- **Lambda function logs** (standard CloudWatch Logs from your code) are NOT vended logs - they incur normal ingestion charges
- **CloudTrail to CloudWatch** technically incurs ingestion charges in some configurations

The most commonly used vended logs are VPC Flow Logs, RDS logs, and API Gateway logs due to their high volume and the 
significant cost savings.

To verify current vended log status for a specific service, check the CloudWatch Logs pricing page or the service's 
documentation, as AWS occasionally updates which logs qualify as vended.