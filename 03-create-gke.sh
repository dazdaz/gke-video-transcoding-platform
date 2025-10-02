# 03-create-gke.sh

PROJECT_ID=my-playground
CLUSTER_NAME=tp

gcloud container clusters create ${CLUSTER_NAME} \
  --project=${PROJECT_ID} \
  --location=europe-west4 \
  --node-locations=europe-west4-a,europe-west4-b,europe-west4-c \
  --network=tpc-network \
  --subnetwork=tpc-network-subnet-europe-west4 \
  --cluster-ipv4-cidr=10.112.0.0/14 \
  --services-ipv4-cidr=10.116.0.0/20 \
  --enable-ip-alias \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=100 \
  --release-channel=regular \
  --enable-autoupgrade \
  --enable-autorepair \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
  --no-enable-basic-auth \
  --no-issue-client-certificate
