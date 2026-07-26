# ── Stage 1: install production dependencies ─────────────────────────────────
FROM node:24-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

# ── Stage 2: final image ──────────────────────────────────────────────────────
FROM node:24-alpine

WORKDIR /app

# Copy production node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application source
COPY . .

# Run as non-root user
USER node

EXPOSE 3001

CMD ["node", "server.js"]
