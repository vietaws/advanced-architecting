# Phase 6 — Frontend

> ← [Back to main guide](../README.md#deployment-workflow)

---

Deploy the static SPA to S3 + CloudFront. You can do this **before any backend exists** — the dashboard shows all resources as **Disconnected** (red) without making any network calls until services are online.

---

## Configure API endpoint

Edit `frontend/config.js`:

```js
window.APP_CONFIG = {
  // Leave empty for frontend-only deploy (all resources show Disconnected).
  // Set to your ALB DNS once the backend is deployed.
  API_URL: '',
};
```

---

## Create S3 bucket

```bash
FRONTEND_BUCKET="demo-frontend-$(openssl rand -hex 4)"

aws s3api create-bucket \
  --bucket "$FRONTEND_BUCKET" \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

# Block public access — CloudFront OAC serves the files
aws s3api put-public-access-block \
  --bucket "$FRONTEND_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

## Upload and create CloudFront distribution

```bash
aws s3 sync frontend/ s3://$FRONTEND_BUCKET --delete

aws cloudfront create-distribution \
  --origin-domain-name "${FRONTEND_BUCKET}.s3.ap-southeast-1.amazonaws.com" \
  --default-root-object index.html
```

Use **Origin Access Control (OAC)** so CloudFront can read the private S3 bucket.

---

## Activate backend (after Phase 5)

```bash
# Get ALB DNS
ALB=$(kubectl get ingress app-ingress -n app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update config.js with ALB endpoint, re-upload, invalidate cache
vi frontend/config.js
aws s3 cp frontend/config.js s3://$FRONTEND_BUCKET/config.js
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/config.js"
```

---

## Dashboard behaviour

| State | API_URL | Dashboard |
|---|---|---|
| Frontend only | `''` (empty) | All resources show **Disconnected** — no network calls |
| Backend deployed | ALB endpoint | Calls `GET /health/status` per service on load and ↻ Refresh |

| Card | Resources checked |
|---|---|
| Product Service | DynamoDB, DAX, S3 |
| Provider Service | Aurora (RDS), EFS |
| Order Service | SQS |

---

→ Next: [Phase 0 — AWS Resources](phase-0-aws-resources.md) *(start backend provisioning)*
