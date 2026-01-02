import requests
from datetime import datetime
from zoneinfo import ZoneInfo
from utils.air_config import settings

def extract_forecast():
    search_date = datetime.now(ZoneInfo("Asia/Seoul")).strftime("%Y-%m-%d")
    
    # API 호출에 필요한 파라미터 설정
    params = {
        "serviceKey": settings.AIR_API_KEY,
        "returnType": "json",
        "numOfRows": 100,
        "pageNo": 1,
        "searchDate": search_date,
    }

    # API 호출
    resp = requests.get(settings.AIR_FORECAST_API_URL, params=params, timeout=10) 
    resp.raise_for_status()
    return resp.json()
