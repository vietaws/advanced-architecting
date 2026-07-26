import { CloudWatchClient, PutMetricDataCommand } from '@aws-sdk/client-cloudwatch';

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
  const orderTypes = ['standard', 'premium'];
  const orders = [];

  for (let i = 1; i <= count; i++) {
    const order = {
      id: `order-${i}`,
      type: orderTypes[Math.floor(Math.random() * orderTypes.length)],
      amount: parseFloat((Math.random() * 500 + 10).toFixed(2)), // $10 - $510
      duration: Math.floor(Math.random() * (2000 - 50 + 1)) + 50 // 50ms - 2000ms
    };
    
    orders.push(order);
    
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
        value: order.duration,
        unit: 'Milliseconds',
        dimensions: { OrderType: order.type }
      }
    ]);
    console.log(`Processed order #${i}: `, order);
  }

  return orders;
}

// Run the function
generateOrders(100).then(() => {
  console.log('All orders processed');
}).catch(error => {
  console.error('Error processing orders:', error);
});