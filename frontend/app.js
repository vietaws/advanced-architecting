// API_URL comes from config.js which is loaded before this script.
// Empty string means frontend-only mode — no backend calls are made.
const API_URL = (window.APP_CONFIG && window.APP_CONFIG.API_URL) || '';

// ── Tab switching ─────────────────────────────────────────────────────────────
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        const target = tab.dataset.tab;
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(target).classList.add('active');

        if (target === 'home')              loadDashboard();
        else if (target === 'products')     loadProducts();
        else if (target === 'products-dax') loadProductsDax();
        else if (target === 'providers')    loadProviders();
        // orders tab has no auto-load — user triggers manually
    });
});

// ── Dashboard ─────────────────────────────────────────────────────────────────
//
// Service groups and the AWS resources each one reports:
//
//   Product Service  → GET /products/health/status  → { dynamodb, dax, s3 }
//   Provider Service → GET /providers/health/status → { aurora, efs }
//   Order Service    → GET /orders/health/status    → { sqs }
//
// When API_URL is empty (frontend-only mode) every resource shows Disconnected
// immediately without making any network request.

const SERVICE_GROUPS = [
    {
        id: 'product',
        name: 'Product Service',
        icon: '📦',
        endpoint: '/products/health/status',
        resources: [
            { key: 'dynamodb', label: 'DynamoDB', icon: '⚡' },
            { key: 'dax',      label: 'DAX',      icon: '🚀' },
            { key: 's3',       label: 'S3',        icon: '🪣' },
        ],
    },
    {
        id: 'provider',
        name: 'Provider Service',
        icon: '🏭',
        endpoint: '/providers/health/status',
        resources: [
            { key: 'aurora', label: 'Aurora (RDS)', icon: '🗄️' },
            { key: 'efs',    label: 'EFS',          icon: '📁' },
        ],
    },
    {
        id: 'order',
        name: 'Order Service',
        icon: '🛒',
        endpoint: '/orders/health/status',
        resources: [
            { key: 'sqs', label: 'SQS', icon: '📨' },
        ],
    },
];

// Build the dashboard cards from SERVICE_GROUPS on first load.
function buildDashboardCards() {
    const grid = document.getElementById('dashboard-grid');
    grid.innerHTML = SERVICE_GROUPS.map(group => `
        <div class="service-group-card" id="group-${group.id}">
            <div class="service-group-header">
                <span class="service-group-icon">${group.icon}</span>
                <span class="service-group-name">${group.name}</span>
            </div>
            <div class="resource-list">
                ${group.resources.map(r => `
                    <div class="resource-item" id="resource-${r.key}">
                        <span class="resource-icon">${r.icon}</span>
                        <span class="resource-label">${r.label}</span>
                        <span class="status-badge disconnected" id="badge-${r.key}">Disconnected</span>
                    </div>
                `).join('')}
            </div>
        </div>
    `).join('');
}

// Set every badge to a given state without making any API calls.
function setAllBadges(state, text) {
    SERVICE_GROUPS.forEach(group => {
        group.resources.forEach(r => {
            const badge = document.getElementById(`badge-${r.key}`);
            if (badge) {
                badge.textContent = text;
                badge.className = `status-badge ${state}`;
            }
        });
    });
}

// Apply a flat result map { resourceKey: { status, error? } } to the badges.
function applyResults(data) {
    SERVICE_GROUPS.forEach(group => {
        group.resources.forEach(r => {
            const badge = document.getElementById(`badge-${r.key}`);
            if (!badge) return;
            const info = data[r.key];
            if (!info) {
                badge.textContent = 'Unknown';
                badge.className = 'status-badge checking';
                return;
            }
            const s = info.status;
            badge.textContent = s.charAt(0).toUpperCase() + s.slice(1);
            badge.className = `status-badge ${s}`;
        });
    });
}

async function loadDashboard() {
    // No backend configured — show Disconnected immediately, no network calls.
    if (!API_URL) {
        setAllBadges('disconnected', 'Disconnected');
        return;
    }

    // Reset to Checking...
    setAllBadges('checking', 'Checking…');

    // Fire all 3 health checks in parallel.
    const results = await Promise.allSettled(
        SERVICE_GROUPS.map(group =>
            fetch(`${API_URL}${group.endpoint}`).then(r => r.json())
        )
    );

    // Merge all responses into one flat map.
    const data = {};

    results.forEach((result, i) => {
        const group = SERVICE_GROUPS[i];
        if (result.status === 'fulfilled') {
            Object.assign(data, result.value);
        } else {
            console.error(`${group.name} health check failed:`, result.reason);
            group.resources.forEach(r => {
                data[r.key] = { status: 'disconnected', error: 'unreachable' };
            });
        }
    });

    applyResults(data);
}

