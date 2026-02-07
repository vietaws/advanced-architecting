const AmazonDaxClient = require('amazon-dax-client');
const config = require('../app_config.json');

const dax = new AmazonDaxClient({ endpoints: [config.dax.endpoint], region: config.dynamodb.region });

module.exports = { 
  daxClient: dax,
  productsTableName: config.dynamodb.productsTableName 
};
