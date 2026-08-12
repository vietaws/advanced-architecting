# Phase 1 — EKS Cluster

---

One command creates the control plane, a new VPC (`10.2.0.0/16`), public + private subnets in 2 AZs, subnet tags for ALB, and the IAM OIDC provider for IRSA.

```bash
eksctl create cluster \
  --name demo-cluster \
  --region ap-southeast-1 \
  --version 1.36 \
  --vpc-cidr 10.2.0.0/16 \
  --zones ap-southeast-1a,ap-southeast-1b \
  --without-nodegroup \
  --with-oidc \
  --tags "project=architecting-pro,env=demo"
```

**Duration:** ~15 minutes. kubeconfig is updated automatically.

---

## VPC layout (auto-created)

| Subnet type | AZs | Auto-tagged for |
|---|---|---|
| Public (2) | a, b | `kubernetes.io/role/elb=1` — ALB |
| Private (2) | a, b | `kubernetes.io/role/internal-elb=1` — internal ALB |

---

## Node group

Choose **one** option at runtime. You can add the other later.

### Option A — Public nodes (default, no NAT Gateway cost)

Nodes in public subnets with direct internet access.

```bash
eksctl create nodegroup \
  --cluster demo-cluster \
  --region ap-southeast-1 \
  --name public-nodes \
  --node-type t4g.medium \
  --nodes 1 --nodes-min 1 --nodes-max 4 \
  --node-volume-size 20 --node-volume-type gp3 \
  --node-zones ap-southeast-1a,ap-southeast-1b \
  --node-labels "role=app,arch=graviton,subnet=public" \
  --managed
  
eksctl create nodegroup \
  --cluster demo-cluster \
  --region ap-southeast-1 \
  --name public-spot-nodes \
  --node-type t4g.medium \
  --spot \
  --nodes 2 --nodes-min 2 --nodes-max 4 \
  --node-volume-size 20 --node-volume-type gp3 \
  --node-zones ap-southeast-1a,ap-southeast-1b \
  --node-labels "role=app,arch=graviton,subnet=public" \
  --managed
```
**Duration:** ~5 minutes.

### Option B — Private nodes (NAT Gateway, ~$0.045/hr per AZ)

Nodes in private subnets; eksctl provisions NAT Gateways automatically.

```bash
eksctl create nodegroup \
  --cluster demo-cluster \
  --region ap-southeast-1 \
  --name private-nodes \
  --node-type t4g.medium \
  --spot \
  --nodes 2 --nodes-min 2 --nodes-max 4 \
  --node-volume-size 20 --node-volume-type gp3 \
  --node-zones ap-southeast-1a,ap-southeast-1b \
  --node-private-networking \
  --node-labels "role=app,arch=graviton,subnet=private" \
  --managed
```

**Duration:** ~5 minutes.

---

## Node group spec

| Property | Value | Notes |
|---|---|---|
| Instance type | t4g.medium | Graviton2, 2 vCPU / 4 GB |
| Capacity | Spot | ~70% cost saving; pods are stateless |
| Min / Desired / Max | 2 / 2 / 4 | HA by default; scales to 4 under load |
| Volume | 20 GB gp3 | Container images + OS |

For production, switch to `m7g.large` or `m8g.large`.

---

## Verify

```bash
kubectl get nodes -o wide
# Expect 2 nodes, STATUS=Ready, linux/arm64
```

---