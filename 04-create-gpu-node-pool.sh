#!/bin/bash

# Configuration
PROJECT_ID=my-playground
CLUSTER_NAME=tp
TP_SERVICE_ACCOUNT=gke-${CLUSTER_NAME}-service-account

# Choose GPU sharing strategy: "time-sharing" or "mps"
# MPS provides better isolation and performance for multiple workloads
GPU_SHARING_STRATEGY="mps"  # Change this to switch between modes

echo "Creating GPU node pool with ${GPU_SHARING_STRATEGY} strategy..."

if [ "$GPU_SHARING_STRATEGY" == "mps" ]; then
    # Create MPS-enabled GPU node pool
    gcloud container node-pools create transcoder-gpunode-pool-mps \
      --cluster=${CLUSTER_NAME} \
      --project=${PROJECT_ID} \
      --location=europe-west4 \
      --node-locations=europe-west4-a \
      --machine-type=n1-highmem-16 \
      --accelerator=type=nvidia-tesla-t4,count=1,gpu-sharing-strategy=mps,gpu-driver-version=latest \
      --disk-size=500 \
      --disk-type=pd-ssd \
      --local-ssd-count=1 \
      --num-nodes=2 \
      --enable-autoscaling \
      --min-nodes=1 \
      --max-nodes=20 \
      --enable-autorepair \
      --enable-autoupgrade \
      --service-account=${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com \
      --scopes=https://www.googleapis.com/auth/cloud-platform \
      --node-taints=nvidia.com/gpu=present:NoSchedule \
      --node-labels=workload-type=gpu-transcoding,gpu-sharing=mps \
      --metadata=disable-legacy-endpoints=true \
      --shielded-secure-boot \
      --shielded-integrity-monitoring

    echo "MPS GPU node pool created. Pods can request fractional GPUs (e.g., 0.25)"
    
else
    # Create time-sharing GPU node pool (original configuration)
    gcloud container node-pools create transcoder-gpunode-pool \
      --cluster=${CLUSTER_NAME} \
      --project=${PROJECT_ID} \
      --location=europe-west4 \
      --node-locations=europe-west4-a \
      --machine-type=n1-highmem-16 \
      --accelerator=type=nvidia-tesla-t4,count=1,gpu-sharing-strategy=time-sharing,max-shared-clients-per-gpu=4,gpu-driver-version=latest \
      --disk-size=500 \
      --disk-type=pd-ssd \
      --local-ssd-count=1 \
      --num-nodes=2 \
      --enable-autoscaling \
      --min-nodes=1 \
      --max-nodes=20 \
      --enable-autorepair \
      --enable-autoupgrade \
      --service-account=${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com \
      --scopes=https://www.googleapis.com/auth/cloud-platform \
      --node-taints=nvidia.com/gpu=present:NoSchedule \
      --node-labels=workload-type=gpu-transcoding,gpu-sharing=time-sharing \
      --metadata=disable-legacy-endpoints=true \
      --shielded-secure-boot \
      --shielded-integrity-monitoring

    echo "Time-sharing GPU node pool created. Multiple pods can share GPUs."
fi

echo ""
echo "Node pool creation complete!"
echo "To verify: gcloud container node-pools list --cluster=${CLUSTER_NAME} --location=europe-west4"
