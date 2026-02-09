## Updated Architecture with AWS Amplify

User → CloudFront → ALB → EC2 (Auto Scaling) → RDS PostgreSQL
                  ↓
                  S3 (Images)
                  
Frontend: AWS Amplify (Auth, Storage)
Authentication: Cognito User Pool
Authorization: Cognito Identity Pool → S3 permissions


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Step-by-Step Implementation

### Step 1: Create Cognito User Pool (Authentication)

bash
# Create User Pool
aws cognito-idp create-user-pool \
  --pool-name image-app-users \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 8,
      "RequireUppercase": true,
      "RequireLowercase": true,
      "RequireNumbers": true,
      "RequireSymbols": false
    }
  }' \
  --auto-verified-attributes email \
  --username-attributes email \
  --mfa-configuration OFF

USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 10 \
  --query 'UserPools[?Name==`image-app-users`].Id' --output text)

# Create User Pool Client
aws cognito-idp create-user-pool-client \
  --user-pool-id $USER_POOL_ID \
  --client-name web-client \
  --no-generate-secret \
  --explicit-auth-flows \
    ALLOW_USER_PASSWORD_AUTH \
    ALLOW_REFRESH_TOKEN_AUTH \
  --read-attributes email name \
  --write-attributes email name

CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
  --user-pool-id $USER_POOL_ID \
  --query 'UserPoolClients[0].ClientId' --output text)

echo "User Pool ID: $USER_POOL_ID"
echo "Client ID: $CLIENT_ID"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: Create Cognito Identity Pool (Authorization)

bash
# Create Identity Pool
aws cognito-identity create-identity-pool \
  --identity-pool-name image_app_identity \
  --allow-unauthenticated-identities \
  --cognito-identity-providers \
    ProviderName=cognito-idp.us-east-1.amazonaws.com/$USER_POOL_ID,ClientId=$CLIENT_ID

IDENTITY_POOL_ID=$(aws cognito-identity list-identity-pools --max-results 10 \
  --query 'IdentityPools[?IdentityPoolName==`image_app_identity`].IdentityPoolId' --output text)

echo "Identity Pool ID: $IDENTITY_POOL_ID"


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 3: Create IAM Roles for Cognito Identity Pool

#### Unauthenticated Role (Guest - Read Only)

bash
# Create trust policy
cat > unauth-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "$IDENTITY_POOL_ID"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "unauthenticated"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name Cognito_ImageApp_Unauth_Role \
  --assume-role-policy-document file://unauth-trust-policy.json

# S3 read-only policy
cat > unauth-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET-NAME",
        "arn:aws:s3:::YOUR-BUCKET-NAME/public/*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name Cognito_ImageApp_Unauth_Role \
  --policy-name S3ReadOnlyPolicy \
  --policy-document file://unauth-policy.json

UNAUTH_ROLE_ARN=$(aws iam get-role --role-name Cognito_ImageApp_Unauth_Role \
  --query 'Role.Arn' --output text)


#### Authenticated Role (Full Access)

bash
# Create trust policy
cat > auth-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "$IDENTITY_POOL_ID"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name Cognito_ImageApp_Auth_Role \
  --assume-role-policy-document file://auth-trust-policy.json

# S3 full access policy with user-specific paths
cat > auth-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET-NAME",
        "arn:aws:s3:::YOUR-BUCKET-NAME/public/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET-NAME/private/\${cognito-identity.amazonaws.com:sub}/*",
        "arn:aws:s3:::YOUR-BUCKET-NAME/protected/\${cognito-identity.amazonaws.com:sub}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET-NAME/protected/*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name Cognito_ImageApp_Auth_Role \
  --policy-name S3FullAccessPolicy \
  --policy-document file://auth-policy.json

AUTH_ROLE_ARN=$(aws iam get-role --role-name Cognito_ImageApp_Auth_Role \
  --query 'Role.Arn' --output text)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 4: Attach Roles to Identity Pool

bash
aws cognito-identity set-identity-pool-roles \
  --identity-pool-id $IDENTITY_POOL_ID \
  --roles authenticated=$AUTH_ROLE_ARN,unauthenticated=$UNAUTH_ROLE_ARN


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 5: Configure S3 Bucket

bash
BUCKET_NAME=your-image-bucket-name

# Create bucket
aws s3 mb s3://$BUCKET_NAME --region us-east-1

# Configure CORS
cat > cors.json <<EOF
{
  "CORSRules": [
    {
      "AllowedOrigins": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag", "x-amz-meta-custom-header"],
      "MaxAgeSeconds": 3000
    }
  ]
}
EOF

