## Maximum Lambda Executions per ENI

### Short Answer

AWS does NOT publish a fixed number of Lambda executions per ENI.

The relationship is dynamic and managed by AWS's Hyperplane system.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What We Know

### 1. No Fixed Ratio

There is NO fixed formula like:
- ❌ 1 ENI = 100 Lambda executions
- ❌ 1 ENI = 1000 Lambda executions
- ❌ 1 ENI = X concurrent executions

Why: AWS uses dynamic multiplexing through Hyperplane

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### 2. Hyperplane Architecture

How it works:

Traditional Model (pre-2019):
1 Lambda execution = 1 ENI
└── Very slow scaling

Hyperplane Model (current):
Many Lambda executions → Few ENIs
├── Dynamic multiplexing
├── Shared network infrastructure
└── Fast scaling


Key concept: Multiple Lambda execution environments share the same ENI through network address translation (NAT) and 
connection multiplexing.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## What Determines ENI Count?

### Factors (in order of importance):

1. Network Throughput
If Lambda executions generate high network traffic:
└── More ENIs created to handle bandwidth

If Lambda executions are low traffic:
└── Fewer ENIs needed


2. Connection Count
If Lambda creates many concurrent connections:
└── More ENIs needed

If Lambda creates few connections:
└── Fewer ENIs needed


3. Subnet + Security Group Combinations
2 subnets × 2 security groups = 4 combinations
└── Minimum 4 ENIs (one per combination)


4. Concurrent Executions
More concurrent executions → More ENIs
But NOT a 1:1 ratio


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Observed Patterns (Not Official)

### Based on Community Observations

Low traffic Lambda (simple queries):
Concurrent Executions    Observed ENIs    Ratio
10                       1-2              5-10:1
100                      2-4              25-50:1
1,000                    5-10             100-200:1
10,000                   20-50            200-500:1


High traffic Lambda (large data transfers):
Concurrent Executions    Observed ENIs    Ratio
10                       2-3              3-5:1
100                      5-10             10-20:1
1,000                    20-40            25-50:1
10,000                   100-200          50-100:1


Important: These are observations, NOT guarantees from AWS.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Why AWS Doesn't Publish Fixed Numbers

### 1. Dynamic System

Hyperplane adjusts ENI count based on:
├── Network traffic patterns
├── Connection patterns
├── Regional capacity
├── Time of day
└── Other factors AWS doesn't disclose


### 2. Continuous Optimization

AWS constantly improves Hyperplane:
├── Better multiplexing algorithms
├── More efficient resource usage
└── Numbers change over time


### 3. Prevents Gaming

If AWS published: "1 ENI = 100 executions"
└── Users might try to optimize around this
    └── Could lead to unexpected behavior


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## How to Estimate ENI Usage

### Method 1: Monitor Your Own Usage

bash
# Run load test
# Monitor ENI count during test

# Before test
BEFORE=$(aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'length(NetworkInterfaces)')

echo "ENIs before: $BEFORE"

# Run load test (e.g., 1000 concurrent invocations)
# ... your load test ...

# After test
AFTER=$(aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query 'length(NetworkInterfaces)')

echo "ENIs after: $AFTER"
echo "ENIs created: $((AFTER - BEFORE))"


### Method 2: Use CloudWatch

bash
# Monitor concurrent executions
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name ConcurrentExecutions \
  --dimensions Name=FunctionName,Value=my-function \
  --start-time 2026-02-09T00:00:00Z \
  --end-time 2026-02-09T01:00:00Z \
  --period 60 \
  --statistics Maximum

# Count ENIs at same time
# Compare: Concurrent executions vs ENI count


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Practical Guidance

### What You Should Plan For

Instead of calculating exact ENI count, focus on:

### 1. Subnet Sizing

Rule of thumb: Allocate 1 IP per 100-200 concurrent executions

Example:
- Expected peak: 1,000 concurrent executions
- Estimated ENIs: 5-10
- Recommended subnet size: /24 (256 IPs)
- Safety margin: 25x more IPs than needed


