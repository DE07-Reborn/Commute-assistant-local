import re
from datetime import datetime
from zoneinfo import ZoneInfo

def normalize_data_time(value: str):
    if not value:
        return None
    m = re.match(r"(\d{4}-\d{2}-\d{2})\s+(\d{2})시", value)
    if not m:
        return None
    return f"{m.group(1)} {m.group(2)}:00"

def transform_forecast(raw_data):
    transformed_data = []

    for item in raw_data['response']['body']['items']:
        data = {
            "inform_code": item.get("informCode"),
            "inform_grade": item.get("informGrade"),
            "inform_data": item.get("informData"),
            "data_time": normalize_data_time(item.get("dataTime")),
            "storage_time": datetime.now(ZoneInfo("Asia/Seoul")).isoformat(),
        }

        transformed_data.append(data)
    
    return transformed_data