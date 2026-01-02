import json
import re
from datetime import datetime
from zoneinfo import ZoneInfo
import boto3
from utils.air_config import settings


def save_raw_to_s3(
    raw_data: dict,
):

    # S3 client 생성
    s3 = boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    )

    # 측정 시각 기준 파티셔닝
    data_time = raw_data["response"]["body"]["items"][0].get("dataTime")
    nm = re.match(r"(\d{4}-\d{2}-\d{2})\s+(\d{2})시", data_time)
    data_time_nm = f"{nm.group(1)}_{nm.group(2)}-00"
    run_ts = datetime.now(ZoneInfo("Asia/Seoul")).strftime("%Y%m%d_%H%M%S")

    key = (
        f"air-api/raw/forecast/"
        f"dataTime={data_time_nm}/"
        f"{run_ts}.json"
    )

    s3.put_object(
        Bucket=settings.AWS_S3_BUCKET,
        Key=key,
        Body=json.dumps(raw_data, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )

    return key