from airflow import DAG
from airflow.decorators import task
from datetime import datetime, timedelta

from utils.air_forecast_extract import extract_forecast
from utils.air_forecast_load_s3 import save_raw_to_s3
from utils.air_forecast_transform import transform_forecast
from utils.air_kafka_producer import KafkaProducerUtils
from utils.air_config import settings

default_args = {
    "owner": "airflow",
    "retries": 3,
    "retry_delay": timedelta(seconds=30),
}

with DAG(
    dag_id="air_quality_forecast_collect",
    start_date=datetime(2025, 1, 1),
    schedule_interval="45 5,11,17,23 * * *",
    catchup=False,
    default_args=default_args,
    tags=["air-quality", "forecast"],
) as dag:

    @task(task_id="extract")
    def extract():
        return extract_forecast()

    @task(task_id="save_raw_s3")
    def save_raw(raw_data: dict):
        save_raw_to_s3(raw_data)

    @task(task_id="transform_for_kafka")
    def transform(raw_data: dict):
        return transform_forecast(raw_data)

    @task(task_id="publish_kafka")
    def publish(transformed: list[dict]):
        producer = KafkaProducerUtils()
        for record in transformed:
            key = f"{record['inform_code']}|{record['inform_data']}|{record['data_time']}"
            producer.send(
                topic=settings.KAFKA_TOPIC_FORECAST,
                key=key,
                message=record,
            )
        producer.close()

    raw = extract()
    save_raw(raw)
    transformed = transform(raw)
    publish(transformed)
