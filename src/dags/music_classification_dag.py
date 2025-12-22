from datetime import datetime, timedelta
from io import StringIO
import pandas as pd

from airflow import DAG
from airflow.operators.python import PythonOperator
from utils.basic_s3_utils import Basic_s3_utils

S3_BUCKET = "commute-test-bucket"
S3_PATH = "raw_data/music"
S3_MUSIC_DATA = "music_origin_data"
S3_MUSIC_RESULT_DATA = "music_classified"
S3_WEATHER_CODE_DATA = "weather_code_table"

def bring_data_from_s3(bucket_path, music_data, weather_code_data, **context):
    try:
        s3 = Basic_s3_utils()
        music_data_path = bucket_path + '/' + music_data
        music_df = s3.read(path=music_data_path)

        weather_code_data_path = bucket_path + '/' + weather_code_data
        weather_code_df = s3.read(path=weather_code_data_path, input_type='csv')
    except Exception as e:
        raise RuntimeError(f"S3에서 데이터를 읽는 중 오류 발생: {e}")

    if music_df is None or music_df.empty:
        raise ValueError("S3에서 가져온 음악 데이터가 비어 있습니다.")
    elif weather_code_df is None or weather_code_df.empty:
        raise ValueError("S3에서 가져온 날씨 코드 데이터가 비어 있습니다.")

    required_cols = {"tempo", "energy", "popularity"}
    if not required_cols.issubset(music_df.columns):
        raise KeyError(f"필수 컬럼 {required_cols}이 누락되었습니다.")

    context['ti'].xcom_push(key="music_df", value=music_df.to_json())
    context['ti'].xcom_push(key="weather_code_df", value=weather_code_df.to_json())

def music_data_classification(**context):
    music_json = context['ti'].xcom_pull(task_ids="bring_data_from_s3", key="music_df")
    music_df = pd.read_json(StringIO(music_json))
    weather_code_json = context['ti'].xcom_pull(task_ids="bring_data_from_s3", key="weather_code_df")
    weather_code_df = pd.read_json(StringIO(weather_code_json))

    # tempo 기준 4개로 분할
    if len(music_df) < 4:
        raise ValueError("tempo 그룹을 나눌 수 있을 만큼 데이터가 충분하지 않습니다.")

    df_sorted = music_df.sort_values('tempo').reset_index(drop=True)
    df_sorted['tempo_group'] = (df_sorted.index // (len(music_df) // 4)) + 1

    # energy 기준 24개씩 분할
    sorted_dfs = {}

    for n in range(1, 5):
        group_df = df_sorted[df_sorted['tempo_group'] == n]

        if len(group_df) < 24:
            raise ValueError(f"tempo 그룹 {n}에서 energy 그룹을 나눌 수 없습니다.")

        sorted_dfs[n] = group_df.sort_values('energy', ascending=False).reset_index(drop=True)
        sorted_dfs[n]['energy_group'] = (sorted_dfs[n].index // (len(sorted_dfs[n]) // 24)) + 1
    
    code_given_music_df = pd.concat(sorted_dfs.values(), ignore_index=True)
    music_code_df = pd.DataFrame(code_given_music_df['tempo_group'].astype(str)+'-'+code_given_music_df['energy_group'].astype(str), columns=['time_code'])
    code_given_music_df['weather_code'] = weather_code_df.merge(music_code_df, on='time_code')['weather_code']

    context['ti'].xcom_push(key="classified_df", value=code_given_music_df.to_json())

def music_classification_result_load(bucket_name, load_path, music_data_result_name, **context):
    classified_json = context['ti'].xcom_pull(task_ids="music_data_classification", key="classified_df")
    df = pd.read_json(StringIO(classified_json)).sort_values(by=['tempo_group', 'energy_group', 'popularity'], ascending=[True, True, False])

    try:
        s3 = Basic_s3_utils(bucket=bucket_name)
        s3.upload(data=df, path=load_path, file_name=music_data_result_name)
    except Exception as e:
        raise RuntimeError(f"S3에 결과 데이터를 업로드하는 중 오류 발생: {e}")


with DAG(
    dag_id="music_classification_dag",
    start_date=datetime(2025, 12, 15),
    schedule_interval="@once",
    catchup=False,
    tags=["s3", "classification", "music"],
    default_args={
        "owner": "airflow",
        "depends_on_past": False,
        "email_on_failure": False,
        "email_on_retry": False,
        "retries": 3,
        "retry_delay": timedelta(seconds=30),
    },
) as dag:
    # 1. S3에서 데이터 가져오기
    bring_data_from_s3_task = PythonOperator(
        task_id="bring_data_from_s3",
        python_callable=bring_data_from_s3,
        op_kwargs={
            "bucket_path": S3_PATH,
            "music_data": S3_MUSIC_DATA,
            "weather_code_data": S3_WEATHER_CODE_DATA
        }
    )

    music_data_classification_task = PythonOperator(
        task_id="music_data_classification",
        python_callable=music_data_classification
    )

    music_classification_result_load_task = PythonOperator(
        task_id="music_classification_result_load",
        python_callable=music_classification_result_load,
        op_kwargs={
            "bucket_name": S3_BUCKET,
            "load_path": S3_PATH,
            "music_data_result_name": S3_MUSIC_RESULT_DATA
        }
    )

    bring_data_from_s3_task >> music_data_classification_task >> music_classification_result_load_task
