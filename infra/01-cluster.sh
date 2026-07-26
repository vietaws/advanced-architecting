#!/usr/bin/env bash
# =============================================================================
# 01-cltion)
#   - kubeconfig updated automatically by eksctluster.sh — Create EKS cluster with Graviton node group
#
# Prerequisites:
#   - AWS CLI v2 configured with admin credentials
#   - eksctl >= 0.180  (brew install eksctl)
#   - kubectl >= 1.29  (brew install kubectl)
#
# Usage:
#   chmod +x infra/01-cluster.sh
#   AWS_ACCOUNT_ID=123456789012 ./infra/01-cluster.sh
#
# What this creates:
#   - EKS cluster:  demo-cluster  (ap-southeast-1, K8s 1.30)
#   - Node group:   app-nodes     (m8g.large Graviton4, 2–6 nodes, Spot)
#   - IAM OIDC provider (required for IRSA, done after cluster crea
# =============================================================================
set -euo pipefail

# ── Variables — edit before running ──────────────────────────────────────────
CLUSTER_NAME="demo-cluster"
REGION="ap-southeast-1"
K8S_VERSION="1.30"
NODE_GROUP_NAME="app-nodes"

# Graviton instance types — demo-optimised for cost:
#   t4g.small  = Graviton2, 2 vCPU / 2 GB  — primary (burstable, fine for demo)
#   t4g.medium = Graviton2, 2 vCPU / 4 GB  — fallback if small pool is exhausted
# 6 pods × 64Mi = 384Mi + ~300Mi system = ~700Mi — fits on a single t4g.small
# NOTE: for production / load testing swap back to m8g.large,m7g.large,m6g.large
INSTANCE_TYPES="t4g.small,t4g.medium"
MIN_SIZE=1
MAX_SIZE=2
DESIRED_SIZE=1

# VPC — use your existing VPC subnet IDs
# Tag public subnets with: kubernetes.io/role/elb=1
# Tag private subnets with: kubernetes.io/role/internal-elb=1
SUBNET_APP_1="subnet-REPLACE_APP_1"   # app-1 10.1.3.0/24
SUBNET_APP_2="subnet-REPLACE_APP_2"   # app-2 10.1.4.0/24
SUBNET_PUB_1="subnet-REPLACE_PUB_1"   # public-1 10.1.1.0/24
SUBNET_PUB_2="subnet-REPLACE_PUB_2"   # public-2 10.1.2.0/24

# AWS account ID — passed as env var or auto-detected
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

echo "============================================================"
echo "  Creating EKS cluster: ${CLUSTER_NAME}"
echo "  Region:               ${REGION}"
echo "  K8s version:          ${K8S_VERSION}"
echo "  Account ID:           ${AWS_ACCOUNT_ID}"
echo "============================================================"

# ── Step 1: Create EKS cluster (control plane only) ──────────────────────────
echo ""
echo "[1/4] Creating EKS control plane..."

eksctl create cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --version "${K8S_VERSION}" \
  --without-nodegroup \
  --vpc-private-subnets "${SUBNET_APP_1},${SUBNET_APP_2}" \
  --vpc-public-subnets  "${SUBNET_PUB_1},${SUBNET_PUB_2}" \
  --tags "project=architecting-pro,env=demo"

echo "[1/4] ✓ Control plane created"

# ── Step 2: Create Graviton Spot node group ───────────────────────────────────
echo ""
echo "[2/4] Creating Graviton node group: ${NODE_GROUP_NAME}..."

eksctl create nodegroup \
  --cluster  "${CLUSTER_NAME}" \
  --region   "${REGION}" \
  --name     "${NODE_GROUP_NAME}" \
  --node-type "${INSTANCE_TYPES}" \
  --spot \
  --nodes          "${DESIRED_SIZE}" \
  --nodes-min      "${MIN_SIZE}" \
  --nodes-max      "${MAX_SIZE}" \
  --node-volume-size 20 \
  --node-volume-type gp3 \
  --subnet-ids    "${SUBNET_APP_1},${SUBNET_APP_2}" \
  --asg-access \
  --managed \
  --node-labels   "role=app,arch=graviton" \
  --tags          "project=architecting-pro,env=demo"

echo "[2/4] ✓ Node group created"

# ── Step 3: Tag subnets for ALB controller ────────────────────────────────────
echo ""
echo "[3/4] Tagging subnets for ALB..."

# Public subnets — internet-facing ALB
aws ec2 create-tags \
  --resources "${SUBNET_PUB_1}" "${SUBNET_PUB_2}" \
  --tags \
    "Key=kubernetes.io/role/elb,Value=1" \
    "Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared" \
  --region "${REGION}"

# Private (app) subnets — internal ALB
aws ec2 create-tags \
  --resources "${SUBNET_APP_1}" "${SUBNET_APP_2}" \
  --tags \
    "Key=kubernetes.io/role/internal-elb,Value=1" \
    "Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared" \
  --region "${REGION}"

echo "[3/4] ✓ Subnets tagged"

# ── Step 4: Enable IAM OIDC provider (required for IRSA) ─────────────────────
echo ""
echo "[4/4] Enabling IAM OIDC provider..."

eksctl utils associate-iam-oidc-provider \
  --cluster "${CLUSTER_NAME}" \
  --region  "${REGION}" \
  --approve

echo "[4/4] ✓ OIDC provider enabled"

# ── Summary ───────────────────────────────────────────────────────────────────
OIDC_ID=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|.*/||')

echo ""
echo "============================================================"
echo "  ✓ Cluster setup complete"
echo ""
echo "  Cluster:    ${CLUSTER_NAME}"
echo "  Region:     ${REGION}"
echo "  OIDC ID:    ${OIDC_ID}"
echo ""
echo "  Next step:  ./infra/02-addons.sh"
echo "============================================================"
