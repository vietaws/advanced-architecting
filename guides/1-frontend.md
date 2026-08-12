# Frontend


---

Deploy the static SPA to S3 + CloudFront. You can do this **before any backend exists** — the dashboard shows all resources as **Disconnected** (red) without making any network calls until services are online.

---

## Configure API endpoint

Edit `frontend/config.js`:

```js
window.APP_CONFIG = {
  // Leave empty for frontend-only deploy (all resources show Disconnected).
  // Set to your ALB DNS once the backend is deployed.
  // If ALB is access via HTTP, ensure cloudfront distribution allow to access via HTTP Only
  API_URL: '',
};
```
---

## Upload and create CloudFront distribution

```bash
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --delete

aws cloudfront create-distribution \
  --origin-domain-name "${FRONTEND_BUCKET}.s3.ap-southeast-1.amazonaws.com" \
  --default-root-object index.html
```

---
