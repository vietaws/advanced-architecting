const AmazonDaxClient = require('amazon-dax-client');

const dax = new AmazonDaxClient({
  endpoints: [process.env.DAX_ENDPOINT],
  region: process.env.AWS_REGION,
});

module.exports = {
  daxClient: dax,
  productsTableName: process.env.DYNAMODB_PRODUCTS_TABLE,
};