aws s3api put-bucket-cors \
  --bucket $BUCKET_NAME \
  --cors-configuration file://cors.json

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,\
    IgnorePublicAcls=true,\
    BlockPublicPolicy=false,\
    RestrictPublicBuckets=false


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 6: Create CloudFront Origin Access Identity (OAI)

bash
# Create OAI
aws cloudfront create-cloud-front-origin-access-identity \
  --cloud-front-origin-access-identity-config \
    CallerReference=$(date +%s),Comment="OAI for image bucket"

OAI_ID=$(aws cloudfront list-cloud-front-origin-access-identities \
  --query 'CloudFrontOriginAccessIdentityList.Items[0].Id' --output text)

# Update S3 bucket policy
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
      "Sid": "AllowCognitoIdentityAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "$AUTH_ROLE_ARN",
          "$UNAUTH_ROLE_ARN"
        ]
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
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


### Step 7: Create CloudFront Distribution

bash
ALB_DNS_NAME=your-alb-dns-name.us-east-1.elb.amazonaws.com

cat > cloudfront-config.json <<EOF
{
  "CallerReference": "$(date +%s)",
  "Comment": "Image app with S3 and ALB",
  "Enabled": true,
  "Origins": {
    "Quantity": 2,
    "Items": [
      {
        "Id": "alb-origin",
        "DomainName": "$ALB_DNS_NAME",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only",
          "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
          }
        }
      },
      {
        "Id": "s3-origin",
        "DomainName": "$BUCKET_NAME.s3.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": "origin-access-identity/cloudfront/$OAI_ID"
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "alb-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": true,
      "Cookies": {"Forward": "all"},
      "Headers": {
        "Quantity": 3,
        "Items": ["Authorization", "Host", "CloudFront-Viewer-Country"]
      }
    },
    "MinTTL": 0,
    "DefaultTTL": 0,
    "MaxTTL": 0,
    "Compress": true
  },
  "CacheBehaviors": {
    "Quantity": 1,
    "Items": [
      {
        "PathPattern": "/images/*",
        "TargetOriginId": "s3-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
          "Quantity": 7,
          "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
          "CachedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"]
          }
        },
        "ForwardedValues": {
          "QueryString": true,
          "Cookies": {"Forward": "none"},
          "Headers": {
            "Quantity": 5,
            "Items": [
              "Authorization",
              "x-amz-date",
              "x-amz-security-token",
              "x-amz-content-sha256",
              "x-amz-user-agent"
            ]
          }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
      }
    ]
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


### Step 8: Backend Application (Node.js/Express)

javascript
// app.js
const express = require('express');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const USER_POOL_ID = 'us-east-1_XXXXXXXXX';
const REGION = 'us-east-1';

// PostgreSQL connection
const pool = new Pool({
  host: process.env.DB_HOST,
  port: 5432,
  database: 'imageapp',
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD
});

// JWKS client
const client = jwksClient({
  jwksUri: `https://cognito-idp.${REGION}.amazonaws.com/${USER_POOL_ID}/.well-known/jwks.json`
});

function getKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    const signingKey = key.publicKey || key.rsaPublicKey;
    callback(null, signingKey);
  });
}

// Verify JWT token
function verifyToken(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  jwt.verify(token, getKey, {
    issuer: `https://cognito-idp.${REGION}.amazonaws.com/${USER_POOL_ID}`,
    algorithms: ['RS256']
  }, (err, decoded) => {
    if (err) {
      return res.status(401).json({ error: 'Invalid token' });
    }
    req.user = decoded;
    next();
  });
}

// Get image metadata (public)
app.get('/api/images', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, key, filename, size, uploaded_at, user_id FROM images ORDER BY uploaded_at DESC'
    );
    res.json({ images: result.rows });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Save image metadata after upload (authenticated)
