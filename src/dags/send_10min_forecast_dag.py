from airflow import DAG
from airflow.operators.python import PythonOperator

from utils.data_api_utils import Data_api_collector
from utils.kafka_utils import Kafka_producer_utils
from utils.preprocessing_utils import Preprocessing
from utils.database_utils import Database_utils
from utils.s3_utils import S3_utils
import pendulum
import logging
from collections import defaultdict
from datetime import timedelta

def request_and_send_api(**context):
    """
        Request 10min weather data from data.go.kr
        Request api for each location under coordinate (px, py)
        Then send to kafka topic : 10min_forecast_raw
    """
    execution_date = context['logical_date']
    processor = Preprocessing()
    db_utils = Database_utils()
    kafka_producer = Kafka_producer_utils()
    
    ymd, hm = processor.split_time_context(execution_date)
    ymd = processor.split_ymd(ymd)
    api_collector = Data_api_collector(ymd, hm)

    address_list = db_utils.get_unique_address()
    logging.info(address_list)
    df = S3_utils(ymd, hm).read_address()

    sent_count = 0
    dic = defaultdict(list)
    for address in address_list:
        address1, address2 = address.split()
        nx, ny = processor.match_coordinates(df, address1, address2)
        key = f'{nx}_{ny}'
        dic[key].append(address)

    for key, addresses in dic.items():
        nx, ny = key.split('_')
        _json = api_collector.request_getUltraSrtFcst_api(nx, ny)

        message = {
            'raw_json' : _json,
            'base_time' : _json['response']['body']['items']['item'][0]['baseTime'],
            'coord_id' : key,
            'addresses' : addresses
        }

        kafka_producer.send_to_kafka(
            '10min_forecast_raw', key, message
        )

        sent_count += 1

        

    kafka_producer.close_kafka()
    logging.info(f'Sent {sent_count} weather records to kafka')
    




# DAG Init
# This DAG runs every 10 minutes
KST = pendulum.timezone("Asia/Seoul")
with DAG(
    dag_id = 'send_10min_forecast_to_kafka',
    start_date=pendulum.datetime(2025, 1, 1, 0, 0, tz=KST),
    schedule_interval="0/10 * * * *",
    catchup = False,
    max_active_runs=1,
    tags=["10minutes", "Forecast", "kafka"],
    default_args={
        'retries' : 2,
        'retry_delay' : timedelta(seconds=30)
    },
) as dag:
    
    # Request API then store metadata into S3 by csv
    send_forecast_kafka = PythonOperator(
        task_id = 'request_api_and_send',
        python_callable = request_and_send_api,
    )

    send_forecast_kafka
