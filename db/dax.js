const { DynamoDBDocumentClient, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const AmazonDaxClient = require('amazon-dax-client');
const config = require('../app_config.json');

const dax = new AmazonDaxClient({ endpoints: [config.dax.endpoint], region: config.dynamodb.region });
const daxDocClient = DynamoDBDocumentClient.from(dax);

module.exports = { 
  daxDocClient, 
  ScanCommand, 
  productsTableName: config.dynamodb.productsTableName 
};
