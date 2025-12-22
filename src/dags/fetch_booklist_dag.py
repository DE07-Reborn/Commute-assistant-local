from airflow import DAG
from airflow.operators.python import PythonOperator
import pandas as pd
from datetime import datetime, timezone

from utils.aladin_api_utils import aladin_api_utils
from utils.booklist_preprocess_utils import booklist_preprocess_utils
from utils.basic_s3_utils import Basic_s3_utils

def run_weekly_aladin_bestseller(**context):
    
    exec_date = context["logical_date"]
    date_str = exec_date.strftime("%Y%m%d")
    
    # 유틸 객체 생성
    aladin = aladin_api_utils()
    preprocess = booklist_preprocess_utils()
    s3 = Basic_s3_utils()    
    
    # 실제 수집 최대치
    MAX_RESULTS = 100   # 한 페이지 당 권수
    TOTAL_START = 20    # 페이지
    
    # paging으로 API 호출
    dfs = []
    for start in range(1, TOTAL_START + 1):
        df = aladin.fetch_bestseller(start=start, max_results=MAX_RESULTS)
        print(f"start={start}, rows={len(df)}")
        
        if df.empty:
            break
        
        dfs.append(df)
        
    if not dfs:
        print("No data collected")
        return
    
    # 전체 DataFrame 합치기
    all_df = pd.concat(dfs, ignore_index=True)
    
    # ISBN 기준 중복 제거
    if "isbn13" in all_df.columns:
        all_df = all_df.drop_duplicates(subset=["isbn13"])
    
    # 전처리
    processed_df = preprocess.preprocess_bestseller(all_df)
    
    processed_df = processed_df[processed_df["genre"].notnull()]
    
    if processed_df.empty:
        print("No data after preprocessing")
        return
    
    # 장르별 저장
    for genre_key, grouped_df in processed_df.groupby("genre"):
        if "bestRank" in grouped_df.columns:
            grouped_df = grouped_df.sort_values("bestRank")
        
        grouped_df = grouped_df.head(100)
        
        s3.upload(
            data=grouped_df,
            path=f"BookList/{genre_key}",
            file_name=f"{genre_key}_{date_str}",
            format="parquet",
        )
        
        print(f"Uploaded genre_key={genre_key} with rows={len(grouped_df)}")

# DAG 실행
with DAG(
    dag_id="booklist_to_s3",
    start_date=datetime(2025, 12, 1, tzinfo=timezone.utc),
    schedule_interval="@weekly",
    catchup=False,
    tags=["aladin", "bestseller", "meta", "weekly"],
) as dag:
    
    run_pipeline = PythonOperator(
        task_id="run_weekly_aladin_bestseller",
        python_callable=run_weekly_aladin_bestseller,
    )
    
    run_pipeline