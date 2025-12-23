from kafka import KafkaProducer
import json
import logging


class Kafka_producer_utils:
    """
        Kafka util for airflow
    """

    def __init__(self):
        self.producer = KafkaProducer(
            bootstrap_servers="kafka:9092",
            api_version=(3, 6, 0),
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            key_serializer=lambda v: v.encode("utf-8"),
            acks="all",
            retries=3,
            linger_ms=50,
            batch_size=16384, 
            buffer_memory=33554432,  # 32MB
            request_timeout_ms=30000, # 30sec
            max_in_flight_requests_per_connection=5,
        )


    def send_to_kafka(self, topic :str, key:str, message):
        """
            let Kafka to send message to target
            param
                target : topic target
                key : key value of message
                message : message
        """
        try:
            self.producer.send(
                topic=topic,
                key=key,
                value=message
            )
            
        except Exception as e:
            logging.error(f"Error sending message to Kafka: {e}")
            raise


    def close_kafka(self):
        """
            Close conection to kafka when Airflow task ends
        """
        self.producer.flush()
        self.producer.close()
        logging.info("Kafka producer closed")