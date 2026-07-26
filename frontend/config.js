// =============================================================================
// config.js — Frontend configuration
//
// This is the ONLY file you need to edit when deploying the frontend to S3/CloudFront.
//
// How to deploy:
//   1. Set API_URL to your ALB DNS name or custom domain:
//        https://api.yourdomain.com          (custom domain via Route 53 + ACM)
//        https://xxx.ap-southeast-1.elb.amazonaws.com  (raw ALB DNS)
//
//   2. Upload all files in this folder to your S3 bucket:
//        aws s3 sync frontend/ s3://YOUR_BUCKET_NAME --delete
//
//   3. Invalidate CloudFront cache after each deploy:
//        aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
//
// For local development against the monolith:
//   Set API_URL = '' (empty string) to fall back to window.location.origin
// =============================================================================

window.APP_CONFIG = {
  // ALB endpoint for the EKS microservices backend.
  // No trailing slash.
  API_URL: 'https://api.yourdomain.com',
};
