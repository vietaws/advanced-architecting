## Implementation Guide: CloudWatch Unified Agent + Custom Metrics

You'll need two components:
1. CloudWatch Unified Agent - for CPU, memory (system metrics)
2. AWS SDK in your app - for custom metrics (orders, latency)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 1: Install CloudWatch Unified Agent

### On Amazon Linux 2 / Amazon Linux 2023

bash
# Download and install
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

sudo yum install amazon-cloudwatch-agent

### On Ubuntu / Debian

bash
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 2: Create IAM Role for EC2

Your EC2 instance needs permissions to send metrics to CloudWatch.

### IAM Policy (JSON)

json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "ec2:DescribeVolumes",
        "ec2:DescribeTags",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:CreateLogStream",
        "logs:CreateLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/AmazonCloudWatch-*"
    }
  ]
}


### Attach to EC2 Instance

bash
# Create role and attach policy (via AWS Console or CLI)
aws iam create-role --role-name CloudWatchAgentRole --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name CloudWatchAgentRole --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws ec2 associate-iam-instance-profile --instance-id i-1234567890abcdef0 --iam-instance-profile Name=CloudWatchAgentRole


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 3: Configure CloudWatch Agent

Create configuration file: /opt/aws/amazon-cloudwatch-agent/etc/config.json

```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "MyApp/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "rename": "CPU_IOWAIT",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "diskio": {
        "measurement": [
          {
            "name": "io_time",
            "rename": "DISK_IO_TIME",
            "unit": "Milliseconds"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MEMORY_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "rename": "TCP_CONNECTIONS",
            "unit": "Count"
          }
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          {
            "name": "swap_used_percent",
            "rename": "SWAP_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/*.log",
            "log_group_name": "/aws/ec2/app",
            "log_stream_name": "{instance_id}/{local_hostname}",
            "timezone": "UTC",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "multi_line_start_pattern": "{timestamp_format}"
          }
        ]
      }
    }
  }
}
```

## Setup log folder
mkdir /var/log/app/

vi /var/log/app/application.log


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 4: Start CloudWatch Agent

bash
# Start the agent with the config
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Check status
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

# Enable auto-start on boot
sudo systemctl enable amazon-cloudwatch-agent


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 5: Implement Custom Metrics in JavaScript App

### Install AWS SDK

bash
npm install @aws-sdk/client-cloudwatch


### Create Metrics Module

File: metrics.js

javascript

```js
const { CloudWatchClient, PutMetricDataCommand } = require('@aws-sdk/client-cloudwatch');

const cloudwatch = new CloudWatchClient({ region: 'us-east-1' });

// Namespace for custom application metrics
const NAMESPACE = 'MyApp/Orders';

/**
 * Send custom metric to CloudWatch
 */
async function putMetric(metricName, value, unit = 'Count', dimensions = {}) {
  const params = {
    Namespace: NAMESPACE,
    MetricData: [
      {
        MetricName: metricName,
        Value: value,
        Unit: unit,
        Timestamp: new Date(),
        StorageResolution: 1, // High resolution (1-second)
        Dimensions: Object.entries(dimensions).map(([Name, Value]) => ({ Name, Value }))
      }
    ]
  };

  try {
    await cloudwatch.send(new PutMetricDataCommand(params));
  } catch (error) {
    console.error('Failed to send metric:', error);
  }
}

/**
 * Send multiple metrics in one API call (more efficient)
 */
async function putMetrics(metrics) {
  const metricData = metrics.map(m => ({
    MetricName: m.name,
    Value: m.value,
    Unit: m.unit || 'Count',
    Timestamp: new Date(),
    StorageResolution: 1,
    Dimensions: Object.entries(m.dimensions || {}).map(([Name, Value]) => ({ Name, Value }))
  }));

  const params = {
    Namespace: NAMESPACE,
    MetricData: metricData
  };

  try {
    await cloudwatch.send(new PutMetricDataCommand(params));
  } catch (error) {
    console.error('Failed to send metrics:', error);
  }
}

async function generateOrders(count = 10) {
  const orderTypes = ['standard', 'express', 'premium'];
  // const orders = [];

  for (let i = 1; i <= count; i++) {
    const order = {
      id: `order-${i}`,
      type: orderTypes[Math.floor(Math.random() * orderTypes.length)],
      amount: parseFloat((Math.random() * 500 + 10).toFixed(2)), // $10 - $510
      duration: Math.floor(Math.random() * (2000 - 50 + 1)) + 50 // 50ms - 2000ms
    };
    await putMetrics([
      {
        name: 'OrderSuccess',
        value: 1,
        unit: 'Count',
        dimensions: { OrderType: order.type }
      },
      {
        name: 'OrderValue',
        value: order.amount,
        unit: 'None',
        dimensions: { OrderType: order.type }
      },
      {
        name: 'OrderProcessingTime',
        value: duration,
        unit: 'Milliseconds',
        dimensions: { OrderType: order.type }
      }
    ]);
    console.log(`Processed order #${i}: `, order)
  }

  return orders;
}

