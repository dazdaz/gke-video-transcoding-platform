#!/bin/bash

# 08-create-gcs.sh

PROJECT_ID=my-playground
REGION=europe-west4
CLUSTER_NAME=tp
TP_SERVICE_ACCOUNT=gke-${CLUSTER_NAME}-service-account
BUCKET_PREPROCESSING=transcode-preprocessing-bucket
BUCKET_POSTPROCESSING=transcode-postprocessing-bucket

echo "========================================="
echo "Setting up GCS buckets and permissions"
echo "========================================="

# Create the preprocessing bucket if it doesn't exist
echo "Creating GCS bucket: gs://${BUCKET_PREPROCESSING}/"
gsutil mb -p $PROJECT_ID -l $REGION -c standard gs://${BUCKET_PREPROCESSING}/ 2>/dev/null || echo "Bucket gs://${BUCKET_PREPROCESSING}/ already exists"

# Create the postprocessing bucket if it doesn't exist  
echo "Creating GCS bucket: gs://${BUCKET_POSTPROCESSING}/"
gsutil mb -p $PROJECT_ID -l $REGION -c standard gs://${BUCKET_POSTPROCESSING}/ 2>/dev/null || echo "Bucket gs://${BUCKET_POSTPROCESSING}/ already exists"

# Grant Storage Admin role to the service account at the project level
echo "Granting 'roles/storage.admin' to ${TP_SERVICE_ACCOUNT} at project level..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.admin" --no-user-output-enabled

# Also grant bucket-level IAM bindings for extra security
echo "Granting bucket-level IAM for gs://${BUCKET_PREPROCESSING}/"
gsutil iam ch serviceAccount:${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectAdmin gs://${BUCKET_PREPROCESSING}
gsutil iam ch serviceAccount:${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com:legacyBucketReader gs://${BUCKET_PREPROCESSING}

echo "Granting bucket-level IAM for gs://${BUCKET_POSTPROCESSING}/"
gsutil iam ch serviceAccount:${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com:roles/storage.objectAdmin gs://${BUCKET_POSTPROCESSING}
gsutil iam ch serviceAccount:${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com:legacyBucketWriter gs://${BUCKET_POSTPROCESSING}

# Create Kubernetes service account if it doesn't exist
echo "Creating Kubernetes service account 'compression-sa'..."
kubectl create serviceaccount compression-sa --namespace=default 2>/dev/null || echo "Kubernetes service account 'compression-sa' already exists"

# Bind the Google Service Account to the Kubernetes Service Account with Workload Identity
echo "Binding Google Service Account to Kubernetes Service Account..."
gcloud iam service-accounts add-iam-policy-binding \
    ${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[default/compression-sa]" --no-user-output-enabled

# Annotate the Kubernetes Service Account
echo "Annotating Kubernetes service account 'compression-sa'..."
kubectl annotate serviceaccount compression-sa \
    iam.gke.io/gcp-service-account=${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com \
    --overwrite

echo ""
echo "========================================="
echo "Verification"
echo "========================================="

# Verify the service account has the correct permissions at the project level
echo "Project-level IAM policies for ${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com:"
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --format="table(bindings.role)"

echo ""
# Verify bucket-level permissions for the preprocessing bucket
echo "Bucket-level permissions for gs://${BUCKET_PREPROCESSING}/:"
gsutil iam get gs://${BUCKET_PREPROCESSING} | grep -A 2 "${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" || echo "No specific permissions found"

echo ""
# Verify bucket-level permissions for the postprocessing bucket
echo "Bucket-level permissions for gs://${BUCKET_POSTPROCESSING}/:"
gsutil iam get gs://${BUCKET_POSTPROCESSING} | grep -A 2 "${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" || echo "No specific permissions found"

echo ""
echo "========================================="
echo "Testing Access"
echo "========================================="

# List files in preprocessing bucket
echo "Files in gs://${BUCKET_PREPROCESSING}/:"
gsutil ls gs://${BUCKET_PREPROCESSING}/ 2>/dev/null || echo "Empty or access denied"

echo ""
echo "Files in gs://${BUCKET_POSTPROCESSING}/:"
gsutil ls gs://${BUCKET_POSTPROCESSING}/ 2>/dev/null || echo "Empty or access denied"

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo "‚úî Buckets created:"
echo "   - gs://${BUCKET_PREPROCESSING}/"
echo "   - gs://${BUCKET_POSTPROCESSING}/"
echo ""
echo "‚úî Service account configured:"
echo "   - ${TP_SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
echo ""
echo "‚úî Kubernetes service account created:"
echo "   - compression-sa (with Workload Identity binding)"
echo ""
echo "Next steps:"
echo "1. Upload video files to gs://${BUCKET_PREPROCESSING}/"
echo "2. Run the transcoding job with:"
echo "   python3 ffmpeg-gpu-nvenc.py --mode gcs --gpu-model T4"
echo ""
