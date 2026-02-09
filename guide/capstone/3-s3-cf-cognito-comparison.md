## Best Solution: S3 Transfer Acceleration + Cognito + CloudFront

### Recommended Architecture

Global Users
     ↓
Upload: S3 Transfer Acceleration (authenticated via Cognito)
Download: CloudFront (cached, authenticated via signed URLs/cookies)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Comparison of Solutions

| Solution | Upload Speed | Download Speed | Cost | Complexity | Security |
|----------|-------------|----------------|------|------------|----------|
| S3 Transfer Acceleration + CloudFront | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | $$$ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| S3 Direct + CloudFront | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | $$ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| CloudFront for both | ⭐⭐ | ⭐⭐⭐⭐⭐ | $$$ | ⭐⭐ | ⭐⭐⭐⭐ |
| S3 Multi-Region + CloudFront | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | $$$$ | ⭐ | ⭐⭐⭐⭐⭐ |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Recommended Solution: S3 Transfer Acceleration + CloudFront

### Architecture

┌─────────────────────────────────────────────────────────┐
│ Global Users                                             │
└─────────────────────────────────────────────────────────┘
                    ↓                    ↓
            UPLOAD (PUT)          DOWNLOAD (GET)
                    ↓                    ↓
┌──────────────────────────┐  ┌──────────────────────────┐
│ S3 Transfer Acceleration │  │ CloudFront Distribution  │
│ - Nearest edge location  │  │ - Global edge caching    │
│ - AWS backbone network   │  │ - Low latency            │
│ - Cognito auth (SigV4)   │  │ - Signed URLs/cookies    │
└──────────────────────────┘  └──────────────────────────┘
                    ↓                    ↓
            ┌────────────────────────────────┐
            │ S3 Bucket (Single Region)      │
            │ - us-east-1                    │
            │ - Cognito IAM permissions      │
            └────────────────────────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation

### Step 1: Enable S3 Transfer Acceleration

bash
BUCKET_NAME=your-image-bucket

# Enable Transfer Acceleration
aws s3api put-bucket-accelerate-configuration \
  --bucket $BUCKET_NAME \
  --accelerate-configuration Status=Enabled

# Get Transfer Acceleration endpoint
echo "Upload endpoint: $BUCKET_NAME.s3-accelerate.amazonaws.com"


Cost: 
- $0.04 per GB for uploads over Transfer Acceleration
- Only charged when faster than regular S3 (automatic)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Configure Amplify with Transfer Acceleration

javascript
// src/aws-exports.js
import { Amplify } from 'aws-amplify';

const config = {
  Auth: {
    region: 'us-east-1',
    userPoolId: 'us-east-1_XXXXXXXXX',
    userPoolWebClientId: 'YOUR_CLIENT_ID',
    identityPoolId: 'us-east-1:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
  },
  Storage: {
    AWSS3: {
      bucket: 'your-image-bucket',
      region: 'us-east-1',
      customPrefix: {
        public: 'public/',
        protected: 'protected/',
        private: 'private/'
      }
    }
  }
};

Amplify.configure(config);

// Enable Transfer Acceleration for uploads
import { Storage } from 'aws-amplify';
Storage.configure({
  AWSS3: {
    ...config.Storage.AWSS3,
    dangerouslyConnectToHttpEndpointForTesting: false,
    useAccelerateEndpoint: true // Enable Transfer Acceleration
  }
});

export default config;


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Upload with Transfer Acceleration

javascript
// src/uploadImage.js
import { Storage, Auth } from 'aws-amplify';

export const uploadImage = async (file, options = {}) => {
  try {
    // Ensure user is authenticated
    const user = await Auth.currentAuthenticatedUser();
    
    // Upload via Transfer Acceleration
    const result = await Storage.put(file.name, file, {
      level: options.level || 'private',
      contentType: file.type,
      progressCallback(progress) {
        const percentage = (progress.loaded / progress.total) * 100;
        console.log(`Upload progress: ${percentage.toFixed(2)}%`);
        if (options.onProgress) {
          options.onProgress(percentage);
        }
      }
    });

    console.log('Upload successful:', result);
    return result;
  } catch (error) {
    console.error('Upload failed:', error);
    throw error;
  }
};

// Usage
const file = document.getElementById('fileInput').files[0];
await uploadImage(file, {
  level: 'private',
  onProgress: (percent) => console.log(`${percent}%`)
});


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 4: Create CloudFront Distribution for Downloads

bash
# Create CloudFront OAI
aws cloudfront create-cloud-front-origin-access-identity \
  --cloud-front-origin-access-identity-config \
    CallerReference=$(date +%s),Comment="OAI for image bucket"

OAI_ID=$(aws cloudfront list-cloud-front-origin-access-identities \
  --query 'CloudFrontOriginAccessIdentityList.Items[0].Id' --output text)

# Create CloudFront distribution
cat > cloudfront-config.json <<EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "Global image delivery",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "s3-origin",
        "DomainName": "$BUCKET_NAME.s3.us-east-1.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": "origin-access-identity/cloudfront/$OAI_ID"
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": true,
      "Cookies": {"Forward": "none"}
    },
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    },
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000,
    "Compress": true
  }
}
EOF

