import boto3
import pandas as pd
import redis
from fastapi import FastAPI, HTTPException
import os
from io import StringIO
import math

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

    if data is None:
        raise HTTPException(status_code=404, detail=f'No data for station {stn_id}')

    return {
        'stn_nm' : station['지역'],
        'weather' : data
    }

