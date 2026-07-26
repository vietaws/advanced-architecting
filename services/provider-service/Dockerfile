# ── Stage 1: install production dependencies ──────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

# ── Stage 2: runtime image ─────────────────────────────────────────────────────
FROM node:20-alpine

WORKDIR /app

# Copy production node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application source
COPY . .

# Create EFS mount point directory
RUN mkdir -p /data/efs

# Run as non-root user for security
USER node

EXPOSE 3002

CMD ["node", "server.js"]
