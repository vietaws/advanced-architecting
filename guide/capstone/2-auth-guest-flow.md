## Authentication & Authorization Workflow Summary

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Guest User (Unauthenticated) Flow

### 1. Initial Access

User opens app (not signed in)
         ↓
Amplify detects no authenticated session
         ↓
Request temporary AWS credentials from Cognito Identity Pool
         ↓
Cognito Identity Pool returns credentials with Unauthenticated Role
         ↓
User gets limited permissions (read-only S3 access)


### 2. View Images Workflow

┌─────────────────────────────────────────────────────────┐
│ Guest User                                               │
└─────────────────────────────────────────────────────────┘
                          ↓
         1. Open app (no sign in)
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Amplify Auth                                             │
│ - No user session found                                  │
│ - Request unauthenticated credentials                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Cognito Identity Pool                                    │
│ - Issue temporary credentials                            │
│ - Attach Unauthenticated Role                            │
│ - Credentials valid for 1 hour                           │
└─────────────────────────────────────────────────────────┘
                          ↓
         2. List public images
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Amplify Storage.list('', { level: 'public' })           │
│ - Uses temporary credentials                             │
│ - Signs request with SigV4                               │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ CloudFront                                               │
│ - Receives signed request                                │
│ - Routes to S3 origin                                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ S3 Bucket                                                │
│ - Validates IAM credentials                              │
│ - Checks bucket policy                                   │
│ - Allows: s3:ListBucket on public/*                     │
│ - Returns list of objects                                │
└─────────────────────────────────────────────────────────┘
                          ↓
         3. Get image URL
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Amplify Storage.get('image.jpg', { level: 'public' })   │
│ - Generates signed URL (valid 15 min)                    │
│ - URL includes: AWSAccessKeyId, Signature, Expires      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Browser loads image from signed URL                      │
│ https://d123.cloudfront.net/public/image.jpg?           │
│   X-Amz-Algorithm=AWS4-HMAC-SHA256&                     │
│   X-Amz-Credential=...&                                  │
│   X-Amz-Signature=...                                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ CloudFront → S3                                          │
│ - Validates signature                                    │
│ - Returns image (cached at edge)                         │
└─────────────────────────────────────────────────────────┘


### Guest Permissions (IAM Role)

json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::bucket-name",
    "arn:aws:s3:::bucket-name/public/*"
  ]
}


What guests CAN do:
- ✅ View public images
- ✅ List public images
- ✅ Get signed URLs for public images

What guests CANNOT do:
- ❌ Upload images
- ❌ Delete images
- ❌ Access private/protected images
- ❌ Call authenticated API endpoints


## Authentication & Authorization Workflow Summary

### Architecture Overview

User → Amplify Auth → Cognito User Pool → JWT Token
                    ↓
              Cognito Identity Pool → Temporary AWS Credentials
                    ↓
              S3 / CloudFront (with IAM permissions)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Authentication Process (Cognito User Pool)

### Step 1: User Sign Up

User enters email/password
         ↓
Amplify Auth.signUp()
         ↓
Cognito User Pool creates user
         ↓
Verification email sent
         ↓
User confirms email
         ↓
Account activated


Code:
javascript
import { Auth } from 'aws-amplify';

// Sign up
await Auth.signUp({
  username: 'user@example.com',
  password: 'Password123!',
  attributes: {
    email: 'user@example.com'
  }
});

// Confirm email
await Auth.confirmSignUp('user@example.com', '123456');


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Step 2: User Sign In

User enters email/password
         ↓
Amplify Auth.signIn()
         ↓
Cognito User Pool validates credentials
         ↓
Returns JWT tokens:
  - ID Token (identity claims)
  - Access Token (API authorization)
  - Refresh Token (get new tokens)
         ↓
Tokens stored in browser (localStorage/cookies)


Code:
javascript
const user = await Auth.signIn('user@example.com', 'Password123!');

// Tokens automatically stored by Amplify
// Access current session:
const session = await Auth.currentSession();
const idToken = session.getIdToken().getJwtToken();
const accessToken = session.getAccessToken().getJwtToken();


JWT ID Token contains:
json
{
  "sub": "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111",
  "email": "user@example.com",
  "cognito:username": "user@example.com",
  "iss": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXXXXX",
  "exp": 1707456000,
  "iat": 1707452400
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Authorization Process (Cognito Identity Pool)

### Step 3: Exchange JWT for AWS Credentials

User authenticated (has JWT token)
         ↓
Amplify automatically calls Cognito Identity Pool
         ↓
Identity Pool validates JWT token
         ↓
Assumes IAM role (authenticated role)
         ↓
Returns temporary AWS credentials:
  - Access Key ID
  - Secret Access Key
  - Session Token
  - Expiration (1 hour)
         ↓
Credentials used for AWS service access (S3, DynamoDB, etc.)


Automatic process (handled by Amplify):
javascript
// When you call Storage.put(), Amplify automatically:
// 1. Gets current JWT token
// 2. Exchanges it for AWS credentials via Identity Pool
// 3. Signs S3 request with credentials
// 4. Uploads file

await Storage.put('photo.jpg', file, { level: 'private' });


Manual credential access:
javascript
import { Auth } from 'aws-amplify';

const credentials = await Auth.currentCredentials();
console.log(credentials);
// {
//   accessKeyId: 'ASIA...',
//   secretAccessKey: '...',
//   sessionToken: '...',
//   expiration: Date
// }


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Workflow: Upload Image

### Authenticated User Upload

┌─────────────────────────────────────────────────────────┐
│ Step 1: User Signs In                                    │
└─────────────────────────────────────────────────────────┘
User → Amplify Auth.signIn()
         ↓
Cognito User Pool validates
         ↓
Returns JWT tokens (stored in browser)

┌─────────────────────────────────────────────────────────┐
│ Step 2: User Uploads Image                               │
└─────────────────────────────────────────────────────────┘
User selects file → Storage.put('photo.jpg', file)
         ↓
Amplify checks for JWT token (found)
         ↓
Amplify calls Cognito Identity Pool with JWT
         ↓
Identity Pool returns AWS credentials
         ↓
Amplify signs S3 PUT request with credentials
         ↓
Request sent to S3 (via CloudFront if configured)
         ↓
S3 validates IAM permissions from authenticated role
         ↓
File uploaded to: s3://bucket/private/{userId}/photo.jpg
         ↓
Success response returned

┌─────────────────────────────────────────────────────────┐
│ Step 3: Save Metadata to Backend                         │
└─────────────────────────────────────────────────────────┘
Frontend gets JWT ID token
         ↓
POST /api/images with Authorization: Bearer {idToken}
         ↓
Backend validates JWT signature
         ↓
Extracts userId from token (sub claim)
         ↓
Saves metadata to RDS PostgreSQL
         ↓
Returns success


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Workflow: View Images

### Guest User (Unauthenticated)

┌─────────────────────────────────────────────────────────┐
│ Guest Access - Read Only                                 │
└─────────────────────────────────────────────────────────┘
User visits site (not signed in)
         ↓
Amplify detects no JWT token
         ↓
Amplify calls Cognito Identity Pool (unauthenticated)
         ↓
Identity Pool returns AWS credentials with unauthenticated role
         ↓
Storage.list('', { level: 'public' })
         ↓
Amplify signs S3 LIST request with credentials
         ↓
S3 validates IAM permissions (unauthenticated role)
         ↓
Returns list of public images only
         ↓
For each image: Storage.get(key, { level: 'public' })
         ↓
S3 generates signed URL (via CloudFront)
         ↓
Images displayed to guest


IAM Permission Check:
json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::bucket/public/*"
  ]
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


### Authenticated User

┌─────────────────────────────────────────────────────────┐
│ Authenticated Access - Full Access                       │
└─────────────────────────────────────────────────────────┘
User signed in (has JWT token)
         ↓
Amplify calls Cognito Identity Pool with JWT
         ↓
Identity Pool returns AWS credentials with authenticated role
         ↓
Storage.list('', { level: 'private' })
         ↓
Amplify signs S3 LIST request with credentials
         ↓
S3 validates IAM permissions (authenticated role)
         ↓
Returns user's private images: private/{userId}/*
         ↓
For each image: Storage.get(key, { level: 'private' })
         ↓
S3 generates signed URL (via CloudFront)
         ↓
Images displayed to user


IAM Permission Check:
json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
  "Resource": [
    "arn:aws:s3:::bucket/private/${cognito-identity.amazonaws.com:sub}/*"
  ]
}


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Complete Workflow: Delete Image

┌─────────────────────────────────────────────────────────┐
│ Step 1: User Clicks Delete                               │
└─────────────────────────────────────────────────────────┘
User clicks delete button
         ↓
Frontend gets JWT ID token
         ↓
DELETE /api/images/{imageId} with Authorization: Bearer {idToken}

┌─────────────────────────────────────────────────────────┐
│ Step 2: Backend Validates Ownership                      │
└─────────────────────────────────────────────────────────┘
Backend validates JWT signature
         ↓
Extracts userId from token (sub claim)
         ↓
Queries database: SELECT * WHERE id={imageId} AND user_id={userId}
         ↓
If not found → 403 Forbidden
If found → Continue

┌─────────────────────────────────────────────────────────┐
│ Step 3: Delete from Database                             │
└─────────────────────────────────────────────────────────┘
Backend deletes metadata from RDS
         ↓
Returns image key to frontend

┌─────────────────────────────────────────────────────────┐
│ Step 4: Delete from S3                                   │
└─────────────────────────────────────────────────────────┘
Frontend calls Storage.remove(key, { level: 'private' })
         ↓
Amplify gets AWS credentials from Identity Pool
         ↓
Amplify signs S3 DELETE request
         ↓
S3 validates IAM permissions
         ↓
Checks: Does key start with private/{userId}/?
         ↓
If yes → Delete file
If no → 403 Forbidden
         ↓
Success response


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Token Flow Diagram

┌──────────────────────────────────────────────────────────────┐
│                    User Authentication                        │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ Cognito User Pool                                             │
│ - Validates username/password                                 │
│ - Issues JWT tokens                                           │
│   • ID Token (identity info)                                  │
│   • Access Token (API authorization)                          │
│   • Refresh Token (renew tokens)                              │
└──────────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────┴───────┐
                    ↓               ↓
┌─────────────────────────┐  ┌─────────────────────────────────┐
│ Backend API             │  │ Cognito Identity Pool            │
│ - Validates JWT         │  │ - Exchanges JWT for AWS creds    │
│ - Extracts user claims  │  │ - Assumes IAM role               │
│ - Authorizes actions    │  │ - Returns temporary credentials  │
└─────────────────────────┘  └─────────────────────────────────┘
         ↓                              ↓
┌─────────────────────────┐  ┌─────────────────────────────────┐
│ RDS PostgreSQL          │  │ S3 / CloudFront                  │
│ - Store metadata        │  │ - Validate IAM permissions       │
│ - Query user data       │  │ - Allow/deny based on role       │
└─────────────────────────┘  └─────────────────────────────────┘


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Security Model

### Access Levels

| Level | Path | Guest Access | Authenticated Access |
|-------|------|--------------|---------------------|
| public | public/* | ✅ Read | ✅ Read/Write |
| protected | protected/{userId}/* | ✅ Read all | ✅ Read all, Write own |
| private | private/{userId}/* | ❌ No access | ✅ Read/Write own only |

### IAM Policy Variables

json
{
  "Resource": "arn:aws:s3:::bucket/private/${cognito-identity.amazonaws.com:sub}/*"
}


At runtime, AWS replaces:
- ${cognito-identity.amazonaws.com:sub} → actual user's Cognito Identity ID
- Example: private/us-east-1:a1b2c3d4-5678-90ab-cdef-EXAMPLE11111/photo.jpg

This ensures:
- User A cannot access User B's files
- Enforced at AWS IAM level (not application level)
- No way to bypass (even with direct S3 API calls)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Token Expiration & Refresh

┌─────────────────────────────────────────────────────────┐
│ Token Lifecycle                                          │
└─────────────────────────────────────────────────────────┘

ID Token expires (1 hour)
         ↓
User makes request
         ↓
Amplify detects expired token
         ↓
Amplify automatically uses Refresh Token
         ↓
Calls Cognito User Pool
         ↓
Returns new ID Token + Access Token
         ↓
Request continues with new token
         ↓
User doesn't notice (seamless)

Refresh Token expires (30 days)
         ↓
User must sign in again


Automatic refresh (handled by Amplify):
javascript
// Amplify automatically refreshes tokens
const session = await Auth.currentSession();
// If expired, Amplify uses refresh token automatically


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Summary: Key Components

### 1. Cognito User Pool (Authentication)
- **Purpose:** Verify user identity
- **Output:** JWT tokens (ID, Access, Refresh)
- **Used for:** Backend API authorization

### 2. Cognito Identity Pool (Authorization)
- **Purpose:** Provide AWS service access
- **Input:** JWT token (or unauthenticated)
- **Output:** Temporary AWS credentials
- **Used for:** S3, DynamoDB, etc.

### 3. IAM Roles
- **Unauthenticated Role:** Read-only public access
- **Authenticated Role:** Full access to user's own resources

### 4. AWS Amplify
- **Purpose:** Simplify authentication flow
- **Handles:** Token management, credential exchange, request signing
- **Automatic:** Token refresh, credential caching

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


## Code Example: Complete Flow

javascript
import { Auth, Storage } from 'aws-amplify';

// 1. Sign in (get JWT tokens)
const user = await Auth.signIn('user@example.com', 'Password123!');

// 2. Upload image (automatic credential exchange)
const result = await Storage.put('photo.jpg', file, {
  level: 'private', // Uploads to: private/{userId}/photo.jpg
  contentType: 'image/jpeg'
});

// 3. Call backend API (use JWT token)
const session = await Auth.currentSession();
const idToken = session.getIdToken().getJwtToken();

const response = await fetch('https://api.example.com/images', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${idToken}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    key: result.key,
    filename: 'photo.jpg'
  })
});

// 4. Get image URL (automatic credential exchange)
const url = await Storage.get('photo.jpg', {
  level: 'private', // Gets from: private/{userId}/photo.jpg
  expires: 3600 // Signed URL valid for 1 hour
});

// 5. Delete image (automatic credential exchange)
await Storage.remove('photo.jpg', {
  level: 'private'
});

// 6. Sign out (clear tokens)
await Auth.signOut();


Behind the scenes, Amplify:
1. Stores JWT tokens in browser
2. Exchanges JWT for AWS credentials via Identity Pool
3. Signs all S3 requests with credentials
4. Refreshes tokens automatically when expired
5. Handles all security and encryption