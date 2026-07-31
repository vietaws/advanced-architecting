// =============================================================================
// config.js — Frontend configuration
//
// This is the ONLY file you need to edit when deploying the frontend.
//
// ── Frontend-first deployment ────────────────────────────────────────────────
// You can deploy the frontend to S3 + CloudFront BEFORE any backend service
// is running. When API_URL is empty, the dashboard shows all services as
// "Disconnected" without making any network calls.
//
// Once you deploy a backend service, set API_URL to its ALB endpoint and
// re-upload this file. The dashboard will immediately start reflecting the
// real status of each service's AWS resources.
//
// ── Steps ────────────────────────────────────────────────────────────────────
// Step 1 — Frontend only (no backend yet):
//   Leave API_URL as empty string ''. Deploy to S3. Done.
//
// Step 2 — Backend deployed:
//   Set API_URL to your ALB DNS name or custom domain:
//     https://api.yourdomain.com                          (Route 53 + ACM)
//     https://xxx.ap-southeast-1.elb.amazonaws.com        (raw ALB DNS)
//   Re-upload this file and invalidate CloudFront cache:
//     aws s3 cp frontend/config.js s3://YOUR_BUCKET_NAME/config.js
//     aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/config.js"
//
// No trailing slash on API_URL.
// =============================================================================

window.APP_CONFIG = {
  // Set to your ALB endpoint once the backend is deployed.
  // Leave empty to run frontend-only (all services show as Disconnected).
  API_URL: 'http://k8s-app-39f644cd8a-2098895631.ap-southeast-1.elb.amazonaws.com',
};
