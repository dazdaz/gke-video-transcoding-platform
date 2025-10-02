PROJECT_ID=my-playground

gcloud builds submit . \
--config=cloudbuild.yaml \
 --substitutions=_PROJECT_ID=${PROJECT_ID},_REGION=europe-west4,_REPO=transcode-repo --project=${PROJECT_ID}
