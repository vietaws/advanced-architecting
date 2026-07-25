import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const s3Client = new S3Client({ region: process.env.AWS_REGION });

export async function uploadImage(file, productId) {
  try {
    const ext = file.originalname.split('.').pop();
    const key = `products/${productId}-${Date.now()}.${ext}`;

    await s3Client.send(new PutObjectCommand({
      Bucket: process.env.S3_BUCKET,
      Key: key,
      Body: file.buffer,
      ContentType: file.mimetype
    }));

    return key;
  } catch (error) {
    console.error('S3 upload error:', error);
    throw new Error(`Failed to upload image: ${error.message}`);
  }
}

export async function getImageUrl(key) {
  try {
    if (!key) return '';
    const command = new GetObjectCommand({
      Bucket: process.env.S3_BUCKET,
      Key: key
    });
    return await getSignedUrl(s3Client, command, { expiresIn: 3600 });
  } catch (error) {
    console.error('Pre-signed URL error:', error);
    return '';
  }
}

export async function deleteImage(key) {
  try {
    if (!key) return;
    await s3Client.send(new DeleteObjectCommand({
      Bucket: process.env.S3_BUCKET,
      Key: key
    }));
  } catch (error) {
    console.error('S3 delete error:', error);
  }
}
