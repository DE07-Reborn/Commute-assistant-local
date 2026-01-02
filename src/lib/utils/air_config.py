import os

class Settings:
    # AWS 관련 설정
    AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
    AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
    AWS_S3_BUCKET = os.getenv("AWS_S3_BUCKET")
    AWS_REGION = os.getenv("AWS_REGION")

    # API 관련 설정
    AIR_REALTIME_API_URL = os.getenv("AIR_REALTIME_API_URL")
    AIR_FORECAST_API_URL = os.getenv("AIR_FORECAST_API_URL")
    AIR_API_KEY = os.getenv("AIR_API_KEY")
    
    # 시도 리스트 설정
    SIDO_LIST = [
        "서울", "부산", "대구", "인천", "광주", "대전", "울산",
        "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주", "세종"
    ]

    KAFKA_BOOTSTRAP_SERVERS = os.getenv(
        "KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"
    )
    KAFKA_TOPIC_REALTIME = os.getenv("KAFKA_TOPIC_REALTIME", "air-quality-realtime")
    KAFKA_TOPIC_FORECAST = os.getenv("KAFKA_TOPIC_FORECAST", "air-quality-forecast")

settings = Settings()