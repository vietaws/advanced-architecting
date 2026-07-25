const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.RDS_HOST,
  port:     parseInt(process.env.RDS_PORT || '5432'),
  database: process.env.RDS_DATABASE,
  user:     process.env.RDS_USER,
  password: process.env.RDS_PASSWORD,
  ssl: {
    rejectUnauthorized: false
  }
});

pool.on('error', (err) => {
  console.error('PostgreSQL pool error:', err);
});

pool.on('connect', () => {
  console.log('Connected to PostgreSQL');
});

module.exports = pool;
