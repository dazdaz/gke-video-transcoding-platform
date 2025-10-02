# batch-aggregator.py
import os
import asyncio
import json
import time
from typing import List, Dict
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Conditional imports with error handling
try:
    import pika
    RABBITMQ_AVAILABLE = True
except ImportError:
    logger.warning("pika not available, RabbitMQ functionality disabled")
    RABBITMQ_AVAILABLE = False

try:
    from google.cloud import storage
    GCS_AVAILABLE = True
except ImportError:
    logger.warning("google-cloud-storage not available, GCS functionality disabled")
    GCS_AVAILABLE = False

try:
    from redis import Redis
    REDIS_AVAILABLE = True
except ImportError:
    logger.warning("redis not available, Redis functionality disabled")
    REDIS_AVAILABLE = False

try:
    from prometheus_client import Counter, Histogram, Gauge, start_http_server
    METRICS_AVAILABLE = True
except ImportError:
    logger.warning("prometheus_client not available, metrics disabled")
    METRICS_AVAILABLE = False

# Metrics (only if available)
if METRICS_AVAILABLE:
    batches_created = Counter('batches_created_total', 'Total number of batches created')
    batch_size_histogram = Histogram('batch_size', 'Size of batches created')
    queue_depth = Gauge('aggregator_queue_depth', 'Current queue depth')

