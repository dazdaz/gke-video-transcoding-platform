# 07-create-registry.sh

REPO_NAME=transcode-repo
PROJECT_ID=my-playground
REGION=europe-west4
CLUSTER_NAME=tp
CLUSTER_SA=gke-${CLUSTER_NAME}-service-account

gcloud artifacts repositories create ${REPO_NAME} --repository-format=docker --location=${REGION}
gcloud artifacts repositories add-iam-policy-binding ${REPO_NAME} --member=serviceAccount:${CLUSTER_SA}@${PROJECT_ID}.iam.gserviceaccount.com --role=roles/artifactregistry.reader --location=${REGION}

gcloud artifacts repositories describe ${REPO_NAME} --location=${REGION}