// ── Products (DynamoDB) ───────────────────────────────────────────────────────
async function loadProducts() {
    try {
        const res = await fetch(`${API_URL}/products`);
        const products = await res.json();
        document.getElementById('products-list').innerHTML = products.map(p => `
            <div class="card">
                ${p.image_url ? `<img src="${p.image_url}" alt="${p.product_name}" style="width:100%;height:200px;object-fit:cover;border-radius:8px 8px 0 0;margin:-16px -16px 12px -16px;">` : ''}
                <h3>${p.product_name}</h3>
                <p>${p.description || ''}</p>
                <div class="price">$${p.price}</div>
                <p>Stock: ${p.remaining_sku}</p>
                <p style="font-size:12px;color:#999;">ID: ${p.id}</p>
                <p style="font-size:11px;color:#4caf50;margin-top:8px;">⚡ DynamoDB: ${p.responseTime}ms</p>
                <button class="btn-delete" onclick="deleteProduct('${p.id}')">Delete</button>
            </div>
        `).join('');
    } catch (error) {
        console.error('Error loading products:', error);
        document.getElementById('products-list').innerHTML = '<p style="color:red;">Error loading products</p>';
    }
}

function showProductForm() {
    document.getElementById('product-form').classList.remove('hidden');
}

function hideProductForm() {
    document.getElementById('product-form').classList.add('hidden');
    document.querySelectorAll('#product-form input, #product-form textarea').forEach(i => i.value = '');
}

async function createProduct() {
    const formData = new FormData();
    formData.append('product_name', document.getElementById('product_name').value);
    formData.append('description', document.getElementById('description').value);
    formData.append('price', document.getElementById('price').value);
    formData.append('remaining_sku', document.getElementById('remaining_sku').value);

    const imageFile = document.getElementById('image_file').files[0];
    if (imageFile) formData.append('image', imageFile);

    await fetch(`${API_URL}/products`, { method: 'POST', body: formData });
    hideProductForm();
    loadProducts();
}

async function deleteProduct(id) {
    if (confirm('Delete this product?')) {
        await fetch(`${API_URL}/products/${id}`, { method: 'DELETE' });
        loadProducts();
    }
}

// ── Products (DAX) ────────────────────────────────────────────────────────────
async function loadProductsDax() {
    try {
        const res = await fetch(`${API_URL}/products-dax`);
        const products = await res.json();

        if (!res.ok) {
            document.getElementById('products-dax-list').innerHTML =
                '<p style="text-align:center;color:red;padding:20px;">Error loading products via DAX</p>';
            return;
        }

        if (products.length === 0) {
            document.getElementById('products-dax-list').innerHTML =
                '<p style="text-align:center;color:#999;padding:20px;">No products found. Add products in the Products tab first.</p>';
            return;
        }

        document.getElementById('products-dax-list').innerHTML = products.map(p => `
            <div class="card">
                ${p.image_url ? `<img src="${p.image_url}" alt="${p.product_name}" style="width:100%;height:200px;object-fit:cover;border-radius:8px 8px 0 0;margin:-16px -16px 12px -16px;">` : ''}
                <h3>${p.product_name}</h3>
                <p>${p.description || ''}</p>
                <div class="price">$${p.price}</div>
                <p>Stock: ${p.remaining_sku}</p>
                <p style="font-size:12px;color:#999;">ID: ${p.id}</p>
                <p style="font-size:11px;color:#ff6b6b;margin-top:8px;">⚡ DAX: ${p.responseTime}μs</p>
            </div>
        `).join('');
    } catch (error) {
        console.error('Error loading products via DAX:', error);
        document.getElementById('products-dax-list').innerHTML =
            `<p style="text-align:center;color:red;padding:20px;">Error: ${error.message}</p>`;
    }
}

// ── Providers (RDS) ───────────────────────────────────────────────────────────
async function loadProviders() {
    try {
        const res = await fetch(`${API_URL}/providers?_=${Date.now()}`, {
            cache: 'no-store',
            headers: { 'Cache-Control': 'no-cache', 'Pragma': 'no-cache' }
        });
        const providers = await res.json();

        if (!Array.isArray(providers)) {
            console.error('Providers response is not an array:', providers);
            return;
        }

        document.getElementById('providers-list').innerHTML = providers.map(p => `
            <div class="card">
                ${p.image_url ? `<img src="${p.image_url}" alt="${p.name}" style="width:100%;height:200px;object-fit:cover;border-radius:8px 8px 0 0;margin:-16px -16px 12px -16px;">` : ''}
                <h3>${p.name}</h3>
                <p>${p.city || ''}</p>
                <p style="font-size:12px;color:#999;">ID: ${p.id}</p>
                <p style="font-size:11px;color:#2196f3;margin-top:8px;">⚡ RDS PostgreSQL: ${p.responseTime || 'N/A'}ms</p>
                <button class="btn-delete" onclick="deleteProvider('${p.id}')">Delete</button>
            </div>
        `).join('');
    } catch (error) {
        console.error('Error loading providers:', error);
        document.getElementById('providers-list').innerHTML = '<p style="color:red;">Error loading providers</p>';
    }
}