aws cloudfront create-distribution \
  --distribution-config file://cloudfront-config.json

DISTRIBUTION_ID=$(aws cloudfront list-distributions \
  --query 'DistributionList.Items[0].Id' --output text)

CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.DomainName' --output text)

echo "CloudFront Domain: https://$CLOUDFRONT_DOMAIN"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 5: Update S3 Bucket Policy

bash
cat > bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontOAI",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity $OAI_ID"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    },
    {
      "Sid": "AllowCognitoAuthenticatedUpload",
      "Effect": "Allow",
      "Principal": {
        "AWS": "$AUTH_ROLE_ARN"
      },
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/private/\${cognito-identity.amazonaws.com:sub}/*"
    },
    {
      "Sid": "AllowCognitoAuthenticatedRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "$AUTH_ROLE_ARN",
          "$UNAUTH_ROLE_ARN"
        ]
      },
      "Action": "s3:GetObject",
      "Resource": [
        "arn:aws:s3:::$BUCKET_NAME/public/*",
        "arn:aws:s3:::$BUCKET_NAME/private/\${cognito-identity.amazonaws.com:sub}/*"
      ]
    },
    {
      "Sid": "AllowCognitoListBucket",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "$AUTH_ROLE_ARN",
          "$UNAUTH_ROLE_ARN"
        ]
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file://bucket-policy.json


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 6: Download via CloudFront with Authentication

#### Option A: Use Amplify Storage (Automatic)

javascript
// src/downloadImage.js
import { Storage } from 'aws-amplify';

export const getImageUrl = async (key, options = {}) => {
  try {
    // Get signed URL (automatically uses CloudFront if configured)
    const url = await Storage.get(key, {
      level: options.level || 'private',
      expires: options.expires || 3600, // 1 hour
      download: false
    });

    return url;
  } catch (error) {
    console.error('Failed to get image URL:', error);
    throw error;
  }
};

// Usage
const imageUrl = await getImageUrl('photo.jpg', { level: 'private' });


#### Option B: CloudFront Signed URLs (Backend)

javascript
// backend/generateSignedUrl.js
const AWS = require('aws-sdk');
const jwt = require('jsonwebtoken');

const CLOUDFRONT_DOMAIN = 'd1234567890.cloudfront.net';
const CLOUDFRONT_KEY_PAIR_ID = 'APKAXXXXXXXXXX';
const CLOUDFRONT_PRIVATE_KEY = `-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----`;

// Generate CloudFront signed URL
const generateSignedUrl = (key, expiresIn = 3600) => {
  const cloudfront = new AWS.CloudFront.Signer(
    CLOUDFRONT_KEY_PAIR_ID,
    CLOUDFRONT_PRIVATE_KEY
  );

  const url = `https://${CLOUDFRONT_DOMAIN}/${key}`;
  const expires = Math.floor(Date.now() / 1000) + expiresIn;

  return cloudfront.getSignedUrl({
    url: url,
    expires: expires
  });
};

// Express endpoint
app.get('/api/images/:key', verifyToken, async (req, res) => {
  try {
    const key = req.params.key;
    const userId = req.user.sub;

    // Verify user owns the image
    if (!key.startsWith(`private/${userId}/`)) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    // Generate signed CloudFront URL
    const signedUrl = generateSignedUrl(key, 3600);

    res.json({ url: signedUrl });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 7: Complete React Component

javascript
// src/ImageGallery.js
import React, { useState, useEffect } from 'react';
import { Storage, Auth } from 'aws-amplify';

function ImageGallery() {
  const [images, setImages] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);

  useEffect(() => {
    loadImages();
  }, []);

  const loadImages = async () => {
    try {
      // List user's private images
      const result = await Storage.list('', { level: 'private' });
      
      // Get signed URLs for each image
      const imagesWithUrls = await Promise.all(
        result.results.map(async (item) => {
          const url = await Storage.get(item.key, {
            level: 'private',
            expires: 3600
          });
          return { key: item.key, url, size: item.size };
        })
      );

      setImages(imagesWithUrls);
    } catch (error) {
      console.error('Failed to load images:', error);
    }
  };

  const uploadImage = async (file) => {
    setUploading(true);
    setUploadProgress(0);

    try {
      // Upload via S3 Transfer Acceleration
      const result = await Storage.put(file.name, file, {
        level: 'private',
        contentType: file.type,
        progressCallback(progress) {
          const percent = (progress.loaded / progress.total) * 100;
          setUploadProgress(percent);
        }
      });

      console.log('Upload successful:', result);
      alert('Upload successful!');
      loadImages();
    } catch (error) {
      console.error('Upload failed:', error);
      alert('Upload failed: ' + error.message);
    } finally {
      setUploading(false);
      setUploadProgress(0);
    }
  };

  const deleteImage = async (key) => {
    try {
      await Storage.remove(key, { level: 'private' });
      alert('Delete successful!');
      loadImages();
    } catch (error) {
      console.error('Delete failed:', error);
      alert('Delete failed: ' + error.message);
    }
  };

  return (
    <div style={{ padding: '20px' }}>
      <h1>Image Gallery</h1>

      {/* Upload */}
      <div style={{ marginBottom: '20px' }}>
        <input
          type="file"
          accept="image/*"
          onChange={(e) => {
            if (e.target.files[0]) {
              uploadImage(e.target.files[0]);
            }
          }}
          disabled={uploading}
        />
        {uploading && (
          <div>
            <progress value={uploadProgress} max="100" />
            <span> {uploadProgress.toFixed(0)}%</span>
          </div>
        )}
      </div>

      {/* Image Grid */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))',
        gap: '20px'
      }}>
        {images.map((image) => (
          <div key={image.key} style={{ border: '1px solid #ccc', padding: '10px' }}>
            <img
              src={image.url}
              alt={image.key}
              style={{ width: '100%', height: '200px', objectFit: 'cover' }}
            />
            <p><strong>{image.key}</strong></p>
            <p>Size: {(image.size / 1024).toFixed(2)} KB</p>
            <button onClick={() => deleteImage(image.key)}>Delete</button>
          </div>
        ))}
      </div>
    </div>
  );
}