app.post('/api/images', verifyToken, async (req, res) => {
  try {
    const { key, filename, size } = req.body;
    const userId = req.user.sub;

    const result = await pool.query(
      'INSERT INTO images (key, filename, size, user_id) VALUES ($1, $2, $3, $4) RETURNING *',
      [key, filename, size, userId]
    );

    res.json({ image: result.rows[0] });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete image metadata (authenticated)
app.delete('/api/images/:id', verifyToken, async (req, res) => {
  try {
    const imageId = req.params.id;
    const userId = req.user.sub;

    // Verify ownership
    const checkResult = await pool.query(
      'SELECT * FROM images WHERE id = $1 AND user_id = $2',
      [imageId, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    await pool.query('DELETE FROM images WHERE id = $1', [imageId]);
    res.json({ message: 'Image deleted' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(3000, () => {
  console.log('Server running on port 3000');
});


Database schema:
sql
CREATE TABLE images (
  id SERIAL PRIMARY KEY,
  key VARCHAR(500) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  size INTEGER,
  user_id VARCHAR(255) NOT NULL,
  uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_images_user_id ON images(user_id);


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 9: Frontend with AWS Amplify (React)

#### Install Dependencies

bash
npm install aws-amplify @aws-amplify/ui-react


#### Configure Amplify

javascript
// src/aws-exports.js
const awsconfig = {
  Auth: {
    region: 'us-east-1',
    userPoolId: 'us-east-1_XXXXXXXXX',
    userPoolWebClientId: 'YOUR_CLIENT_ID',
    identityPoolId: 'us-east-1:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
    mandatorySignIn: false
  },
  Storage: {
    AWSS3: {
      bucket: 'your-image-bucket-name',
      region: 'us-east-1',
      customPrefix: {
        public: 'public/',
        protected: 'protected/',
        private: 'private/'
      }
    }
  },
  API: {
    endpoints: [
      {
        name: 'imageAPI',
        endpoint: 'https://YOUR_CLOUDFRONT_DOMAIN',
        custom_header: async () => {
          const session = await Auth.currentSession();
          return {
            Authorization: `Bearer ${session.getIdToken().getJwtToken()}`
          };
        }
      }
    ]
  }
};

export default awsconfig;


#### Main App Component

javascript
// src/App.js
import React, { useState, useEffect } from 'react';
import { Amplify, Auth, Storage, API } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';
import awsconfig from './aws-exports';

Amplify.configure(awsconfig);

// Configure Storage to use CloudFront
Storage.configure({
  customPrefix: {
    public: 'public/',
    protected: 'protected/',
    private: 'private/'
  },
  // Use CloudFront for downloads
  download: {
    level: 'public',
    customPrefix: {
      public: 'images/public/',
      protected: 'images/protected/',
      private: 'images/private/'
    }
  }
});

function App() {
  const [images, setImages] = useState([]);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    loadImages();
  }, []);

  const loadImages = async () => {
    try {
      // Get metadata from backend
      const response = await fetch(`${awsconfig.API.endpoints[0].endpoint}/api/images`);
      const data = await response.json();
      
      // Get signed URLs from S3 via CloudFront
      const imagesWithUrls = await Promise.all(
        data.images.map(async (img) => {
          try {
            // Determine access level from key
            let level = 'public';
            let key = img.key;
            
            if (key.startsWith('private/')) {
              level = 'private';
              key = key.replace('private/', '');
            } else if (key.startsWith('protected/')) {
              level = 'protected';
              key = key.replace('protected/', '');
            } else if (key.startsWith('public/')) {
              key = key.replace('public/', '');
            }

            const url = await Storage.get(key, { level, download: false });
            return { ...img, url };
          } catch (err) {
            console.error('Error getting URL:', err);
            return { ...img, url: null };
          }
        })
      );

      setImages(imagesWithUrls);
    } catch (error) {
      console.error('Failed to load images:', error);
    }
  };

  const uploadImage = async (file) => {
    setUploading(true);
    try {
      const user = await Auth.currentAuthenticatedUser();
      
      // Upload to S3 via Amplify Storage (goes through CloudFront)
      const result = await Storage.put(file.name, file, {
        level: 'private', // private/userId/filename
        contentType: file.type,
        progressCallback(progress) {
          console.log(`Uploaded: ${progress.loaded}/${progress.total}`);
        }
      });

      // Save metadata to backend
      const session = await Auth.currentSession();
      const token = session.getIdToken().getJwtToken();

      await fetch(`${awsconfig.API.endpoints[0].endpoint}/api/images`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({
          key: result.key,
          filename: file.name,
          size: file.size
        })
      });

      alert('Upload successful!');
      loadImages();
    } catch (error) {
      console.error('Upload failed:', error);
      alert('Upload failed: ' + error.message);
    } finally {
      setUploading(false);
    }
  };

  const deleteImage = async (image) => {
    try {
      const session = await Auth.currentSession();
      const token = session.getIdToken().getJwtToken();

      // Delete from backend
      await fetch(`${awsconfig.API.endpoints[0].endpoint}/api/images/${image.id}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`
        }
      });

      // Delete from S3
      let key = image.key;
      let level = 'public';
      
      if (key.startsWith('private/')) {
        level = 'private';
        key = key.replace(/^private\/[^/]+\//, '');
      } else if (key.startsWith('protected/')) {
        level = 'protected';
        key = key.replace(/^protected\/[^/]+\//, '');
      } else if (key.startsWith('public/')) {
        key = key.replace('public/', '');
      }

      await Storage.remove(key, { level });

      alert('Delete successful!');
      loadImages();
    } catch (error) {
      console.error('Delete failed:', error);
      alert('Delete failed: ' + error.message);
    }
  };

  return (
    <Authenticator>
      {({ signOut, user }) => (
        <div className="App" style={{ padding: '20px' }}>
          <header>
            <h1>Image Gallery</h1>
            {user && (
              <div>
                <p>Welcome, {user.attributes.email}</p>
                <button onClick={signOut}>Sign Out</button>
              </div>
            )}
          </header>

          {user && (
            <div style={{ margin: '20px 0' }}>
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
              {uploading && <span> Uploading...</span>}
            </div>
          )}

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: '20px' }}>
            {images.map((image) => (
              <div key={image.id} style={{ border: '1px solid #ccc', padding: '10px' }}>
                {image.url ? (
                  <img
                    src={image.url}
                    alt={image.filename}
                    style={{ width: '100%', height: '200px', objectFit: 'cover' }}
                  />
                ) : (
                  <div style={{ width: '100%', height: '200px', background: '#f0f0f0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    No access
                  </div>
                )}
                <p><strong>{image.filename}</strong></p>
                <p>Size: {(image.size / 1024).toFixed(2)} KB</p>
                <p>Uploaded: {new Date(image.uploaded_at).toLocaleDateString()}</p>
                {user && user.attributes.sub === image.user_id && (
                  <button onClick={() => deleteImage(image)}>Delete</button>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </Authenticator>
  );
}

export default App;


#### Guest Access Component (Optional)

javascript
// src/GuestGallery.js
import React, { useState, useEffect } from 'react';
import { Storage } from 'aws-amplify';

function GuestGallery() {
  const [images, setImages] = useState([]);

  useEffect(() => {
    loadPublicImages();
  }, []);

  const loadPublicImages = async () => {
    try {
      // List public images
      const result = await Storage.list('', { level: 'public' });
      
      // Get URLs
      const imagesWithUrls = await Promise.all(
        result.results.map(async (item) => {
          const url = await Storage.get(item.key, { level: 'public' });
          return { key: item.key, url };
        })
      );

      setImages(imagesWithUrls);
    } catch (error) {
      console.error('Failed to load images:', error);
    }
  };

  return (
    <div style={{ padding: '20px' }}>
      <h2>Public Gallery (Guest Access)</h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: '20px' }}>
        {images.map((image) => (
          <div key={image.key}>
            <img
              src={image.url}
              alt={image.key}
              style={{ width: '100%', height: '200px', objectFit: 'cover' }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

export default GuestGallery;


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 10: Configure Amplify Storage to Use CloudFront

Option 1: Custom Storage Provider

javascript
// src/customStorage.js
import { Storage } from 'aws-amplify';

const CLOUDFRONT_DOMAIN = 'https://d1234567890.cloudfront.net';

export const uploadToCloudFront = async (file, options = {}) => {
  // Upload via Amplify (uses S3 directly)
  const result = await Storage.put(file.name, file, {
    level: options.level || 'private',
    contentType: file.type,
    ...options
  });

  return result;
};

export const getFromCloudFront = async (key, options = {}) => {
  // Get signed URL that routes through CloudFront
  const url = await Storage.get(key, {
    level: options.level || 'public',
    download: false,
    ...options
  });

  // Replace S3 URL with CloudFront URL
  const s3Url = new URL(url);
  const cloudFrontUrl = `${CLOUDFRONT_DOMAIN}${s3Url.pathname}${s3Url.search}`;
  
  return cloudFrontUrl;
};

export const deleteFromStorage = async (key, options = {}) => {
  return await Storage.remove(key, {
    level: options.level || 'private',
    ...options
  });
};


Option 2: Configure CloudFront as Custom Endpoint

javascript
// src/aws-exports.js
const awsconfig = {
  Auth: {
    region: 'us-east-1',
    userPoolId: 'us-east-1_XXXXXXXXX',
    userPoolWebClientId: 'YOUR_CLIENT_ID',
    identityPoolId: 'us-east-1:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX'
  },
  Storage: {
    AWSS3: {
      bucket: 'your-image-bucket-name',
      region: 'us-east-1',
      customPrefix: {
        public: 'public/',
        protected: 'protected/',
        private: 'private/'
      }
    }
  }
};

// Override Storage get method to use CloudFront
import { Storage } from 'aws-amplify';

const originalGet = Storage.get.bind(Storage);
Storage.get = async (key, options) => {
  const url = await originalGet(key, options);
  
  // Replace S3 domain with CloudFront domain
  const CLOUDFRONT_DOMAIN = 'd1234567890.clou