await generateOrders()

// module.exports = { putMetric, putMetrics };
```


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 6: Integrate Metrics into Your Application

File: app.js

```javascript
const express = require('express');
const { putMetric, putMetrics } = require('./metrics');

const app = express();
app.use(express.json());

// Middleware to track request latency
app.use((req, res, next) => {
  const startTime = Date.now();
  
  // Capture response
  res.on('finish', async () => {
    const duration = Date.now() - startTime;
    
    // Send latency metric
    await putMetric('ResponseLatency', duration, 'Milliseconds', {
      Method: req.method,
      Path: req.path,
      StatusCode: res.statusCode.toString()
    });
  });
  
  next();
});

// Order endpoint
app.post('/api/orders', async (req, res) => {
  const startTime = Date.now();
  
  try {
    // Process order
    const order = await processOrder(req.body);
    const duration = Date.now() - startTime;
    
    // Send success metrics
    await putMetrics([
      {
        name: 'OrderSuccess',
        value: 1,
        unit: 'Count',
        dimensions: { OrderType: order.type }
      },
      {
        name: 'OrderValue',
        value: order.amount,
        unit: 'None',
        dimensions: { OrderType: order.type }
      },
      {
        name: 'OrderProcessingTime',
        value: duration,
        unit: 'Milliseconds',
        dimensions: { OrderType: order.type }
      }
    ]);
    
    res.json({ success: true, order });
    
  } catch (error) {
    const duration = Date.now() - startTime;
    
    // Send failure metrics
    await putMetrics([
      {
        name: 'OrderFailure',
        value: 1,
        unit: 'Count',
        dimensions: { 
          ErrorType: error.code || 'Unknown',
          OrderType: req.body.type || 'Unknown'
        }
      },
      {
        name: 'OrderProcessingTime',
        value: duration,
        unit: 'Milliseconds',
        dimensions: { OrderType: req.body.type || 'Unknown' }
      }
    ]);
    
    res.status(500).json({ success: false, error: error.message });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

async function processOrder(orderData) {
  // Your order processing logic
  return {
    id: 'order-123',
    type: orderData.type,
    amount: orderData.amount
  };
}

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 7: Optimized Version with Batching

For high-traffic applications, batch metrics to reduce API calls:

File: metrics-batched.js

```javascript
const { CloudWatchClient, PutMetricDataCommand } = require('@aws-sdk/client-cloudwatch');

const cloudwatch = new CloudWatchClient({ region: 'us-east-1' });
const NAMESPACE = 'MyApp/Orders';

class MetricsBatcher {
  constructor(flushInterval = 60000) { // Flush every 60 seconds
    this.buffer = [];
    this.flushInterval = flushInterval;
    this.startFlushing();
  }

  add(metricName, value, unit = 'Count', dimensions = {}) {
    this.buffer.push({
      MetricName: metricName,
      Value: value,
      Unit: unit,
      Timestamp: new Date(),
      StorageResolution: 1,
      Dimensions: Object.entries(dimensions).map(([Name, Value]) => ({ Name, Value }))
    });

    // Flush if buffer is full (max 1000 metrics per API call)
    if (this.buffer.length >= 1000) {
      this.flush();
    }
  }

  async flush() {
    if (this.buffer.length === 0) return;

    const metricsToSend = this.buffer.splice(0, 1000); // Take up to 1000

    try {
      await cloudwatch.send(new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: metricsToSend
      }));
      console.log(`Flushed ${metricsToSend.length} metrics`);
    } catch (error) {
      console.error('Failed to flush metrics:', error);
      // Re-add failed metrics to buffer
      this.buffer.unshift(...metricsToSend);
    }
  }

  startFlushing() {
    setInterval(() => this.flush(), this.flushInterval);
  }
}

const metricsBatcher = new MetricsBatcher();

module.exports = { metricsBatcher };


Usage in app:

javascript
const { metricsBatcher } = require('./metrics-batched');

app.post('/api/orders', async (req, res) => {
  try {
    const order = await processOrder(req.body);
    
    // Add metrics to batch (non-blocking)
    metricsBatcher.add('OrderSuccess', 1, 'Count', { OrderType: order.type });
    metricsBatcher.add('OrderValue', order.amount, 'None', { OrderType: order.type });
    
    res.json({ success: true, order });
  } catch (error) {
    metricsBatcher.add('OrderFailure', 1, 'Count', { ErrorType: error.code });
    res.status(500).json({ success: false, error: error.message });
  }
});
```


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 8: Create CloudWatch Alarms

```bash
# Alarm for high memory usage
aws cloudwatch put-metric-alarm \
  --alarm-name high-memory-usage \
  --alarm-description "Alert when memory > 85%" \
  --metric-name MEMORY_USED \
  --namespace MyApp/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2

# Alarm for order failures
aws cloudwatch put-metric-alarm \
  --alarm-name high-order-failures \
  --alarm-description "Alert when order failures > 10/min" \
  --metric-name OrderFailure \
  --namespace MyApp/Orders \
  --statistic Sum \
  --period 60 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2

# Alarm for high latency
aws cloudwatch put-metric-alarm \
  --alarm-name high-response-latency \
  --alarm-description "Alert when latency > 1000ms" \
  --metric-name ResponseLatency \
  --namespace MyApp/Orders \
  --statistic Average \
  --period 60 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step 9: Create Dashboard

bash
aws cloudwatch put-dashboard --dashboard-name MyApp-Production --dashboard-body '{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["MyApp/EC2", "CPU_IDLE"],
          [".", "MEMORY_USED"],
          [".", "DISK_USED"]
        ],
        "period": 60,
        "stat": "Average",
        "region": "us-east-1",
        "title": "System Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["MyApp/Orders", "OrderSuccess", {"stat": "Sum"}],
          [".", "OrderFailure", {"stat": "Sum"}]
        ],
        "period": 60,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Order Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["MyApp/Orders", "ResponseLatency", {"stat": "Average"}],
          ["...", {"stat": "p95"}]
        ],
        "period": 60,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Latency"
      }
    }
  ]
}'


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Estimate

### For 1 EC2 Instance

Component                              Cost/Month
─────────────────────────────────────────────────
CloudWatch Agent metrics (6 metrics)   $1.80
Custom metrics (4 metrics)             $1.20
Alarms (3 alarms)                      $0.30
Dashboard (1st-3rd)                    $0.00
API calls (batched, ~10k/month)        $0.10
─────────────────────────────────────────────────
TOTAL                                  $3.40/month


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary

What you get:
1. ✅ CPU, Memory, Disk metrics (via CloudWatch Agent)
2. ✅ Custom order metrics (success, failure)
3. ✅ Response latency tracking
4. ✅ High-resolution metrics (1-second)
5. ✅ Alarms for critical thresholds
6. ✅ Dashboard for visualization

Key files:
- /opt/aws/amazon-cloudwatch-agent/etc/config.json - Agent config
- metrics.js - Metrics helper module
- app.js - Application with metrics integration

Commands:
bash
# Start agent
sudo systemctl start amazon-cloudwatch-agent

# Check status
sudo systemctl status amazon-cloudwatch-agent

# View logs
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log