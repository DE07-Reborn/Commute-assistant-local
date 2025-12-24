import boto3
import pandas as pd
import redis
from fastapi import FastAPI, HTTPException
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

    # apply 

    if data is None:
        raise HTTPException(status_code=404, detail=f'No data for station {stn_id}')

    return {
        'stn_nm' : station['지역'],
        'weather' : data,
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

    data_1 = json.loads(data_1)
    data_2 = json.loads(data_2)

    if data_1 is None:
        raise HTTPException(status_code=404, detail=f'No data for station {address_1}')
    if data_2 is None:
        raise HTTPException(status_code=404, detail=f'No data for station {address_2}')

    return {
        'home_address' : address_1.split(':')[1],
        'value_1' : data_1,
        'work_address' : address_2.split(':')[1],
        'value_2' : data_2,
    }



@app.get("/air")
def get_air(home_address, work_address):
    """
        Request Redis to send air pollute (fine dust) information within 30 minutes updates
        param
            home_address : User's home address
            work_address : User's work address
    """
    address_1 = f"forecast:{' '.join(home_address.split()[:2])}"
    address_2 = f"forecast:{' '.join(work_address.split()[:2])}"

    data_1 = redis_client.get(address_1)
    data_2 = redis_client.get(address_2)

    data_1 = json.loads(data_1)
    data_2 = json.loads(data_2)

    if data_1 is None:
        raise HTTPException(status_code=404, detail=f'No data for station {address_1}')
    if data_2 is None:
        raise HTTPException(status_code=404, detail=f'No data for station {address_2}')

    return {
        'home_address' : address_1.split(':')[1],
        'value_1' : data_1,
        'work_address' : address_2.split(':')[1],
        'value_2' : data_2,
    }
