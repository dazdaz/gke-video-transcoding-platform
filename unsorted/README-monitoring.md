
## Hardware CPU Threads

If ffmpeg is told to use 6 threads, then will 6 threads be utilized ?

No, in an example where I did some video transcoding, FFmpeg was using approximately 3.6 CPU cores on average during the encoding process, even though it had 6 threads available. This is normal because:

1. Not all threads are always active simultaneously
2. Some threads may be waiting for I/O or synchronization
3. The workload (encoding a simple blue video) might not fully utilize all available threads
4. Thread efficiency is rarely 100%




## Working Solution - Using the API directly:

The key points:
1. **There's no gcloud CLI command** for directly querying time series - you need to use the API
2. **Use MQL (Monitoring Query Language)** via the `:query` endpoint for more flexible queries
3. **The metric type includes the full path** with the type suffix (e.g., `/gauge`, `/counter`)
4. Your DCGM metrics are successfully being collected and are available in Cloud Monitoring


# Query a specific DCGM metric using MQL (Monitoring Query Language)
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/daev-playground/timeSeries:query" \
  -d '{
    "query": "fetch prometheus_target | metric '\''prometheus.googleapis.com/DCGM_FI_DEV_GPU_UTIL/gauge'\'' | within 1h"
  }'


# Query a specific DCGM metric using MQL (Monitoring Query Language)
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/daev-playground/timeSeries:query" \
  -d '{
    "query": "fetch prometheus_target | metric '\''prometheus.googleapis.com/DCGM_FI_DEV_GPU_UTIL/gauge'\'' | within 1h"
  }'


## To query multiple DCGM metrics at once:

```bash
# List all DCGM metrics available
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/daev-playground/metricDescriptors" | \
  jq -r '.metricDescriptors[].type' | grep -i DCGM


## Query with specific time range and aggregation:

```bash
# Query with 1-minute intervals
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/daev-playground/timeSeries:query" \
  -d '{
    "query": "fetch prometheus_target | metric '\''prometheus.googleapis.com/DCGM_FI_DEV_GPU_UTIL/gauge'\'' | within 1h | every 1m"
  }'

## If you want to use the REST API with filters:

```bash
# Using the timeSeries list endpoint
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/daev-playground/timeSeries?filter=metric.type%3D%22prometheus.googleapis.com%2FDCGM_FI_DEV_GPU_UTIL%2Fgauge%22&interval.startTime=2025-01-09T00:00:00Z&interval.endTime=2025-01-10T00:00:00Z"



## Create a script to query all DCGM metrics:

```bash
#!/bin/bash

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



Querying the Metrics Exporter Directly
You can interact with the /metrics endpoint by making a simple HTTP request to the exposed port of the metrics exporter.
The data you can extract are Prometheus-formatted metrics that provide detailed insights into the performance of GPUs, disk I/O, and application-specific queues.

Howto use
kubectl port-forward custom-metrics-exporter-7hnmw 8000:8000
curl http://localhost:8000/metrics

Data You Can Extract
The provided configuration defines a custom Python-based metrics exporter and a DCGM exporter. The /metrics endpoint will expose all the metrics defined in these exporters in a Prometheus-compatible format. The data is organized into different types of metrics: gauges and histograms.

Custom Metrics (custom-metrics-exporter)
The custom-metrics-exporter collects metrics using nvidia-smi and psutil. You can extract the following data:

 custom_gpu_utilization: A gauge that measures the GPU utilization percentage. It's labeled with gpu_id to differentiate between multiple GPUs.
 custom_nvenc_sessions: A gauge that tracks the number of active NVENC (NVIDIA Encoder) sessions, also labeled by gpu_id.
 custom_disk_read_kb_per_sec: A gauge that shows the disk read rate in KB/s, labeled by the disk device.
 custom_disk_write_kb_per_sec: A gauge for the disk write rate in KB/s, labeled by the disk device.
 video_queue_depth: A gauge to track the number of videos waiting in a processing queue.
 video_processing_duration_seconds: A histogram that records the distribution of video processing durations. This metric also provides a _count and _sum for the total number of processed videos and total processing time, respectively.

DCGM Exporter Metrics (nvidia-dcgm-exporter)
The configuration also references a dcgm-exporter which provides a wide range of GPU metrics collected by the NVIDIA Data Center GPU Manager (DCGM). The PodMonitoring configurations show that metrics matching the regex dcgm_.* and DCGM.* are being scraped. This means you can also extract detailed data about the GPUs, including:

 dcgm_gpu_utilization: A gauge for overall GPU utilization.
 dcgm_gpu_temperature: The current temperature of the GPU.
 dcgm_gpu_power_usage: The power consumption of the GPU.
 dcgm_gpu_memory_usage: The amount of GPU memory being used.
 dcgm_gpu_fan_speed: The speed of the GPU's fan.

All these metrics are labeled with various metadata like gpu_id, pod, container, namespace, and node to provide context and allow for filtering and aggregation in monitoring systems like Prometheus or Google Cloud Managed Service for Prometheus (GMP).
