import http from 'http';
import dns from 'dns/promises';
import fs from 'fs';
import pg from 'pg';

const { Client } = pg;

const DB_CONFIG = {
  host: 'db.cloud.viet.vn',
  port: 5432,
  database: 'demo',
  user: 'dbadmin',
  password: 'DemoPassword',
  connectionTimeoutMillis: 3000,
};

// ── DNS resolver helper ────────────────────────────────────────────────────────

function getDnsResolver() {
  try {
    const resolv = fs.readFileSync('/etc/resolv.conf', 'utf8');
    const match = resolv.match(/^nameserver\s+(\S+)/m);
    return match ? match[1] : 'unknown';
  } catch {
    return 'unknown';
  }
}

// ── DB helper ──────────────────────────────────────────────────────────────────

async function query(sql, params = []) {
  const client = new Client(DB_CONFIG);
  await client.connect();
  try {
    return await client.query(sql, params);
  } finally {
    await client.end().catch(() => {});
  }
}

// ── Styles ─────────────────────────────────────────────────────────────────────
// Cloud theme: AWS-inspired teal/cyan gradient instead of purple

const BASE_STYLE = `
  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: linear-gradient(135deg, #0f2027 0%, #203a43 50%, #2c5364 100%);
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
  }

  .container {
    max-width: 860px;
    width: 100%;
    background: white;
    border-radius: 16px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.4);
    overflow: hidden;
  }

  .header {
    background: #f0f8ff;
    padding: 40px 30px;
    text-align: center;
    border-bottom: 1px solid #daeeff;
  }
  .header h1 { color: #1a2f3a; font-size: 1.75rem; margin-bottom: 8px; }
  .header p  { color: #6b8fa8; font-size: 0.9rem; }

  /* Cloud badge in header */
  .cloud-badge {
    display: inline-block;
    background: linear-gradient(135deg, #00b4d8 0%, #0077b6 100%);
    color: white;
    font-size: 0.72rem;
    font-weight: 700;
    padding: 3px 10px;
    border-radius: 20px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    margin-bottom: 12px;
  }

  .body { padding: 30px; }

  /* ── Table ── */
  .table-wrap { overflow-x: auto; border-radius: 12px; margin-bottom: 20px; }

  table { width: 100%; border-collapse: collapse; }

  thead tr { border-bottom: 2px solid #e8f4fd; }
  th {
    padding: 10px 16px;
    text-align: left;
    font-size: 0.72rem;
    font-weight: 700;
    color: #8fb3cc;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    white-space: nowrap;
  }
  tbody tr {
    border-bottom: 1px solid #f0f7fc;
    transition: background 0.15s;
  }
  tbody tr:last-child { border-bottom: none; }
  tbody tr:hover { background: #f0f8ff; }
  td {
    padding: 14px 16px;
    font-size: 0.93rem;
    color: #2c3e50;
    vertical-align: middle;
  }

  td.col-id    { color: #b0c8d8; font-size: 0.82rem; font-weight: 500; width: 40px; }
  td.col-name  { font-weight: 500; }

  /* Price badge — cloud teal */
  td.col-price .badge {
    display: inline-block;
    background: #e0f4fb;
    color: #0077b6;
    font-weight: 600;
    font-size: 0.85rem;
    padding: 3px 10px;
    border-radius: 20px;
  }

  /* SKU badge */
  td.col-qty .sku-badge {
    display: inline-block;
    background: #f0f4f8;
    color: #5a7a8a;
    font-size: 0.78rem;
    font-weight: 600;
    padding: 3px 9px;
    border-radius: 6px;
    letter-spacing: 0.04em;
    font-family: 'SF Mono', 'Fira Mono', monospace;
  }

  td.col-actions { width: 100px; }
  .actions { display: flex; align-items: center; gap: 12px; }
  .action-link {
    font-size: 0.82rem;
    font-weight: 600;
    text-decoration: none;
    border: none;
    background: none;
    cursor: pointer;
    padding: 0;
    transition: opacity 0.15s;
  }
  .action-link:hover { opacity: 0.65; }
  .action-link.edit   { color: #0077b6; }
  .action-link.delete { color: #e74c3c; }
  .actions .divider   { color: #d0e4f0; font-size: 0.8rem; }

  /* ── DB Status bar ── */
  .db-status {
    display: flex;
    align-items: center;
    gap: 10px;
    background: #f0f8ff;
    border: 1px solid #daeeff;
    border-radius: 8px;
    padding: 9px 14px;
    margin-bottom: 20px;
    font-size: 0.82rem;
    color: #5a7a8a;
  }
  .db-status .dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: #2ecc71; flex-shrink: 0;
  }
  .db-status .dot.err { background: #e74c3c; }
  .db-status strong { color: #1a2f3a; }

  /* ── Add button — cloud teal gradient ── */
  .add-btn {
    display: inline-block;
    padding: 11px 28px;
    background: linear-gradient(135deg, #00b4d8 0%, #0077b6 100%);
    color: white;
    border: none;
    border-radius: 10px;
    font-size: 0.92rem;
    font-weight: 600;
    cursor: pointer;
    text-align: center;
    text-decoration: none;
    transition: opacity 0.2s, transform 0.1s;
    margin-top: 6px;
  }
  .add-btn:hover  { opacity: 0.9; }
  .add-btn:active { transform: scale(0.98); }

  /* ── Form ── */
  .back {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-bottom: 22px;
    color: #0077b6;
    text-decoration: none;
    font-size: 0.88rem;
    font-weight: 600;
  }
  .back:hover { opacity: 0.7; }

  .form-wrapper {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: left;
  }

  .form-card {
    background: #f5fbff;
    padding: 28px;
    border-radius: 12px;
    border: 1px solid #daeeff;
    max-width: 420px;
    width: 100%;
    margin: 0 auto 20px;
    text-align: center;
  }
  .form-card label { text-align: left; }
  label { display: block; margin-bottom: 18px; }
  label span {
    display: block;
    margin-bottom: 6px;
    font-size: 0.75rem;
    font-weight: 700;
    color: #8fb3cc;
    text-transform: uppercase;
    letter-spacing: 0.07em;
  }
  input {
    width: 100%;
    padding: 10px 13px;
    border: 1.5px solid #cce4f0;
    border-radius: 8px;
    font-size: 0.95rem;
    background: white;
    color: #2c3e50;
    transition: border-color 0.2s, box-shadow 0.2s;
  }
  input:focus {
    outline: none;
    border-color: #00b4d8;
    box-shadow: 0 0 0 3px rgba(0,180,216,0.12);
  }

  /* ── Alerts ── */
  .alert {
    padding: 11px 16px;
    border-radius: 8px;
    margin-bottom: 18px;
    font-size: 0.88rem;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .alert-error   { background: #fff0f0; color: #c0392b; border-left: 3px solid #e74c3c; }

  /* ── Footer ── */
  .footer {
    background: #f0f8ff;
    padding: 10px 20px;
    border-top: 1px solid #daeeff;
  }
  .footer .db-status {
    margin-bottom: 0;
    background: transparent;
    border: none;
    justify-content: center;
    padding: 4px 0;
  }

  @media (max-width: 600px) {
    .header { padding: 28px 20px; }
    .header h1 { font-size: 1.35rem; }
    .body { padding: 20px; }
    th, td { padding: 10px 12px; }
    .form-card { padding: 20px; }
    .footer { padding: 12px 20px; }
  }
`;

