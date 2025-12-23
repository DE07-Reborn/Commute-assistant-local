import json
from datetime import datetime
import boto3
from utils.air_realtime_config import settings


def save_raw_to_s3(
    raw_data: dict,
    sido_name: str,
):
    """
    실시간 대기질 API 원본 데이터를 S3에 저장
    """

    # S3 client 생성
    s3 = boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    )

    # 측정 시각 기준 파티셔닝
    data_time = raw_data["response"]["body"]["items"][0].get("dataTime")
    dt = datetime.strptime(data_time, "%Y-%m-%d %H:%M")

    key = (
        f"air-quality/raw/"
        f"sido={sido_name}/"
        f"year={dt.year}/"
        f"month={dt.month:02d}/"
        f"day={dt.day:02d}/"
        f"hour={dt.hour:02d}.json"
    )

    s3.put_object(
        Bucket=settings.AWS_S3_BUCKET,
        Key=key,
        Body=json.dumps(raw_data, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )

    return key
