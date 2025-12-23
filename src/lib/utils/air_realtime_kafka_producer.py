import json
import logging
from kafka import KafkaProducer
from utils.config import settings

class KafkaProducerUtils:
    def __init__(self):
        self.producer = KafkaProducer(
            bootstrap_servers=settings.KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode("utf-8"),
            key_serializer=lambda v: v.encode("utf-8"),
            acks="all",
            retries=3,
            linger_ms=50,
            batch_size=16384,
            buffer_memory=33554432,
            request_timeout_ms=30000,
        )

    def send(self, topic: str, key: str, message: dict):
        try:
            self.producer.send(topic=topic, key=key, value=message)
        except Exception:
            logging.exception("Kafka send failed")
            raise

    def close(self):
        self.producer.flush()
        self.producer.close()
        logging.info("Kafka producer closed")