function showProviderForm() {
    document.getElementById('provider-form').classList.remove('hidden');
}

function hideProviderForm() {
    document.getElementById('provider-form').classList.add('hidden');
    document.querySelectorAll('#provider-form input').forEach(i => i.value = '');
}

async function createProvider() {
    try {
        const formData = new FormData();
        formData.append('name', document.getElementById('provider_name').value);
        formData.append('city', document.getElementById('provider_city').value);

        const imageFile = document.getElementById('provider_image').files[0];
        if (imageFile) formData.append('image', imageFile);

        const res = await fetch(`${API_URL}/providers`, { method: 'POST', body: formData });
        const result = await res.json();

        if (!res.ok) {
            alert(`Error: ${result.error || 'Failed to create provider'}`);
            return;
        }

        hideProviderForm();
        loadProviders();
    } catch (error) {
        console.error('Error creating provider:', error);
        alert('Failed to create provider');
    }
}

async function deleteProvider(id) {
    if (confirm('Delete this provider?')) {
        await fetch(`${API_URL}/providers/${id}`, { method: 'DELETE' });
        loadProviders();
    }
}

// ── Orders (SQS + DynamoDB) ───────────────────────────────────────────────────
async function generateOrders() {
    const statusEl = document.getElementById('order-status');
    const btn = event.target;
    btn.disabled = true;
    statusEl.textContent = 'Generating orders...';
    statusEl.style.color = '#666';

    try {
        const response = await fetch(`${API_URL}/orders/generate`, { method: 'POST' });
        const data = await response.json();

        if (response.ok) {
            statusEl.textContent = `✓ ${data.message}`;
            statusEl.style.color = 'green';
        } else {
            throw new Error(data.error);
        }
    } catch (error) {
        statusEl.textContent = `✗ Error: ${error.message}`;
        statusEl.style.color = 'red';
    } finally {
        btn.disabled = false;
        setTimeout(() => { statusEl.textContent = ''; }, 5000);
    }
}

async function getOrderStatus() {
    const statusEl = document.getElementById('order-status');
    const listEl = document.getElementById('orders-list');
    statusEl.textContent = 'Loading orders...';
    statusEl.style.color = '#666';

    try {
        const response = await fetch(`${API_URL}/orders`);
        const orders = await response.json();

        if (response.ok) {
            statusEl.textContent = `✓ Loaded ${orders.length} orders`;
            statusEl.style.color = 'green';

            if (orders.length === 0) {
                listEl.innerHTML = '<p style="text-align:center;color:#999;padding:20px;">No orders found</p>';
            } else {
                listEl.innerHTML = `
                    <table style="width:100%;border-collapse:collapse;margin-top:10px;">
                        <thead>
                            <tr style="background:#f0f0f0;text-align:left;">
                                <th style="padding:10px;border:1px solid #ddd;">Order ID</th>
                                <th style="padding:10px;border:1px solid #ddd;">Product</th>
                                <th style="padding:10px;border:1px solid #ddd;">Qty</th>
                                <th style="padding:10px;border:1px solid #ddd;">Price</th>
                                <th style="padding:10px;border:1px solid #ddd;">Customer</th>
                                <th style="padding:10px;border:1px solid #ddd;">Status</th>
                                <th style="padding:10px;border:1px solid #ddd;">Created</th>
                                <th style="padding:10px;border:1px solid #ddd;">Completed</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${orders.map(order => `
                                <tr>
                                    <td style="padding:10px;border:1px solid #ddd;">${order.id}</td>
                                    <td style="padding:10px;border:1px solid #ddd;">${order.product_name}</td>
                                    <td style="padding:10px;border:1px solid #ddd;">${order.qty}</td>
                                    <td style="padding:10px;border:1px solid #ddd;">$${order.price}</td>
                                    <td style="padding:10px;border:1px solid #ddd;">${order.customer_id}</td>
                                    <td style="padding:10px;border:1px solid #ddd;">
                                        <span style="background:${order.status === 'completed' ? '#4caf50' : '#ffc107'};color:${order.status === 'completed' ? 'white' : 'black'};padding:3px 8px;border-radius:4px;font-size:12px;">
                                            ${order.status}
                                        </span>
                                    </td>
                                    <td style="padding:10px;border:1px solid #ddd;">${new Date(order.time).toLocaleString()}</td>
                                    <td style="padding:10px;border:1px solid #ddd;">${order.completion_date ? new Date(order.completion_date).toLocaleString() : '-'}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                `;
            }
        } else {
            throw new Error(orders.error);
        }
    } catch (error) {
        statusEl.textContent = `✗ Error: ${error.message}`;
        statusEl.style.color = 'red';
        listEl.innerHTML = '';
    } finally {
        setTimeout(() => { statusEl.textContent = ''; }, 5000);
    }
}

// ── Init ──────────────────────────────────────────────────────────────────────
buildDashboardCards();
loadDashboard();
