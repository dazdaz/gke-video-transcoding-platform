#!/bin/bash

# 01-create-service-accounts-workload-identity.sh

# Configuration
PROJECT_ID=my-playground
CLUSTER_NAME=tp
KSA_NAME=gke-${CLUSTER_NAME}-service-account
GSA_NAME=gke-${CLUSTER_NAME}-gcs-accessor
NAMESPACE=default
INPUT_BUCKET=transcode-preprocessing-bucket
OUTPUT_BUCKET=transcode-postprocessing-bucket

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Setting up Workload Identity for GKE${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Step 1: Create Kubernetes Service Account (KSA)
echo -e "${YELLOW}Step 1: Creating Kubernetes Service Account...${NC}"
kubectl create serviceaccount ${KSA_NAME} --namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
if [ $? -eq 0 ]; then
    echo -e "${GREEN}‚úì Created Kubernetes Service Account: ${KSA_NAME}${NC}"
else
    echo -e "${RED}‚úó Failed to create Kubernetes Service Account${NC}"
    exit 1
fi

# Step 2: Create Google Cloud IAM Service Account (GSA)
echo -e "${YELLOW}Step 2: Creating Google Cloud Service Account...${NC}"
gcloud iam service-accounts create ${GSA_NAME} \
    --display-name="GKE Transcoding GCS Accessor" \
    --project=${PROJECT_ID}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}‚úì Created Google Cloud Service Account: ${GSA_NAME}${NC}"
else
    echo -e "${YELLOW}‚ö† Service account might already exist, continuing...${NC}"
fi

# Get the GSA email
GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo -e "${BLUE}GSA Email: ${GSA_EMAIL}${NC}"

# Step 3: Grant GSA permissions on buckets
echo -e "${YELLOW}Step 3: Granting permissions on GCS buckets...${NC}"

# Grant read permission on input bucket
echo -e "  Granting objectViewer on ${INPUT_BUCKET}..."
gsutil iam ch serviceAccount:${GSA_EMAIL}:objectViewer gs://${INPUT_BUCKET}
if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ‚úì Granted objectViewer permission on ${INPUT_BUCKET}${NC}"
else
    echo -e "${RED}  ‚úó Failed to grant permission on ${INPUT_BUCKET}${NC}"
fi

# Grant write permission on output bucket  
echo -e "  Granting objectAdmin on ${OUTPUT_BUCKET}..."
gsutil iam ch serviceAccount:${GSA_EMAIL}:objectAdmin gs://${OUTPUT_BUCKET}
if [ $? -eq 0 ]; then
    echo -e "${GREEN}  ‚úì Granted objectAdmin permission on ${OUTPUT_BUCKET}${NC}"
else
    echo -e "${RED}  ‚úó Failed to grant permission on ${OUTPUT_BUCKET}${NC}"
fi

# Step 4: Link KSA to GSA using Workload Identity
echo -e "${YELLOW}Step 4: Setting up Workload Identity binding...${NC}"

# Allow the KSA to impersonate the GSA
gcloud iam service-accounts add-iam-policy-binding ${GSA_EMAIL} \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    --project=${PROJECT_ID}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}‚úì Created Workload Identity binding${NC}"
else
    echo -e "${RED}‚úó Failed to create Workload Identity binding${NC}"
    exit 1
fi

# Step 5: Annotate the Kubernetes Service Account
echo -e "${YELLOW}Step 5: Annotating Kubernetes Service Account...${NC}"
kubectl annotate serviceaccount ${KSA_NAME} \
    iam.gke.io/gcp-service-account=${GSA_EMAIL} \
    --namespace=${NAMESPACE} \
    --overwrite

if [ $? -eq 0 ]; then
    echo -e "${GREEN}‚úì Annotated Kubernetes Service Account${NC}"
else
    echo -e "${RED}‚úó Failed to annotate Kubernetes Service Account${NC}"
    exit 1
fi

# Step 6: Grant additional permissions for monitoring and logging
echo -e "${YELLOW}Step 6: Granting additional permissions...${NC}"

# Logging
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/logging.logWriter" \
    --condition=None

# Monitoring
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/monitoring.metricWriter" \
    --condition=None

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/monitoring.viewer" \
    --condition=None

echo -e "${GREEN}‚úì Granted monitoring and logging permissions${NC}"

# Step 7: Verify setup
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Verification${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "${YELLOW}Kubernetes Service Account:${NC}"
kubectl get serviceaccount ${KSA_NAME} -n ${NAMESPACE} -o yaml | grep -A 2 "annotations:"

echo ""
echo -e "${YELLOW}Google Cloud Service Account:${NC}"
gcloud iam service-accounts describe ${GSA_EMAIL} --project=${PROJECT_ID}

echo ""
echo -e "${YELLOW}Workload Identity Binding:${NC}"
gcloud iam service-accounts get-iam-policy ${GSA_EMAIL} --project=${PROJECT_ID}

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}‚úÖ Workload Identity setup completed!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}The Python script will now use: ${KSA_NAME}${NC}"
echo -e "${BLUE}This account has permissions to:${NC}"
echo -e "${BLUE}  - Read from: gs://${INPUT_BUCKET}${NC}"
echo -e "${BLUE}  - Write to: gs://${OUTPUT_BUCKET}${NC}"
echo ""