export default ImageGallery;


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Cost Comparison (1TB data, 10M requests/month)

### Option 1: S3 Transfer Acceleration + CloudFront (Recommended)

Upload (100GB):
- S3 Transfer Acceleration: 100GB × $0.04 = $4.00
- S3 PUT requests: 1M × $0.005/1000 = $5.00

Download (900GB):
- CloudFront data transfer: 900GB × $0.085 = $76.50
- CloudFront requests: 9M × $0.0075/10K = $6.75
- S3 storage: 1TB × $0.023 = $23.00

Total: $115.25/month


### Option 2: S3 Direct + CloudFront

Upload (100GB):
- S3 PUT requests: 1M × $0.005/1000 = $5.00
- S3 data transfer: $0 (inbound free)

Download (900GB):
- CloudFront data transfer: 900GB × $0.085 = $76.50
- CloudFront requests: 9M × $0.0075/10K = $6.75
- S3 storage: 1TB × $0.023 = $23.00

Total: $111.25/month

Savings: $4/month
Trade-off: Slower uploads from distant regions


### Option 3: S3 Multi-Region Replication + CloudFront

Upload (100GB):
- S3 PUT requests: 1M × $0.005/1000 = $5.00
- S3 replication: 100GB × $0.02 = $2.00

Download (900GB):
- CloudFront data transfer: 900GB × $0.085 = $76.50
- CloudFront requests: 9M × $0.0075/10K = $6.75
- S3 storage (3 regions): 3TB × $0.023 = $69.00

Total: $159.25/month

Extra cost: $44/month
Benefit: Fastest uploads and downloads globally


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Performance Comparison

### Upload Speed (from Tokyo to us-east-1)

| Solution | Latency | Speed |
|----------|---------|-------|
| S3 Transfer Acceleration | 50-80ms | 50-100 MB/s |
| S3 Direct | 150-200ms | 10-20 MB/s |
| S3 Multi-Region (ap-northeast-1) | 10-20ms | 100-200 MB/s |

### Download Speed (from Tokyo)

| Solution | Latency | Speed |
|----------|---------|-------|
| CloudFront | 10-30ms | 100-200 MB/s |
| S3 Direct (us-east-1) | 150-200ms | 10-20 MB/s |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Final Recommendation

### Best Solution: S3 Transfer Acceleration + CloudFront

Why?
✅ Fast uploads globally (50-80ms latency vs 150-200ms)
✅ Fast downloads globally (CloudFront edge caching)
✅ Simple architecture (single S3 bucket)
✅ Cost-effective ($4/month extra for Transfer Acceleration)
✅ Easy implementation (just enable Transfer Acceleration)
✅ Automatic authentication (Cognito Identity Pool)
✅ Secure (IAM permissions, signed URLs)

When to use alternatives:
- **Budget-constrained:** Use S3 Direct + CloudFront (save $4/month)
- **Mission-critical performance:** Use S3 Multi-Region + CloudFront (extra $44/month)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Implementation Summary

javascript
// 1. Configure Amplify with Transfer Acceleration
Storage.configure({
  AWSS3: {
    bucket: 'your-bucket',
    region: 'us-east-1',
    useAccelerateEndpoint: true // Enable Transfer Acceleration
  }
});

// 2. Upload (via Transfer Acceleration)
await Storage.put(file.name, file, {
  level: 'private',
  contentType: file.type
});

// 3. Download (via CloudFront)
const url = await Storage.get(key, {
  level: 'private',
  expires: 3600
});

// Done! Amplify handles:
// - Cognito authentication
// - AWS credential exchange
// - Request signing
// - Transfer Acceleration routing
// - CloudFront URL generation


Total implementation time: 30 minutes
Lines of code: ~50
Complexity: Low
Performance: Excellent
Cost: Reasonable