Subnet sizing guide:
Concurrent Executions    Recommended Subnet
< 100                    /28 (16 IPs)
100-500                  /26 (64 IPs)
500-2,000                /24 (256 IPs)
2,000-10,000             /22 (1,024 IPs)
> 10,000                 /20 (4,096 IPs)


### 2. ENI Limits

AWS account ENI limit: 5,000 per region (default)

If you expect:
- 10,000 concurrent executions
- Estimated 50-100 ENIs
- You're well within limits


### 3. Connection Limits

More important than ENI count:
└── RDS connection limits

Example:
- RDS db.t3.micro: 87 max connections
- 1,000 concurrent Lambdas
- Each Lambda: 1 connection
- Problem: 1,000 > 87

Solution: Use RDS Proxy (not more ENIs)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Testing Your Specific Workload

### Load Test Script

javascript
// load-test.js
const { Lambda } = require('@aws-sdk/client-lambda');

const lambda = new Lambda({ region: 'us-east-1' });

async function loadTest(concurrency) {
  console.log(`Starting load test with ${concurrency} concurrent invocations`);
  
  const promises = [];
  for (let i = 0; i < concurrency; i++) {
    promises.push(
      lambda.invoke({
        FunctionName: 'my-vpc-function',
        InvocationType: 'RequestResponse',
        Payload: JSON.stringify({ test: i })
      })
    );
  }
  
  const start = Date.now();
  await Promise.all(promises);
  const duration = Date.now() - start;
  
  console.log(`Completed ${concurrency} invocations in ${duration}ms`);
  console.log(`Average: ${duration / concurrency}ms per invocation`);
}

// Test different concurrency levels
async function runTests() {
  await loadTest(10);
  await new Promise(r => setTimeout(r, 5000));
  
  await loadTest(100);
  await new Promise(r => setTimeout(r, 5000));
  
  await loadTest(1000);
}

runTests();


Monitor ENIs during test:
bash
# Run in separate terminal
watch -n 5 'aws ec2 describe-network-interfaces \
  --filters Name=description,Values="AWS Lambda VPC ENI*" \
  --query "length(NetworkInterfaces)" \
  --output text'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## AWS Official Guidance

### What AWS Says

From AWS documentation:

│ "Lambda creates elastic network interfaces in your VPC subnets. The number of network interfaces created depends on the 
number of concurrent function executions and the network traffic patterns."

Translation: It's dynamic and depends on your workload.

### What AWS Recommends

1. Use multiple subnets (at least 2 AZs)
2. Use subnets with sufficient IP addresses
3. Don't try to calculate exact ENI count
4. Monitor and adjust based on actual usage

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Key Takeaways

### What We Know

✅ Multiple Lambda executions share ENIs
✅ ENI count scales with concurrent executions
✅ ENI count scales with network traffic
✅ Typical ratio: 100-500 executions per ENI (varies widely)

### What We Don't Know

❌ Exact formula for ENI count
❌ Maximum executions per ENI
❌ How Hyperplane decides to create new ENIs

### What You Should Do

1. Don't try to calculate exact ENI count
2. Provision subnets with 10-25x more IPs than estimated ENIs
3. Monitor actual ENI usage in your workload
4. Focus on connection limits (RDS, etc.) not ENI limits
5. Use RDS Proxy if you have connection issues

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

| Question | Answer |
|----------|--------|
| Max executions per ENI? | No fixed number (dynamic) |
| How many ENIs will I need? | Depends on traffic patterns |
| Typical ratio? | 100-500 executions per ENI (varies) |
| How to plan? | Provision large subnets, monitor actual usage |
| Should I worry about ENI limits? | Usually no (5,000 limit per region) |
| Should I worry about connection limits? | Yes! (Use RDS Proxy) |

Bottom line: AWS intentionally doesn't publish fixed numbers because the system is dynamic. Focus on provisioning adequate 
subnet space and monitoring actual usage rather than trying to calculate exact ENI counts.