// ── Layout ─────────────────────────────────────────────────────────────────────

function layout(title, body, dbStatus = '') {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>${BASE_STYLE}</style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="cloud-badge">⛅️ AWS Cloud</div>
      <h1>${title}</h1>
      <p>app.cloud.viet.vn &nbsp;·&nbsp; 10.1.0.40 &nbsp;·&nbsp; VPC A (ap-southeast-1)</p>
    </div>
    <div class="body">${body}</div>
    <div class="footer">${dbStatus}</div>
  </div>
</body>
</html>`;
}

// ── Handlers ───────────────────────────────────────────────────────────────────

async function listProducts(req, res) {
  let rows = [], err = null, dbIp = null;

  // Resolve DB hostname and query in parallel
  const [resolveResult, queryResult] = await Promise.allSettled([
    dns.lookup(DB_CONFIG.host),
    (async () => {
      const r = await query('SELECT id, name, price, sku FROM products ORDER BY id');
      return r.rows;
    })()
  ]);

  if (resolveResult.status === 'fulfilled') dbIp = resolveResult.value.address;
  if (queryResult.status === 'fulfilled') rows = queryResult.value;
  else err = queryResult.reason.message;

  const statusBar = `
    <div class="db-status">
      <span class="dot${err ? ' err' : ''}"></span>
      <span>
        <strong>${DB_CONFIG.host}</strong>
        &nbsp;·&nbsp; ${dbIp || 'unresolved'}
        &nbsp;·&nbsp; resolver: ${getDnsResolver()}
      </span>
    </div>`;

  const alert = err
    ? `<div class="alert alert-error"><strong>DB error:</strong> ${err}</div>`
    : '';

  const table = err ? '' : `
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Name</th>
            <th>Price</th>
            <th>Qty</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${rows.map(r => `
          <tr>
            <td class="col-id">${r.id}</td>
            <td class="col-name">${r.name}</td>
            <td class="col-price"><span class="badge">$${parseFloat(r.price).toFixed(2)}</span></td>
            <td class="col-qty"><span class="sku-badge">${r.sku || '—'}</span></td>
            <td class="col-actions">
              <div class="actions">
                <a class="action-link edit" href="/edit/${r.id}">Edit</a>
                <span class="divider">|</span>
                <form method="POST" action="/delete/${r.id}" style="margin:0">
                  <button class="action-link delete" type="submit"
                    onclick="return confirm('Delete ${r.name}?')">Delete</button>
                </form>
              </div>
            </td>
          </tr>`).join('')}
        </tbody>
      </table>
    </div>`;

  const body = `
    ${alert}
    ${table}
    <div style="text-align:center">
      <a class="add-btn" href="/new">+ Add Product</a>
    </div>`;

  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(layout('Cloud Inventory', body, statusBar));
}

function newForm(res, err = null) {
  const body = `
    <div class="form-wrapper">
      <a class="back" href="/">← Back</a>
      ${err ? `<div class="alert alert-error">${err}</div>` : ''}
      <div class="form-card">
        <form method="POST" action="/create">
          <label><span>Name</span><input name="name" required autofocus></label>
          <label><span>Price</span><input name="price" type="number" step="0.01" min="0" required></label>
          <label><span>SKU</span><input name="sku" placeholder="e.g. SKU001" required></label>
          <button class="add-btn" type="submit">Save Product</button>
        </form>
      </div>
    </div>`;
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(layout('Add Product', body));
}

async function createProduct(body, res) {
  const p = new URLSearchParams(body);
  try {
    await query(
      'INSERT INTO products (name, price, sku) VALUES ($1, $2, $3)',
      [p.get('name'), parseFloat(p.get('price')), p.get('sku')]
    );
    res.writeHead(302, { Location: '/' });
    res.end();
  } catch (e) { newForm(res, e.message); }
}

async function editForm(id, res, err = null) {
  let product;
  try {
    const r = await query('SELECT * FROM products WHERE id = $1', [id]);
    product = r.rows[0];
  } catch (e) { err = e.message; }

  if (!product) { res.writeHead(302, { Location: '/' }); res.end(); return; }

  const body = `
    <div class="form-wrapper">
      <a class="back" href="/">← Back</a>
      ${err ? `<div class="alert alert-error">${err}</div>` : ''}
      <div class="form-card">
        <form method="POST" action="/update/${product.id}">
          <label><span>Name</span>
            <input name="name" value="${product.name}" required autofocus></label>
          <label><span>Price</span>
            <input name="price" type="number" step="0.01" min="0"
                   value="${parseFloat(product.price).toFixed(2)}" required></label>
          <label><span>SKU</span>
            <input name="sku"
                   value="${product.sku}" required></label>
          <button class="add-btn" type="submit">Update Product</button>
        </form>
      </div>
    </div>`;
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(layout(`Edit Product #${product.id}`, body));
}

