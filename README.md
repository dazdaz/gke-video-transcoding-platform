# GKE Video Transcoding Platform - Setup Guide

Complete infrastructure setup scripts for a GPU-accelerated video transcoding platform on Google Kubernetes Engine (GKE).

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Setup Instructions](#setup-instructions)
- [Configuration](#configuration)
- [Verification](#verification)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## 🎯 Overview

This repository contains automated setup scripts for deploying a production-ready video transcoding platform on GKE with:

- **GPU-accelerated transcoding** using NVIDIA Tesla T4 GPUs
- **Workload Identity** for secure GCP resource access
- **Auto-scaling** node pools for GPU and CPU workloads
- **GCS integration** for input/output video storage
- **Monitoring & Logging** with Google Cloud Managed Prometheus

## ✅ Prerequisites

### Required Tools
```bash
# Google Cloud SDK
gcloud --version

# kubectl
kubectl version --client

# gsutil (included with gcloud)
gsutil version
```

### Required Permissions
Your GCP account needs:
- `roles/container.admin` - GKE cluster management
- `roles/iam.serviceAccountAdmin` - Service account creation
- `roles/compute.networkAdmin` - VPC network management
- `roles/storage.admin` - GCS bucket management
- `roles/artifactregistry.admin` - Container registry management

### GCP Project Setup
```bash
# Set your project ID
export PROJECT_ID=your-project-id

# Enable required APIs
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         GKE Cluster                         │
│  ┌────────────────────┐         ┌────────────────────┐      │
│  │   GPU Node Pool    │         │   CPU Node Pool    │      │
│  │  (NVIDIA T4 GPUs)  │         │  (General workload)│      │
│  │  - Auto-scaling    │         │  - Auto-scaling    │      │
│  │  - 1-20 nodes      │         │  - 1-5 nodes       │      │
│  └────────────────────┘         └────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
           │                                  │
           │ Workload Identity                │
           ▼                                  ▼
┌──────────────────────┐          ┌──────────────────────┐
│  GCS Input Bucket    │          │  GCS Output Bucket   │
│  (Raw videos)        │          │  (Transcoded videos) │
└──────────────────────┘          └──────────────────────┘
```

## 🚀 Setup Instructions

### Quick Start

Run all setup scripts in order:

```bash
# Clone this repository
git clone <your-repo-url>
cd <repo-directory>

# Make all scripts executable
chmod +x *.sh

# Run setup in sequence
./01-create-service-accounts-workload-identity.sh
./02-create-network.sh
./03-create-gke.sh
./04-create-gpu-node-pool.sh
./05-create-cpu-node-pool.sh
./06-install-gmp.sh
./07-create-registry.sh
./08-create-gcs.sh
```

### Step-by-Step Setup

#### 1️⃣ Workload Identity & Service Accounts
```bash
./01-create-service-accounts-workload-identity.sh
```
**What it does:**
- Creates Kubernetes Service Account (KSA): `gke-tp-service-account`
- Creates Google Cloud Service Account (GSA): `gke-tp-gcs-accessor`
- Configures Workload Identity binding
- Grants GCS bucket permissions
- Enables logging and monitoring

#### 2️⃣ VPC Network
```bash
./02-create-network.sh
```
**What it does:**
- Creates custom VPC: `tpc-network`
- Creates subnet in `europe-west4`: `10.0.0.0/20`
- Enables Private Google Access

#### 3️⃣ GKE Cluster
```bash
./03-create-gke.sh
```
**What it does:**
- Creates regional GKE cluster in `europe-west4`
- Enables Workload Identity
- Configures auto-scaling (0-100 nodes)
- Enables shielded nodes for security
- Configures logging and monitoring

**Cluster specs:**
- **Location:** europe-west4 (multi-zonal)
- **Network:** Custom VPC with private Google access
- **IP ranges:** 
  - Pods: `10.112.0.0/14`
  - Services: `10.116.0.0/20`

#### 4️⃣ GPU Node Pool
```bash
./04-create-gpu-node-pool.sh
```
**What it does:**
- Creates GPU node pool with NVIDIA Tesla T4
- Supports two GPU sharing modes:
  - **MPS** (Multi-Process Service) - Better isolation
  - **Time-sharing** - Share GPUs across pods
- Configures SSD storage for fast I/O

**GPU Node specs:**
- **Machine type:** n1-highmem-16 (16 vCPUs, 104 GB RAM)
- **GPU:** 1x NVIDIA Tesla T4
- **Disk:** 500GB SSD + 1 local SSD
- **Auto-scaling:** 1-20 nodes

**Switching GPU sharing modes:**
Edit `04-create-gpu-node-pool.sh`:
```bash
# Choose: "mps" or "time-sharing"
GPU_SHARING_STRATEGY="mps"
```

#### 5️⃣ CPU Node Pool
```bash
./05-create-cpu-node-pool.sh
```
**What it does:**
- Creates CPU-only node pool for non-GPU workloads
- Handles batch aggregation and orchestration

**CPU Node specs:**
- **Machine type:** n1-standard-4 (4 vCPUs, 15 GB RAM)
- **Disk:** 100GB standard persistent disk
- **Auto-scaling:** 1-5 nodes

#### 6️⃣ Managed Prometheus
```bash
./06-install-gmp.sh
```
**What it does:**
- Enables Google Cloud Managed Prometheus
- Provides metrics collection and monitoring

#### 7️⃣ Artifact Registry
```bash
./07-create-registry.sh
```
**What it does:**
- Creates Docker repository: `transcode-repo`
- Grants cluster service account pull access

**Registry URL:**
```
europe-west4-docker.pkg.dev/my-playground/transcode-repo
```

#### 8️⃣ GCS Buckets
```bash
./08-create-gcs.sh
```
**What it does:**
- Creates input bucket: `transcode-preprocessing-bucket`
- Creates output bucket: `transcode-postprocessing-bucket`
- Configures IAM permissions for service account
- Sets up Workload Identity for Kubernetes pods

## ⚙️ Configuration

### Environment Variables

Edit the scripts to customize for your environment:

```bash
# Common across all scripts
PROJECT_ID=my-playground          # Your GCP project ID
CLUSTER_NAME=tp                     # GKE cluster name
REGION=europe-west4                 # GCP region

# Service accounts
KSA_NAME=gke-tp-service-account    # Kubernetes SA
GSA_NAME=gke-tp-gcs-accessor       # Google Cloud SA

# Storage
INPUT_BUCKET=transcode-preprocessing-bucket
OUTPUT_BUCKET=transcode-postprocessing-bucket

# Registry
REPO_NAME=transcode-repo
```

### GPU Configuration

**MPS Mode** (Recommended for production):
```yaml
resources:
  limits:
    nvidia.com/gpu: 0.25  # Request 25% of GPU
```

**Time-Sharing Mode:**
```yaml
resources:
  limits:
    nvidia.com/gpu: 1  # Full GPU, shared with max 4 pods
```

## ✓ Verification

### Check Cluster Status
```bash
# Get cluster info
gcloud container clusters describe tp --region=europe-west4

# List node pools
gcloud container node-pools list --cluster=tp --region=europe-west4

# Check nodes
kubectl get nodes -o wide
```

### Verify Service Accounts
```bash
# List Kubernetes service accounts
kubectl get serviceaccounts

# Check Workload Identity annotation
kubectl describe sa gke-tp-service-account

# Verify GCP service account
gcloud iam service-accounts describe \
  gke-tp-gcs-accessor@my-playground.iam.gserviceaccount.com
```

### Test GCS Access
```bash
# List buckets
gsutil ls

# Check bucket permissions
gsutil iam get gs://transcode-preprocessing-bucket

# Upload test file
echo "test" > test.txt
gsutil cp test.txt gs://transcode-preprocessing-bucket/
gsutil ls gs://transcode-preprocessing-bucket/
```

### Verify GPU Availability
```bash
# Check GPU nodes
kubectl get nodes -l cloud.google.com/gke-accelerator=nvidia-tesla-t4

# Describe GPU node
kubectl describe node <gpu-node-name> | grep -A 10 "Allocatable"
```

## 🎬 Usage

### Deploy Transcoding Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-transcoder
spec:
  serviceAccountName: gke-tp-service-account
  containers:
  - name: transcoder
    image: europe-west4-docker.pkg.dev/my-playground/transcode-repo/transcoder:latest
    resources:
      limits:
        nvidia.com/gpu: 1
    env:
    - name: INPUT_BUCKET
      value: "transcode-preprocessing-bucket"
    - name: OUTPUT_BUCKET
      value: "transcode-postprocessing-bucket"
  nodeSelector:
    cloud.google.com/gke-accelerator: nvidia-tesla-t4
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

### Upload Videos
```bash
# Upload source videos
gsutil -m cp -r /path/to/videos/* gs://transcode-preprocessing-bucket/

# Monitor transcoding
kubectl logs -f gpu-transcoder

# Check output
gsutil ls gs://transcode-postprocessing-bucket/
```

## 🔧 Troubleshooting

### Common Issues

**Issue: Pods stuck in Pending**
```bash
# Check events
kubectl describe pod <pod-name>

# Common causes:
# 1. No GPU nodes available - check node pool scaling
kubectl get nodes -l workload-type=gpu-transcoding

# 2. Resource limits too high
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

**Issue: Permission denied accessing GCS**
```bash
# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy \
  gke-tp-gcs-accessor@my-playground.iam.gserviceaccount.com

# Check pod's service account
kubectl get pod <pod-name> -o jsonpath='{.spec.serviceAccountName}'

# Test from within pod
kubectl exec <pod-name> -- gcloud auth list
```

**Issue: GPU not detected**
```bash
# Check GPU driver installation
kubectl get daemonset -n kube-system | grep nvidia

# Verify GPU allocation
kubectl describe node <gpu-node-name> | grep nvidia.com/gpu
```

### Cleanup

```bash
# Delete cluster (WARNING: This deletes everything)
gcloud container clusters delete tp --region=europe-west4

# Delete buckets
gsutil rm -r gs://transcode-preprocessing-bucket
gsutil rm -r gs://transcode-postprocessing-bucket

# Delete service accounts
gcloud iam service-accounts delete \
  gke-tp-gcs-accessor@my-playground.iam.gserviceaccount.com

# Delete VPC network
gcloud compute networks subnets delete tpc-network-subnet-europe-west4 --region=europe-west4
gcloud compute networks delete tpc-network
```

## 📚 Additional Resources

- [GKE GPU Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
- [Workload Identity Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [GPU Sharing Strategies](https://cloud.google.com/kubernetes-engine/docs/concepts/timesharing-gpus)
- [GCS Best Practices](https://cloud.google.com/storage/docs/best-practices)

---