class BatchAggregator:
    def __init__(self):
        self.batch_size = int(os.environ.get('BATCH_SIZE', '50'))
        self.batch_timeout = int(os.environ.get('BATCH_TIMEOUT_SECONDS', '2'))
        self.local_cache_path = os.environ.get('LOCAL_CACHE_PATH', '/cache')
        self.gcs_bucket_name = os.environ.get('GCS_BUCKET_NAME', 'vid-transcode')
        self.current_batch = []
        self.last_batch_time = time.time()

        # Initialize connections with retry
        self.rabbit_connection = None
        self.channel = None
        self.gcs_client = None
        self.gcs_bucket = None
        self.redis_client = None

        self.initialize_connections()

    def initialize_connections(self):
        """Initialize connections with retry logic"""
        max_retries = 5
        retry_count = 0

        while retry_count < max_retries:
            try:
                # RabbitMQ connection with credentials
                if RABBITMQ_AVAILABLE:
                    logger.info("Connecting to RabbitMQ...")

                    # Get credentials from environment variables
                    rabbitmq_user = os.environ.get('RABBITMQ_USER', 'guest')
                    rabbitmq_pass = os.environ.get('RABBITMQ_PASS', 'guest')
                    rabbitmq_host = os.environ.get('RABBITMQ_HOST', 'rabbitmq-service')

                    credentials = pika.PlainCredentials(rabbitmq_user, rabbitmq_pass)

                    self.rabbit_connection = pika.BlockingConnection(
                        pika.ConnectionParameters(
                            host=rabbitmq_host,
                            credentials=credentials,
                            connection_attempts=3,
                            retry_delay=5
                        )
                    )
                    self.channel = self.rabbit_connection.channel()
                    self.channel.queue_declare(queue='video-compression', durable=True)
                    self.channel.queue_declare(queue='video-batches', durable=True)
                    logger.info("RabbitMQ connected successfully")

                # GCS client
                if GCS_AVAILABLE:
                    logger.info("Initializing GCS client...")
                    # GCS client will use Application Default Credentials (ADC)
                    # In GKE, this will use the service account attached to the pod
                    self.gcs_client = storage.Client()
                    
                    # Get or create bucket
                    try:
                        self.gcs_bucket = self.gcs_client.bucket(self.gcs_bucket_name)
                        # Check if bucket exists
                        if not self.gcs_bucket.exists():
                            logger.info(f"Creating GCS bucket: {self.gcs_bucket_name}")
                            self.gcs_bucket = self.gcs_client.create_bucket(
                                self.gcs_bucket_name,
                                location=os.environ.get('GCS_LOCATION', 'US')
                            )
                    except Exception as e:
                        logger.warning(f"Could not verify/create bucket: {e}")
                        # Try to use bucket anyway
                        self.gcs_bucket = self.gcs_client.bucket(self.gcs_bucket_name)
                    
                    logger.info(f"GCS client initialized with bucket: {self.gcs_bucket_name}")

                # Redis for caching
                if REDIS_AVAILABLE:
                    logger.info("Connecting to Redis...")
                    self.redis_client = Redis(
                        host=os.environ.get('REDIS_HOST', 'redis-service'),
                        port=6379,
                        decode_responses=True,
                        socket_connect_timeout=5,
                        retry_on_timeout=True
                    )
                    self.redis_client.ping()
                    logger.info("Redis connected successfully")

                break

            except Exception as e:
                retry_count += 1
                logger.error(f"Failed to initialize connections (attempt {retry_count}/{max_retries}): {e}")
                if retry_count < max_retries:
                    time.sleep(10)
                else:
                    logger.error("Max retries reached. Exiting.")
                    sys.exit(1)

    def list_gcs_videos(self, prefix=''):
        """List video files in GCS bucket"""
        if not self.gcs_bucket:
            logger.warning("GCS bucket not initialized")
            return []
        
        try:
            video_extensions = ('.mp4', '.avi', '.mov', '.mkv', '.webm', '.flv')
            videos = []
            
            blobs = self.gcs_bucket.list_blobs(prefix=prefix)
            for blob in blobs:
                if blob.name.lower().endswith(video_extensions):
                    videos.append({
                        'name': blob.name,
                        'size': blob.size,
                        'created': blob.time_created.isoformat() if blob.time_created else None,
                        'updated': blob.updated.isoformat() if blob.updated else None,
                        'gcs_uri': f'gs://{self.gcs_bucket_name}/{blob.name}'
                    })
            
            logger.info(f"Found {len(videos)} videos in GCS bucket")
            return videos
            
        except Exception as e:
            logger.error(f"Error listing GCS videos: {e}")
            return []

    async def start(self):
        """Start the batch aggregator"""
        if METRICS_AVAILABLE:
            start_http_server(8080)  # Metrics endpoint
            logger.info("Metrics server started on port 8080")

        # Start batch timeout checker
        asyncio.create_task(self.batch_timeout_checker())

        if self.channel:
            # Start consuming messages
            self.channel.basic_qos(prefetch_count=self.batch_size * 2)
            self.channel.basic_consume(
                queue='video-compression',
                on_message_callback=self.on_message,
                auto_ack=False
            )

            logger.info("Batch aggregator started")
            try:
                self.channel.start_consuming()
            except KeyboardInterrupt:
                logger.info("Stopping batch aggregator...")
                self.channel.stop_consuming()
                self.rabbit_connection.close()
        else:
            logger.error("No RabbitMQ connection available")
            # Keep the service running for health checks
            while True:
                await asyncio.sleep(60)

    def on_message(self, channel, method, properties, body):
        """Handle incoming message"""
        try:
            message = json.loads(body)
            
            # If message contains GCS path, validate it exists
            if 'gcs_uri' in message or 'video_path' in message:
                video_path = message.get('gcs_uri') or message.get('video_path')
                if video_path and video_path.startswith('gs://'):
                    # Extract blob name from GCS URI
                    blob_name = video_path.replace(f'gs://{self.gcs_bucket_name}/', '')
                    if self.gcs_bucket:
                        blob = self.gcs_bucket.blob(blob_name)
                        if not blob.exists():
                            logger.warning(f"Video not found in GCS: {video_path}")
            
            self.current_batch.append({
                'message': message,
                'delivery_tag': method.delivery_tag
            })

            if METRICS_AVAILABLE:
                queue_depth.set(len(self.current_batch))

            if len(self.current_batch) >= self.batch_size:
                self.flush_batch()

        except Exception as e:
            logger.error(f"Error processing message: {e}")
            channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)

    def flush_batch(self):
        """Flush current batch to processing queue"""
        if not self.current_batch:
            return

        batch_id = f"batch_{int(time.time() * 1000)}"
        batch_data = {
            'batch_id': batch_id,
            'videos': [item['message'] for item in self.current_batch],
            'timestamp': time.time(),
            'gcs_bucket': self.gcs_bucket_name
        }

        # Store batch metadata in Redis if available
        if self.redis_client:
            try:
                self.redis_client.setex(
                    batch_id,
                    3600,  # 1 hour TTL
                    json.dumps(batch_data)
                )
            except Exception as e:
                logger.error(f"Failed to store batch in Redis: {e}")

        # Optionally store batch metadata in GCS
        if self.gcs_bucket:
            try:
                batch_blob = self.gcs_bucket.blob(f'batches/{batch_id}.json')
                batch_blob.upload_from_string(
                    json.dumps(batch_data),
                    content_type='application/json'
                )
                logger.info(f"Stored batch metadata in GCS: batches/{batch_id}.json")
            except Exception as e:
                logger.error(f"Failed to store batch metadata in GCS: {e}")

        # Send batch to processing queue
        if self.channel:
            self.channel.basic_publish(
                exchange='',
                routing_key='video-batches',
                body=json.dumps({'batch_id': batch_id, 'gcs_bucket': self.gcs_bucket_name}),
                properties=pika.BasicProperties(delivery_mode=2)
            )

            # Acknowledge original messages
            for item in self.current_batch:
                self.channel.basic_ack(delivery_tag=item['delivery_tag'])

        # Update metrics
        if METRICS_AVAILABLE:
            batches_created.inc()
            batch_size_histogram.observe(len(self.current_batch))

        logger.info(f"Flushed batch {batch_id} with {len(self.current_batch)} videos")

        self.current_batch = []
        self.last_batch_time = time.time()

        if METRICS_AVAILABLE:
            queue_depth.set(0)

    async def batch_timeout_checker(self):
        """Check for batch timeout and flush if needed"""
        while True:
            await asyncio.sleep(1)
            if self.current_batch and (time.time() - self.last_batch_time) > self.batch_timeout:
                self.flush_batch()

if __name__ == '__main__':
    aggregator = BatchAggregator()
    asyncio.run(aggregator.start())
