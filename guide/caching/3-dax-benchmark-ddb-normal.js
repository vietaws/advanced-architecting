import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, GetCommand } from '@aws-sdk/lib-dynamodb';

// Create DynamoDB client
const client = new DynamoDBClient({ region: 'us-east-1' });
const docClient = DynamoDBDocumentClient.from(client);

const tableName = 'products';

// Put item
async function putItem() {
  const params = {
    TableName: tableName,
    Item: {
      id: '123',
      name: 'Product Name',
      price: 29.99,
      category: 'Electronics'
    }
  };

  try {
    await docClient.send(new PutCommand(params));
    console.log('Item added successfully');
  } catch (error) {
    console.error('Error putting item:', error);
  }
}

// Get item
async function getItem() {
  const params = {
    TableName: tableName,
    Key: {
      id: '123'
    }
  };

  try {
    const result = await docClient.send(new GetCommand(params));
    console.log('Item retrieved:', result.Item);
    return result.Item;
  } catch (error) {
    console.error('Error getting item:', error);
  }
}

// Run both operations
async function main() {
  await putItem();
  await getItem();
}

main();


// Install dependencies:
// bash
// npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb


// Run:
// bash
// node app.js