from airflow import DAG
from airflow.decorators import task
from airflow.utils.task_group import TaskGroup
from datetime import datetime, timedelta

from utils.air_realtime_extract import extract_realtime
from utils.air_realtime_transform import transform_realtime
from utils.air_realtime_load_s3 import save_raw_to_s3
from utils.air_realtime_kafka_producer import KafkaProducerUtils
from utils.air_realtime_config import settings

# ---------------------------
# 기본 DAG 설정
# ---------------------------
default_args = {
    "owner": "airflow",
    "retries": 3,
    "retry_delay": timedelta(minutes=1),
}

with DAG(
    dag_id="air_quality_realtime_collect",
    start_date=datetime(2025, 1, 1),
    schedule_interval="15 * * * *",
    catchup=False,
    default_args=default_args,
    tags=["air-quality", "realtime"],
) as dag:

    # ---------------------------
    # 시도별 TaskGroup
    # ---------------------------
    for sido in settings.SIDO_LIST:

        with TaskGroup(group_id=f"sido_{sido}") as tg:

            @task(task_id="extract")
            def extract(sido_name: str):
                return extract_realtime(sido_name)

            @task(task_id="save_raw_s3")
            def save_raw(raw_data: dict, sido_name: str):
                save_raw_to_s3(raw_data, sido_name)

            @task(task_id="transform_for_kafka")
            def transform(raw_data: dict):
                return transform_realtime(raw_data)

            @task(task_id="publish_kafka")
            def publish(transformed: list[dict]):
                producer = KafkaProducerUtils()
                for record in transformed:
                    key = f"{record['sido_name']}|{record['station_name']}|{record['data_time']}"
                    producer.send(
                        topic=settings.KAFKA_TOPIC_REALTIME,
                        key=key,
                        message=record,
                    )
                producer.close()

            # task flow
            raw = extract(sido)
            save_raw(raw, sido)
            transformed = transform(raw)
            publish(transformed)

        tg