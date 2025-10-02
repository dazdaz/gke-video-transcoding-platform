# 05-create-cpu-node-pool.sh

PROJECT_ID=my-playground
CLUSTER_NAME=tp
TP_SERVICE_ACCOUNT=gke-${CLUSTER_NAME}-service-account

# Create CPU node pool for batch-aggregator and other non-GPU services
gcloud container node-pools create cpu-pool \
  --cluster=${CLUSTER_NAME} \
  --project=${PROJECT_ID} \
  --location=europe-west4 \
  --machine-type=n1-standard-4 \
  --disk-size=100 \
  --disk-type=pd-standard \
  --num-nodes=1 \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=5 \
  --enable-autorepair \
  --enable-autoupgrade
