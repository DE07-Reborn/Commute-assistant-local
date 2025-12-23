import boto3
import pandas as pd
import redis
from fastapi import FastAPI, HTTPException
from datetime import datetime, date
import io
import os
from io import StringIO
import math
import json

app = FastAPI(title='Service API')

redis_host = os.getenv("REDIS_HOST")
redis_port = os.getenv("REDIS_PORT")
bucket = os.getenv('AWS_S3_BUCKET')

redis_client = redis.Redis(
    host=redis_host,
    port=redis_port,
    decode_responses=True
)
s3 = boto3.client('s3')
stations = []
music_df = None


# Methods
def load_stations_metadata():
    global stations
    obj = s3.get_object(
        Bucket=bucket,
        Key="stn-metadata/metadata.csv"
    )
    body = obj["Body"].read().decode("utf-8")
    df = pd.read_csv(StringIO(body))

    stations = df.to_dict("records")


def load_music_metadata():
    global music_df
    obj = s3.get_object(
        Bucket=bucket,
        Key="music/music_classified.parquet"
    )

    body = obj["Body"].read()
    music_df = pd.read_parquet(io.BytesIO(body))


# Haversine으로 거리 계산
def haversine(lat1, lon1, lat2, lon2):
    R = 6371 # radius(Earth)

    # Conver to Radian
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad

    a = math.sin(dlat / 2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    distance = R * c
    return distance


# Find nearest station
def find_nearest_stn(lat, lon):
    smallest = float('inf')
    matched = None

    for row in stations:
        d = haversine(float(lat), float(lon), float(row['위도']), float(row['경도']))
        if d < smallest:
            smallest = d
            matched = row
    return matched
    

def recomendation_music(data):
    time = data['obs_time']
    month = int(time[4:6])
    day = int(time[6:8])
    hour = int(time[8:10])

    season = get_season(month)
    time_category = get_time_category(hour)
    weather_category = get_weather_category(data, season, time_category, month, day)

    weather_code = f'{season}-{time_category}-{weather_category}'

    df_with_code = music_df[music_df['weather_code'] == weather_code]
    df_parsed = df_with_code[['artists', 'album_name','track_name']]
    return df_parsed.iloc[:10].to_dict(orient="records")

    
def get_season(month):
    """
        Get season by month : 봄 여름 가을 겨울
    """
    if 3 <= month <= 5:
        return '봄'
    elif 6 <= month <= 8:
        return '여름'
    elif 9 <= month <= 11:
        return '가을'

    return '겨울'


def get_time_category(hour):
    """
        Get time category : 새벽 오전 오후 밤
    """
    if 0 <= hour <= 6:
        return '새벽'
    elif 7 <= hour <= 11:
        return '오전'
    elif 12 <= hour <= 17:
        return '오후'
    return '밤'

def get_weather_category(data , season, time_category, month, day):
    """
        Distribute weather category based on season, time category and time
        param
            data : data from redis
            season : in 봄, 여름, 가을, 겨울
            time_category : in 새벽, 오전, 오후, 밤 
            month : month (int)
            day : day (int)
    """

    wc = data['wc']
    ta = data['ta']

    if wc in (70, 71, 72, 73, 74, 75, 76, 77, 78, 79):
        return '눈'
    elif wc in (50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 
                62, 63, 64, 65, 66, 67, 68, 69, 80, 81, 82, 83, 84, 
                85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99):
        return '비'
    elif ((season == '여름' and ta >= 30 and time_category in ('오전', '오후')) or 
        (season == '여름' and ta >= 25 and time_category in ('새벽', '밤'))):
        return '더위'
    elif data['sky'] == 5 : 
        return '흐림'
    elif (
        (2, 25) <= (month, day) <= (4, 5)
        or
        (8, 25) <= (month, day) <= (10, 5)
    ):
        return "환절기"
    elif (
        (time_category in ('오전', '오후') and 20 <= ta <= 26) or
        (time_category in ('밤') and 18 <= ta <= 22) or
        (time_category in ('새벽') and 15 <= ta <= 20)
    ):
        return '선선'
    else:
        return '화창'
    


def preprocessing_weather(data):
    '''
        convert value in data to integer and parse null to value
    '''
    try:
        return {
            **data,
            "wc": int(data.get("wc") or -99),
            "ta": float(data.get("ta") or 0.0),
            "sky": int(data.get("sky") or 0),
        }
    except ValueError:
        raise HTTPException(
            status_code=500,
            detail=f"Invalid weather data in Redis: {data}"
        )



# API main
@app.on_event('startup')
def startup_event():
    load_stations_metadata()
    load_music_metadata()


@app.get("/weather")
def get_weather(lat, lon):
    """
        Find nearest Station ID and its information to get weather
        information then return all 
        param
            lat : live latitude from app
            lon : live longitude from app
    """
    # get nearest station
    station = find_nearest_stn(lat, lon)
    stn_id = station['STN_ID']

    # Request Redis the info 
    key = f'kma-stn:{stn_id}'
    data = redis_client.hgetall(key)
    data = preprocessing_weather(data)
    music_list = recomendation_music(data)

    # apply 

    if data is None:
        raise HTTPException(status_code=404, detail=f'No data for station {stn_id}')

    return {
        'stn_nm' : station['지역'],
        'weather' : data,
        'music_list' : music_list
    }



@app.get("/forecast")
def get_forecast(home_address, work_address):
    """
        Request Redis to get forecast information of addresses
        param
            home_address : User's home address
            work_address : User's work address
    """
    address_1 = f"forecast:{' '.join(home_address.split()[:2])}"
    address_2 = f"forecast:{' '.join(work_address.split()[:2])}"

    data_1 = redis_client.get(address_1)
    data_2 = redis_client.get(address_2)

    if data_1 is None:
        raise HTTPException(status_code=404, detail=f'No data for station {address_1}')
    if data_2 is None:
        raise HTTPException(status_code=404, detail=f'No data for station {address_2}')

    return {
        'home_address' : address_1,
        'value_1' : json.loads(data_1),
        'work_address' : address_2,
        'value_2' : json.loads(data_2)
    }
