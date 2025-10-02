# 02-create-network.sh

# Create network

gcloud compute networks create tpc-network \
  --project=my-playground \
  --subnet-mode=custom

# Create the subnet
gcloud compute networks subnets create tpc-network-subnet-europe-west4 \
  --project=daev-playground \
  --network=tpc-network \
  --region=europe-west4 \
  --range=10.0.0.0/20 \
  --enable-private-ip-google-access
