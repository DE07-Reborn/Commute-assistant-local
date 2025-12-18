from airflow import DAG
from airflow.operators.python import PythonOperator

from utils.kma_api_tool_utils import Kma_api_collector
from utils.kafka_utils import Kafka_producer_utils

import pendulum
import logging
from datetime import timedelta

def request_and_send_api():
    """
        Request hourly weather data from kma
        Extract only data and send it to Kafka Topic
    """
    
    # Initialize Kma api collector with execution date
    kma_collector = Kma_api_collector()
    kafka_producer = Kafka_producer_utils()

    text = kma_collector.request_live_weather()

    sent_count = 0

    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        splited = line.split()
        obs_time = splited[0]
        stn_id = splited[1]

        message = {
            'raw_line' : line,
            'obs_time' : obs_time,
            'stn_id' : stn_id,
        }
        
        kafka_producer.send_to_kafka(
            'hourly_weather_raw', stn_id, message
        )
        
        sent_count += 1

    kafka_producer.close_kafka()
    logging.info(f'Sent {sent_count} weather records to kafka')




# DAG Init
# This DAG runs every hour
KST = pendulum.timezone("Asia/Seoul")
with DAG(
    dag_id = 'send_hourly_weather_to_kafka',
    start_date=pendulum.datetime(2025, 1, 1, 0, 0, tz=KST),
    schedule_interval="5 * * * *",
    catchup = False,
    max_active_runs=1,
    tags=["Hourly", "Weather", "kafka"],
    default_args={
        'retries' : 2,
        'retry_delay' : timedelta(seconds=30)
    },
) as dag:
    
    # Request API then store metadata into S3 by csv
    send_weather_kafka = PythonOperator(
        task_id = 'request_api_and_send',
        python_callable = request_and_send_api,
    )

    send_weather_kafka
