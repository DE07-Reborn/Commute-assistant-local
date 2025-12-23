import requests
from utils.config import settings

def extract_realtime(sido_name: str = "서울") -> dict:
    # API 호출에 필요한 파라미터 설정
    params = {
        "serviceKey": settings.AIR_API_KEY,
        "returnType": "json",
        "numOfRows": 100,
        "pageNo": 1,
        "sidoName": sido_name,
        "ver": "1.5",
    }

    # API 호출
    resp = requests.get(settings.AIR_API_URL, params=params, timeout=10) 
    resp.raise_for_status()
    return resp.json()
