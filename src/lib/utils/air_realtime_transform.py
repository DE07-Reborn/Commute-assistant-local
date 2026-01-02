from datetime import datetime
from zoneinfo import ZoneInfo

def safe_int(value):
    if value in (None, "-", ""):
        return None
    try:
        return int(value.strip())
    except ValueError:
        return None

def transform_realtime(raw_data):
    # 실시간 대기질 데이터에서 필요한 컬럼만 추출
    transformed_data = []

    for item in raw_data['response']['body']['items']:
        data = {
            "station_code": safe_int(item.get("stationCode")),
            "sido_name": item.get("sidoName"),
            "station_name": item.get("stationName"),
            "pm25": safe_int(item.get("pm25Value")),
            "pm10": safe_int(item.get("pm10Value")),
            "pm25_flag": item.get("pm25Flag"),
            "pm10_flag": item.get("pm10Flag"),
            "data_time": item.get("dataTime"),
            "storage_time": datetime.now(ZoneInfo("Asia/Seoul")).isoformat(),
        }

        transformed_data.append(data)
    
    return transformed_data