async function updateProduct(id, body, res) {
  const p = new URLSearchParams(body);
  try {
    await query(
      'UPDATE products SET name=$1, price=$2, sku=$3 WHERE id=$4',
      [p.get('name'), parseFloat(p.get('price')), p.get('sku'), id]
    );
    res.writeHead(302, { Location: '/' });
    res.end();
  } catch (e) { editForm(id, res, e.message); }
}

async function deleteProduct(id, res) {
  await query('DELETE FROM products WHERE id = $1', [id]).catch(() => {});
  res.writeHead(302, { Location: '/' });
  res.end();
}

function readBody(req) {
  return new Promise(resolve => {
    let data = '';
    req.on('data', chunk => data += chunk);
    req.on('end', () => resolve(data));
  });
}

// ── Router ────────────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];
  const method = req.method;

  try {
    if (url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', host: 'app.cloud.viet.vn', ip: '10.1.0.50' }));
      return;
    }

    if (method === 'GET'  && url === '/')       return await listProducts(req, res);
    if (method === 'GET'  && url === '/new')     return newForm(res);
    if (method === 'POST' && url === '/create')  return await createProduct(await readBody(req), res);

    const edit   = url.match(/^\/edit\/(\d+)$/);
    const update = url.match(/^\/update\/(\d+)$/);
    const del    = url.match(/^\/delete\/(\d+)$/);

    if (method === 'GET'  && edit)   return await editForm(edit[1], res);
    if (method === 'POST' && update) return await updateProduct(update[1], await readBody(req), res);
    if (method === 'POST' && del)    return await deleteProduct(del[1], res);

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');

  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end(`Server error: ${e.message}`);
  }
});

const PORT = 80;
server.listen(PORT, () => {
  console.log(`App server listening on port ${PORT}`);
  console.log(`DB: ${DB_CONFIG.host}:${DB_CONFIG.port}/${DB_CONFIG.database}`);
});