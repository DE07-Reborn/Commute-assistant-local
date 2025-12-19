from utils.preprocessing_utils import Preprocessing
from utils.kma_api_tool_utils import Kma_api_collector
from utils.s3_utils import S3_utils

from airflow import DAG
from airflow.operators.python import PythonOperator

from datetime import datetime

# DAG Methods

def request_kma_stn_meta(**context):
    """
        Request KMA API to get STN meta data
        Store pandas dataframe to S3 as csv
    """ 
    execution_date = context['logical_date']

    # Initialize Kma api collector with execution date
    ymd, hm = Preprocessing().split_time_context(execution_date)
    kma_collector = Kma_api_collector()
    df = kma_collector.request_stn_metadata()

    # S3 Connection and save into s3 as csv
    s3_connector = S3_utils(ymd, hm)
    s3_connector.upload_stn_metadata(df)



# DAG Init
# This DAG run every first day of JAN and JULY (interval : 6 months) 
with DAG(
    dag_id = 'Request_STN_Metadata',
    start_date = datetime(2025,12,1),
    schedule_interval="0 0 1 1,7 *",
    catchup = False,
    max_active_runs=1,
    tags=["kma_stn", "metadata", "s3"],
) as dag:
    
    # Request API then store metadata into S3 by csv
    request_and_save_s3 = PythonOperator(
        task_id = 'api_to_s3',
        python_callable = request_kma_stn_meta,
    )

    request_and_save_s3