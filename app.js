'use strict';

const http = require('http');
const { Client } = require('pg');

const DB_CONFIG = {
  host: 'db.corp.local',
  port: 5432,
  database: 'corp_demo',
  user: 'demo',
  password: 'DemoPassword',
  connectionTimeoutMillis: 3000,
};

function renderPage(rows, err) {
  const tableRows = rows
    .map(r => `
        <tr>
          <td>${r.id}</td>
          <td>${r.name}</td>
          <td>$${parseFloat(r.price).toFixed(2)}</td>
          <td>${r.sku}</td>
        </tr>`)
    .join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>On-Prem App Server</title>
  <style>
    body        { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
    h1          { color: #333; margin-bottom: 4px; }
    .meta       { color: #888; font-size: 0.85em; margin-bottom: 28px; }
    h2          { color: #444; margin-bottom: 12px; }
    table       { border-collapse: collapse; background: #fff;
                  box-shadow: 0 1px 4px rgba(0,0,0,0.1); min-width: 400px; }
    th          { background: #2c6fad; color: #fff; padding: 10px 18px; text-align: left; }
    td          { padding: 9px 18px; border-bottom: 1px solid #eee; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: #f0f7ff; }
    .error      { color: #c0392b; background: #fdecea;
                  padding: 12px 16px; border-radius: 4px; }
    .source     { color: #888; font-size: 0.85em; margin-left: 8px; }
  </style>
</head>
<body>
  <h1>On-Premises App Server</h1>
  <div class="meta">
    host: app.corp.local &nbsp;|&nbsp;
    ip: 10.2.1.20 &nbsp;|&nbsp;
    env: VPC OP (simulated on-premises)
  </div>

  <h2>Products <span class="source">from db.corp.local</span></h2>

  ${err
    ? `<div class="error"><strong>DB error:</strong> ${err}</div>`
    : `<table>
      <thead>
        <tr><th>ID</th><th>Name</th><th>Price</th><th>SKU</th></tr>
      </thead>
      <tbody>${tableRows}</tbody>
    </table>`
  }
</body>
</html>`;
}

const server = http.createServer(async (req, res) => {
  // Health check endpoint
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      host: 'app.corp.local',
      ip: '10.2.1.20',
      env: 'on-premises',
    }));
    return;
  }

  // Main page — fetch products from DB
  const client = new Client(DB_CONFIG);
  let rows = [];
  let err = null;

  try {
    await client.connect();
    const result = await client.query(
      'SELECT id, name, price, sku FROM products ORDER BY id'
    );
    rows = result.rows;
  } catch (e) {
    err = e.message;
  } finally {
    await client.end().catch(() => {});
  }

  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(renderPage(rows, err));
});

const PORT = 80;
server.listen(PORT, () => {
  console.log(`App server listening on port ${PORT}`);
  console.log(`DB: ${DB_CONFIG.host}:${DB_CONFIG.port}/${DB_CONFIG.database}`);
});
