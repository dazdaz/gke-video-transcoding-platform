#!/bin/bash

# dcgm-query.sh

## Create a script to query all DCGM metrics:

# Save all DCGM metrics to a file
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/daev-playground/metricDescriptors" | \
  jq -r '.metricDescriptors[].type' | grep -i DCGM > dcgm_metrics.txt

# Query each metric
while read metric; do
  echo "Querying: $metric"
  curl -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    "https://monitoring.googleapis.com/v3/projects/daev-playground/timeSeries:query" \
    -d "{
      \"query\": \"fetch prometheus_target | metric '$metric' | within 1h\"
    }" | jq '.'
done < dcgm_metrics.txt
