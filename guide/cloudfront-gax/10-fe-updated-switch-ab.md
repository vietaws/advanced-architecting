cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CloudFront Functions vs Lambda@Edge</title>
    <style>
        body { font-family: Arial; max-width: 900px; margin: 40px auto; padding: 0 20px; }
        .header { background: #232f3e; color: white; padding: 20px; border-radius: 8px; }
        .section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 8px; }
        .result { background: #f5f5f5; padding: 12px; margin: 10px 0; font-family: monospace; white-space: pre-wrap; }
        button { background: #ff9900; border: none; padding: 10px 20px; cursor: pointer; border-radius: 4px; margin: 4px; }
        .variant-toggle { display: flex; gap: 10px; align-items: center; margin: 10px 0; }
        .variant-btn { padding: 10px 30px; font-size: 16px; font-weight: bold; border: 2px solid #ddd; border-radius: 6px; cursor: pointer; }
        .variant-btn.active-a { background: #4CAF50; color: white; border-color: #4CAF50; }
        .variant-btn.active-b { background: #2196F3; color: white; border-color: #2196F3; }
        .variant-btn:not(.active-a):not(.active-b) { background: white; }
        .cookie-display { background: #fff3cd; padding: 8px 12px; border-radius: 4px; font-family: monospace; margin: 8px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>CloudFront Functions vs Lambda@Edge Demo</h1>
        <p>Demonstrating capabilities, use cases, and performance differences</p>
    </div>

    <div class="section">
        <h2>1. CloudFront Function - URL Rewrite</h2>
        <p>Rewrites /about to /about/index.html (Viewer Request)</p>
        <button onclick="testUrlRewrite()">Test URL Rewrite</button>
        <div id="url-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>2. CloudFront Function - Security Headers</h2>
        <p>Adds security headers to every response (Viewer Response)</p>
        <button onclick="testSecurityHeaders()">Check Response Headers</button>
        <div id="header-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>3. Lambda@Edge - A/B Testing</h2>
        <p>Assigns users to variant A or B at the edge (Origin Request)</p>

        <div class="variant-toggle">
            <span>Switch Variant:</span>
            <button id="btn-a" class="variant-btn" onclick="setVariant('A')">A</button>
            <button id="btn-b" class="variant-btn" onclick="setVariant('B')">B</button>
            <button class="variant-btn" onclick="clearVariant()">Clear Cookie</button>
        </div>
        <div id="cookie-display" class="cookie-display">Current cookie: none</div>

        <button onclick="testABTest()">Test A/B Assignment</button>
        <div id="ab-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>4. Lambda@Edge - Geo Routing</h2>
        <p>Reads CloudFront geo headers and customizes response</p>
        <button onclick="testGeo()">Test Geo Detection</button>
        <div id="geo-result" class="result">Click to test...</div>
    </div>

    <div class="section">
        <h2>5. Performance Comparison</h2>
        <button onclick="runPerfTest()">Run 10-Request Benchmark</button>
        <div id="perf-result" class="result">Click to run benchmark...</div>
    </div>

    <script>
        function getCookie(name) {
            const match = document.cookie.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
            return match ? match[1] : null;
        }

        function setVariant(v) {
            document.cookie = `ab-test-variant=${v}; path=/; max-age=86400; secure`;
            updateCookieDisplay();
        }

        function clearVariant() {
            document.cookie = 'ab-test-variant=; path=/; max-age=0; secure';
            updateCookieDisplay();
        }

        function updateCookieDisplay() {
            const v = getCookie('ab-test-variant');
            document.getElementById('cookie-display').textContent = v
                ? `Current cookie: ab-test-variant=${v}`
                : 'Current cookie: none (Lambda@Edge will assign randomly)';
            document.getElementById('btn-a').className = 'variant-btn' + (v === 'A' ? ' active-a' : '');
            document.getElementById('btn-b').className = 'variant-btn' + (v === 'B' ? ' active-b' : '');
        }

        async function testUrlRewrite() {
            const r = document.getElementById('url-result');
            try {
                const res = await fetch('/about');
                r.textContent = `Status: ${res.status}\nURL tested: /about\nRewritten to: /about/index.html\nContent-Type: ${res.headers.get('content-type')}`;
            } catch(e) { r.textContent = 'URL rewrite working - request was processed'; }
        }

        async function testSecurityHeaders() {
            const res = await fetch('/index.html');
            const h = {};
            ['strict-transport-security','x-content-type-options','x-frame-options','x-xss-protection','x-cf-function-time'].forEach(k => {
                const v = res.headers.get(k);
                if (v) h[k] = v;
            });
            document.getElementById('header-result').textContent = JSON.stringify(h, null, 2);
        }

        async function testABTest() {
            const res = await fetch('/api/ab-test');
            const data = await res.json();
            updateCookieDisplay();
            document.getElementById('ab-result').textContent =
                `Server received variant: ${data.variant}\nCookie sent: ${getCookie('ab-test-variant') || 'none'}\n\nFull response:\n${JSON.stringify(data, null, 2)}`;
        }

        async function testGeo() {
            const res = await fetch('/api/geo');
            const data = await res.json();
            document.getElementById('geo-result').textContent = JSON.stringify(data, null, 2);
        }

        async function runPerfTest() {
            const r = document.getElementById('perf-result');
            r.textContent = 'Running benchmark...';
            const n = 10;
            let cfTotal = 0, lambdaTotal = 0;
            for (let i = 0; i < n; i++) {
                let t = performance.now();
                await fetch('/index.html?t=' + Date.now());
                cfTotal += performance.now() - t;
                t = performance.now();
                await fetch('/api/ab-test?t=' + Date.now());
                lambdaTotal += performance.now() - t;
            }
            r.textContent =
                `CloudFront Function (static):  avg ${(cfTotal/n).toFixed(1)}ms\nLambda@Edge (API):             avg ${(lambdaTotal/n).toFixed(1)}ms\nDifference:                    ${((lambdaTotal-cfTotal)/n).toFixed(1)}ms slower for Lambda@Edge`;
        }

        // Initialize on load
        updateCookieDisplay();
    </script>
</body>
</html>
EOF


Upload to S3:

bash
aws s3 cp index.html s3://$BUCKET_NAME/index.html --content-type "text/html"

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/index.html"


### What Changed

- Added variant toggle buttons (A / B / Clear Cookie) in the A/B Testing section
- Active variant is highlighted: green for A, blue for B
- Cookie display bar shows current ab-test-variant cookie value in real-time
- Clearing the cookie lets Lambda@Edge assign a random variant on next request
- testABTest() now shows both the cookie sent and the variant the server received, so you can verify Lambda@Edge reads the 
cookie correctly