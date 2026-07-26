import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';
import logger from '../logger.js';

const sqsClient = new SQSClient({ region: process.env.AWS_REGION });

export async function sendOrder(order) {
  await sqsClient.send(new SendMessageCommand({
    QueueUrl: process.env.SQS_QUEUE_URL,
    MessageBody: JSON.stringify(order)
  }));

  logger.info(
    { action: 'sqs.send', order_id: order.id, queue: process.env.SQS_QUEUE_URL },
    'Message sent to SQS'
  );
}
