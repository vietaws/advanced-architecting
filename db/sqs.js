const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const config = require('../app_config.json');

const sqsClient = new SQSClient({ region: config.sqs.region });

async function sendOrder(order) {
  await sqsClient.send(new SendMessageCommand({
    QueueUrl: config.sqs.queueUrl,
    MessageBody: JSON.stringify(order)
  }));
}

module.exports = { sendOrder };
