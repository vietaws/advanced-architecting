const API_URL = window.location.origin;

// Tab switching
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        const target = tab.dataset.tab;
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(target).classList.add('active');
        
        if (target === 'home') loadDashboard();
        else if (target === 'products') loadProducts();
        else if (target === 'products-dax') loadProductsDax();
        else if (target === 'providers') loadProviders();
        else if (target === 'orders') {} // Orders tab - no auto-load
        else if (target === 'stress') loadStressStatus();
    });
});

// Products
async function loadProducts() {
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
    if (imageFile) {
        formData.append('image', imageFile);
    }

    await fetch(`${API_URL}/products`, {
        method: 'POST',
        body: formData
    });
    hideProductForm();
    loadProducts();
}

async function deleteProduct(id) {
    if (confirm('Delete this product?')) {
        await fetch(`${API_URL}/products/${id}`, {method: 'DELETE'});
        loadProducts();
    }
}

// Products DAX
async function loadProductsDax() {
    try {
        const res = await fetch(`${API_URL}/products-dax`);
        const products = await res.json();
        
        if (!res.ok) {
            console.error('Error loading products via DAX:', products);
            document.getElementById('products-dax-list').innerHTML = '<p style="text-align:center;color:red;padding:20px;">Error loading products via DAX</p>';
            return;
        }
        
        if (products.length === 0) {
            document.getElementById('products-dax-list').innerHTML = '<p style="text-align:center;color:#999;padding:20px;">No products found. Add products in the Products tab first.</p>';
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
        document.getElementById('products-dax-list').innerHTML = '<p style="text-align:center;color:red;padding:20px;">Error: ' + error.message + '</p>';
    }
}


// Providers
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
        if (imageFile) {
            formData.append('image', imageFile);
        }

        const res = await fetch(`${API_URL}/providers`, {
            method: 'POST',
            body: formData
        });

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

// Initial load
loadDashboard();

// Dashboard
// Each microservice exposes its own GET /health/status.
// We call all 3 in parallel and merge the results into the dashboard cards.
//
//  product-service  → /products/health/status  → { dynamodb, dax, s3 }
//  provider-service → /providers/health/status → { aurora, efs }
//  order-service    → /orders/health/status    → { sqs, dynamodb* }
//
// *order-service returns its own DynamoDB key; we surface it as "dynamodb"
//  only when the product-service card is absent (no duplicate card on the page).

async function loadDashboard() {
    const allServices = ['dynamodb', 'dax', 's3', 'aurora', 'efs', 'sqs'];

    // Reset all cards to "Checking..." state
    allServices.forEach(svc => {
        const badge = document.querySelector(`#status-${svc} .status-badge`);
        if (badge) {
            badge.textContent = 'Checking...';
            badge.className = 'status-badge checking';
        }
    });

    // Fire all 3 health checks in parallel
    const [productResult, providerResult, orderResult] = await Promise.allSettled([
        fetch(`${API_URL}/products/health/status`).then(r => r.json()),
        fetch(`${API_URL}/providers/health/status`).then(r => r.json()),
        fetch(`${API_URL}/orders/health/status`).then(r => r.json()),
    ]);

    // Merge all responses into one flat map  { serviceName -> { status, error? } }
    const data = {};

    if (productResult.status === 'fulfilled') {
        Object.assign(data, productResult.value);
    } else {
        console.error('product-service health check failed:', productResult.reason);
        ['dynamodb', 'dax', 's3'].forEach(s => { data[s] = { status: 'disconnected', error: 'unreachable' }; });
    }

    if (providerResult.status === 'fulfilled') {
        Object.assign(data, providerResult.value);
    } else {
        console.error('provider-service health check failed:', providerResult.reason);
        ['aurora', 'efs'].forEach(s => { data[s] = { status: 'disconnected', error: 'unreachable' }; });
    }

    if (orderResult.status === 'fulfilled') {
        // order-service reports "dynamodb" for orders_table — surface it as "sqs" is separate;
        // only update the dynamodb card if product-service didn't already set it.
        const orderData = orderResult.value;
        data['sqs'] = orderData['sqs'] || { status: 'disconnected', error: 'unreachable' };
        // order DynamoDB result — product-service DynamoDB takes precedence for the shared card
        if (!data['dynamodb']) {
            data['dynamodb'] = orderData['dynamodb'] || { status: 'disconnected', error: 'unreachable' };
        }
    } else {
        console.error('order-service health check failed:', orderResult.reason);
        data['sqs'] = { status: 'disconnected', error: 'unreachable' };
    }

    // Update every status card
    allServices.forEach(svc => {
        const badge = document.querySelector(`#status-${svc} .status-badge`);
        if (!badge) return;

        const info = data[svc];
        if (!info) {
            badge.textContent = 'Unknown';
            badge.className = 'status-badge checking';
            return;
        }

        const s = info.status;
        badge.textContent = s.charAt(0).toUpperCase() + s.slice(1);
        badge.className = `status-badge ${s}`;
    });
}

// Load instance ID
async function loadInstanceId() {
    try {
        const res = await fetch(`${API_URL}/instance-id`);
        const data = await res.json();
        document.getElementById('instance-id').textContent = `Instance: ${data.instanceId}`;
    } catch (error) {
        document.getElementById('instance-id').textContent = 'Instance: unknown';
    }
}

loadInstanceId();

// Stress Test
let stressInterval = null;

async function startStress() {
    try {
        const res = await fetch(`${API_URL}/stress/start`, { method: 'POST' });
        const data = await res.json();
        console.log('Stress test started:', data);
        
        if (!stressInterval) {
            stressInterval = setInterval(loadAllInstances, 3000);
        }
        loadAllInstances();
    } catch (error) {
        console.error('Error starting stress test:', error);
        alert('Failed to start stress test');
    }
}

async function stopStress() {
    try {
        const res = await fetch(`${API_URL}/stress/stop`, { method: 'POST' });
        const data = await res.json();
        console.log('Stress test stopped:', data);
        loadAllInstances();
    } catch (error) {
        console.error('Error stopping stress test:', error);
        alert('Failed to stop stress test');
    }
}

async function loadAllInstances() {
    try {
        // Get current instance status only
        const res = await fetch(`${API_URL}/stress/status`);
        const data = await res.json();
        
        // Render table with single row
        const tbody = document.getElementById('instances-tbody');
        tbody.innerHTML = `
            <tr>
                <td data-label="Instance ID">${data.instanceId}</td>
                <td data-label="Status" class="${data.running ? 'status-running' : 'status-stopped'}">
                    ${data.running ? 'Running' : 'Stopped'}
                </td>
                <td data-label="Workers">${data.workers}</td>
                <td data-label="CPU Usage">${data.cpu.toFixed(1)}%</td>
                <td data-label="CPU Cores">${data.cores}</td>
                <td data-label="Actions" class="actions">
                    <button class="btn-small btn-start" onclick="startStress()">Start</button>
                    <button class="btn-small btn-stop" onclick="stopStress()">Stop</button>
                </td>
            </tr>
        `;
    } catch (error) {
        console.error('Error loading instance:', error);
        const tbody = document.getElementById('instances-tbody');
        tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:red;">Error loading instance</td></tr>';
    }
}

async function loadStressStatus() {
    loadAllInstances();
    if (!stressInterval) {
        stressInterval = setInterval(loadAllInstances, 3000);
    }
}

// Orders
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



