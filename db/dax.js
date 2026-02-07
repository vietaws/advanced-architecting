const AmazonDaxClient = require('amazon-dax-client');
const { DynamoDBDocumentClient, PutCommand, GetCommand, UpdateCommand, DeleteCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../app_config.json');

const dax = new AmazonDaxClient({ endpoints: [config.dax.endpoint], region: config.dynamodb.region });
const daxDocClient = DynamoDBDocumentClient.from(dax);

module.exports = { 
  daxDocClient, 
  PutCommand, 
  GetCommand, 
  UpdateCommand, 
  DeleteCommand, 
  ScanCommand, 
  productsTableName: config.dynamodb.productsTableName 
};
