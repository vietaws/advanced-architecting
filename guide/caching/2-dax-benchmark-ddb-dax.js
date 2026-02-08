const AmazonDaxClient = require('amazon-dax-client');

// Create DAX client
const dax = new AmazonDaxClient({
  endpoints: ['my-dax-cluster.xxxxx.dax-clusters.us-east-1.amazonaws.com:8111'],
  region: 'us-east-1'
});

const tableName = 'products';

// Put item
async function putItem() {
  const params = {
    TableName: tableName,
    Item: {
      id: { S: '123' },
      name: { S: 'Product Name' },
      price: { N: '29.99' },
      category: { S: 'Electronics' }
    }
  };

  try {
    await dax.putItem(params);
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
      id: { S: '123' }
    }
  };

  try {
    const result = await dax.getItem(params);
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


// Install dependency:
// bash
// npm install amazon-dax-client


// Run:
// bash
// node app.js