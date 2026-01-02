"""
FastAPI 서버
Redis에서 데이터를 조회하여 Flutter 앱에 제공
Docker 컨테이너에서 실행 가능하도록 환경 변수 사용
"""

from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional
from sqlalchemy.orm import Session
import redis
import json
import os
from datetime import datetime

# 데이터베이스 및 모델 import
from database import engine, get_db, Base
from models import User, UserProfile, UserAddress, Event, Gender
from auth import hash_password, verify_password
from address_service import AddressService

app = FastAPI(title="Commute Assistant API", version="1.0.0")

# 데이터베이스 테이블 생성
@app.on_event("startup")
async def startup_event():
    # 데이터베이스 연결 테스트
    from database import test_connection
    if test_connection():
        try:
            # 테이블이 없으면 생성 (기존 데이터 보존)
            Base.metadata.create_all(bind=engine)
            print("✅ 데이터베이스 테이블 생성 완료")
        except Exception as e:
            print(f"❌ 데이터베이스 테이블 생성 실패: {e}")
            import traceback
            traceback.print_exc()
            # 테이블 스키마 문제일 수 있으므로 재생성 시도
            print("⚠️ 기존 테이블과 스키마 불일치 가능성. 테이블 재생성 시도...")
            try:
                # 개발 환경에서만 사용 (기존 데이터 삭제됨)
                # 프로덕션에서는 마이그레이션 도구 사용 권장
                if os.getenv('ENVIRONMENT') == 'development':
                    Base.metadata.drop_all(bind=engine)
                    Base.metadata.create_all(bind=engine)
                    print("✅ 데이터베이스 테이블 재생성 완료")
            except Exception as recreate_error:
                print(f"❌ 테이블 재생성 실패: {recreate_error}")
    else:
        print("⚠️ 데이터베이스 연결 실패 - 일부 기능이 작동하지 않을 수 있습니다")

# CORS 설정 (Flutter 앱에서 접근 가능하도록)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 프로덕션에서는 특정 도메인으로 제한
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis 연결 (환경 변수 사용)
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'localhost'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    db=int(os.getenv('REDIS_DB', '0')),
    password=os.getenv('REDIS_PASSWORD', None),
    decode_responses=True
)

# 환경 변수로 가져온 Google Maps API 키 (한 번만 정의)
GOOGLE_MAPS_API_KEY = os.getenv('GOOGLE_MAPS_API_KEY', '')

# Google Maps API 서비스
address_service = AddressService(
    api_key=GOOGLE_MAPS_API_KEY
)

# 대지역 리스트 (매칭용)
LARGE_REGIONS = [
    "서울", "부산", "대구", "인천", "광주", "대전", "울산",
    "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주", "세종"
]


# Pydantic 모델
class WeatherInfo(BaseModel):
    temperature: float
    condition: str
    humidity: int
    windSpeed: float
    description: str
    location: Optional[str] = None
    uvIndex: Optional[str] = None
    weatherCategory: Optional[str] = None


class BookInfo(BaseModel):
    title: str
    author: str
    link: Optional[str] = None


class MusicTrack(BaseModel):
    trackName: str
    artists: str
    albumName: str


class UnifiedDataResponse(BaseModel):
    """통합 데이터 응답 모델"""
    weather: WeatherInfo
    book: Optional[BookInfo] = None
    music: list[MusicTrack] = []


# Redis 서비스
class RedisService:
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
    
    def get_unified_data(self, station_id: str) -> Optional[dict]:
        """
        Redis에서 통합 데이터 조회
        하나의 Hash에 날씨, 도서, 음악 데이터가 모두 저장되어 있음
        (기존 Flutter 코드와 동일한 방식)
        """
        key = f"kma-stn:{station_id}"
        
        try:
            # Hash로 저장된 경우 (기존 Flutter 코드와 동일)
            data = self.redis.hgetall(key)
            
            # 디버깅: 키 존재 여부 확인
            if not data or len(data) == 0:
                # 키가 존재하는지 확인
                exists = self.redis.exists(key)
                print(f"Redis 키 '{key}' 존재 여부: {exists}")
                
                # 유사한 키 검색
                pattern = f"kma-stn:*"
                similar_keys = self.redis.keys(pattern)
                print(f"유사한 키들: {similar_keys}")
                
                return None
            
            # 디버깅: 데이터 필드 확인
            print(f"Redis에서 데이터 조회 성공: {key}, 필드 수: {len(data)}")
            print(f"데이터 필드: {list(data.keys())}")
            
            # Redis에서 가져온 값이 모두 문자열이므로, 그대로 반환
            # (Flutter 코드에서도 문자열로 처리)
            return data
        except Exception as e:
            print(f"Redis 데이터 조회 오류: {e}")
            import traceback
            traceback.print_exc()
            raise
    
    def parse_weather_data(self, data: dict) -> dict:
        """날씨 데이터 파싱 (기존 Flutter 코드와 동일한 로직)"""
        # 날씨 카테고리에서 condition 추출
        weather_category = data.get('weather_category', '') or ''
        if '-' in weather_category:
            wc = weather_category.split('-')[-1]
        else:
            wc = weather_category
        
        condition = self._map_weather_condition(wc)
        
        # 문자열을 숫자로 변환 (기존 Flutter 코드와 동일)
        def parse_double(value):
            if value is None:
                return 0.0
            if isinstance(value, (int, float)):
                return float(value)
            if isinstance(value, str):
                try:
                    return float(value)
                except (ValueError, TypeError):
                    return 0.0
            return 0.0
        
        ws = parse_double(data.get('ws', '0'))
        ta = parse_double(data.get('ta', '0'))
        hm = int(parse_double(data.get('hm', '0')))  # hm은 double로 저장되어 있을 수 있음
        
        return {
            'temperature': ta,
            'condition': condition,
            'humidity': hm,
            'windSpeed': ws,
            'description': wc,
            'location': data.get('location', '서울시 강남구'),
            'uvIndex': data.get('uvIndex'),
            'weatherCategory': wc
        }
    
    def parse_book_data(self, data: dict) -> Optional[dict]:
        """도서 데이터 파싱"""
        book_title = data.get('book_title')
        if not book_title or book_title == '':
            return None
        
        return {
            'title': book_title,
            'author': data.get('book_author', '저자 정보 없음'),
            'link': data.get('book_link') if data.get('book_link') else None
        }
    
    def parse_music_data(self, data: dict) -> list[dict]:
        """음악 데이터 파싱 (기존 Flutter 코드와 동일한 로직)"""
        music_data = data.get('music')
        if not music_data:
            return []
        
        music_tracks = []
        
        # JSON 문자열인 경우 (기존 Flutter 코드와 동일)
        if isinstance(music_data, str):
            try:
                # 문자열을 JSON으로 파싱
                music_list = json.loads(music_data)
                if isinstance(music_list, list):
                    for item in music_list:
                        if isinstance(item, dict):
                            # MusicTrack.fromJson과 동일한 로직
                            track = {
                                'trackName': item.get('track_name') or item.get('trackName', ''),
                                'artists': item.get('artists', ''),
                                'albumName': item.get('album_name') or item.get('albumName', '')
                            }
                            music_tracks.append(track)
            except (json.JSONDecodeError, TypeError) as e:
                print(f'음악 데이터 파싱 실패: {e}, music_data: {music_data}')
        
        # 이미 리스트인 경우
        elif isinstance(music_data, list):
            for item in music_data:
                if isinstance(item, dict):
                    music_tracks.append({
                        'trackName': item.get('track_name') or item.get('trackName', ''),
                        'artists': item.get('artists', ''),
                        'albumName': item.get('album_name') or item.get('albumName', '')
                    })
        
        return music_tracks
    
    def _map_weather_condition(self, wc: str) -> str:
        """날씨 카테고리를 condition으로 매핑"""
        wc_lower = wc.lower()
        if '비' in wc_lower or 'rain' in wc_lower:
            return 'rainy'
        elif '눈' in wc_lower or 'snow' in wc_lower:
            return 'snowy'
        elif '흐림' in wc_lower or 'cloud' in wc_lower:
            return 'cloudy'
        elif '맑음' in wc_lower or '화창' in wc_lower or 'sunny' in wc_lower or 'clear' in wc_lower:
            return 'sunny'
        else:
            return 'sunny'  # 기본값


# 의존성 주입
def get_redis_service() -> RedisService:
    return RedisService(redis_client)


# 통합 API 엔드포인트
@app.get("/api/v1/data/{station_id}", response_model=UnifiedDataResponse)
async def get_unified_data(
    station_id: str,
    redis_service: RedisService = Depends(get_redis_service)
):
    """
    통합 데이터 조회
    Redis의 하나의 테이블에서 날씨, 도서, 음악 데이터를 모두 가져옴
    """
    # Redis에서 통합 데이터 조회
    raw_data = redis_service.get_unified_data(station_id)
    
    if not raw_data:
        raise HTTPException(
            status_code=404,
            detail=f"Station {station_id}의 데이터를 찾을 수 없습니다"
        )
    
    # 데이터 파싱 (에러 핸들링 추가)
    try:
        weather_data = redis_service.parse_weather_data(raw_data)
        print(f"날씨 데이터 파싱 성공: {weather_data}")
    except Exception as e:
        print(f"날씨 데이터 파싱 오류: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"날씨 데이터 파싱 중 오류가 발생했습니다: {str(e)}"
        )
    
    try:
        book_data = redis_service.parse_book_data(raw_data)
        print(f"도서 데이터 파싱: {book_data}")
    except Exception as e:
        print(f"도서 데이터 파싱 오류: {e}")
        book_data = None
    
    try:
        music_data = redis_service.parse_music_data(raw_data)
        print(f"음악 데이터 파싱 성공: {len(music_data)}개 트랙")
    except Exception as e:
        print(f"음악 데이터 파싱 오류: {e}")
        music_data = []
    
    return UnifiedDataResponse(
        weather=WeatherInfo(**weather_data),
        book=BookInfo(**book_data) if book_data else None,
        music=[MusicTrack(**track) for track in music_data]
    )


def get_station_coordinates(station_id: str, redis_data: Optional[dict] = None) -> tuple:
    """
    관측소 ID를 기반으로 좌표 반환
    Redis 데이터에서 latitude, longitude를 직접 사용
    """
    # Redis 데이터에서 좌표 추출
    if redis_data:
        try:
            if 'latitude' in redis_data and 'longitude' in redis_data:
                lat = float(redis_data['latitude'])
                lng = float(redis_data['longitude'])
                if lat != 0.0 and lng != 0.0:
                    return (lat, lng)
        except (ValueError, TypeError):
            pass
    
    # 기본값: 서울 좌표
    return (37.5665, 126.9780)

def get_seoul_station_id(redis_service) -> Optional[str]:
    """
    Redis에서 서울 지역 관측소 ID 찾기
    location 필드에 '서울'이 포함된 관측소를 찾음
    """
    try:
        pattern = "kma-stn:*"
        keys = redis_service.redis.keys(pattern)
        
        for key in keys:
            try:
                station_id = key.replace("kma-stn:", "")
                station_data = redis_service.get_unified_data(station_id)
                
                if station_data and 'location' in station_data:
                    location = str(station_data['location']).strip()
                    if '서울' in location:
                        print(f"서울 기본 관측소 발견: {station_id} ({location})")
                        return station_id
            except Exception:
                continue
        
        # 서울 관측소를 찾지 못한 경우 기본값
        print("서울 관측소를 찾지 못해 기본값 사용: 108")
        return "108"
    except Exception as e:
        print(f"서울 관측소 찾기 오류: {e}")
        return "108"  # 기본값


# 좌표 기반 가장 가까운 관측소 찾기
@app.get("/api/v1/weather/nearest-station")
async def get_nearest_station(
    latitude: float,
    longitude: float,
    redis_service: RedisService = Depends(get_redis_service)
):
    """
    좌표를 기반으로 가장 가까운 관측소 ID 찾기
    """
    try:
        # Redis에서 모든 관측소 키 가져오기
        pattern = "kma-stn:*"
        keys = redis_service.redis.keys(pattern)
        
        if not keys:
            # Redis에 키가 없으면 강남구 관측소 반환
            return {
                "station_id": "130",  # 강남구 관측소
                "distance_km": None
            }
        
        nearest_station_id = None
        min_distance = float('inf')
        
        import math
        R = 6371  # 지구 반지름 (km)
        
        # 각 관측소와의 거리 계산
        for key in keys:
            try:
                # 키에서 station_id 추출 (예: "kma-stn:221" -> "221")
                station_id = key.replace("kma-stn:", "")
                
                # Redis에서 해당 관측소 데이터 가져오기 (좌표 확인용)
                station_data = redis_service.get_unified_data(station_id)
                
                # 관측소 좌표 가져오기 (Redis 데이터 우선, 없으면 매핑 테이블)
                station_lat, station_lng = get_station_coordinates(station_id, station_data)
                
                # 거리 계산 (Haversine 공식)
                lat1_rad = math.radians(latitude)
                lat2_rad = math.radians(station_lat)
                delta_lat = math.radians(station_lat - latitude)
                delta_lng = math.radians(station_lng - longitude)
                
                a = math.sin(delta_lat / 2) ** 2 + \
                    math.cos(lat1_rad) * math.cos(lat2_rad) * \
                    math.sin(delta_lng / 2) ** 2
                c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
                distance = R * c
                
                if distance < min_distance:
                    min_distance = distance
                    nearest_station_id = station_id
                    
            except Exception as e:
                # 개별 관측소 처리 중 오류 발생 시 스킵
                print(f"관측소 {station_id} 처리 중 오류: {e}")
                continue
        
        if nearest_station_id is None:
            # 가장 가까운 관측소를 찾지 못한 경우 강남구 좌표로 재시도
            print("관측소를 찾지 못해 강남구 좌표로 재시도합니다.")
            gangnam_lat, gangnam_lng = 37.5172, 127.0473  # 강남구 좌표
            
            # 강남구 좌표로 가장 가까운 관측소 다시 찾기
            for key in keys:
                try:
                    station_id = key.replace("kma-stn:", "")
                    station_data = redis_service.get_unified_data(station_id)
                    station_lat, station_lng = get_station_coordinates(station_id, station_data)
                    
                    import math
                    R = 6371
                    lat1_rad = math.radians(gangnam_lat)
                    lat2_rad = math.radians(station_lat)
                    delta_lat = math.radians(station_lat - gangnam_lat)
                    delta_lng = math.radians(station_lng - gangnam_lng)
                    
                    a = math.sin(delta_lat / 2) ** 2 + \
                        math.cos(lat1_rad) * math.cos(lat2_rad) * \
                        math.sin(delta_lng / 2) ** 2
                    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
                    distance = R * c
                    
                    if distance < min_distance:
                        min_distance = distance
                        nearest_station_id = station_id
                except Exception:
                    continue
            
            # 여전히 찾지 못하면 서울 기본 관측소 사용
            if nearest_station_id is None:
                seoul_id = get_seoul_station_id(redis_service)
                nearest_station_id = seoul_id
                print(f"관측소를 찾지 못해 서울 기본 관측소 사용: {nearest_station_id}")
                min_distance = None
        
        return {
            "station_id": nearest_station_id,
            "distance_km": round(min_distance, 2) if min_distance != float('inf') and min_distance is not None else None
        }
        
    except Exception as e:
        print(f"가장 가까운 관측소 찾기 오류: {e}")
        import traceback
        traceback.print_exc()
        # 오류 발생 시 서울 기본 관측소 반환
        try:
            seoul_id = get_seoul_station_id(redis_service)
        except:
            seoul_id = "108"
        return {
            "station_id": seoul_id,
            "distance_km": None
        }


# 좌표 기반 날씨 조회
@app.get("/api/v1/weather/by-coordinates")
async def get_weather_by_coordinates(
    latitude: float,
    longitude: float,
    redis_service: RedisService = Depends(get_redis_service)
):
    """
    좌표를 기반으로 가장 가까운 관측소의 날씨 데이터 조회
    관측소를 찾을 수 없으면 강남구 좌표로 재시도
    """
    try:
        # 가장 가까운 관측소 찾기
        nearest = await get_nearest_station(latitude, longitude, redis_service)
        station_id = nearest["station_id"]
        
        # 해당 관측소의 날씨 데이터 조회
        raw_data = redis_service.get_unified_data(station_id)
        
        if not raw_data:
            # 데이터가 없으면 서울 기본 관측소로 재시도
            seoul_id = get_seoul_station_id(redis_service)
            print(f"Station {station_id}의 데이터를 찾을 수 없어 서울 기본 관측소({seoul_id})로 재시도합니다.")
            station_id = seoul_id
            raw_data = redis_service.get_unified_data(station_id)
            
            if not raw_data:
                raise HTTPException(
                    status_code=404,
                    detail=f"관측소 데이터를 찾을 수 없습니다"
                )
        
        weather_data = redis_service.parse_weather_data(raw_data)
        return WeatherInfo(**weather_data)
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"좌표 기반 날씨 조회 오류: {e}")
        import traceback
        traceback.print_exc()
        # 오류 발생 시 서울 기본 관측소로 재시도
        try:
            seoul_id = get_seoul_station_id(redis_service)
            raw_data = redis_service.get_unified_data(seoul_id)
            if raw_data:
                weather_data = redis_service.parse_weather_data(raw_data)
                return WeatherInfo(**weather_data)
        except:
            pass
        
        raise HTTPException(
            status_code=500,
            detail=f"날씨 데이터 조회 중 오류가 발생했습니다: {str(e)}"
        )


# 개별 엔드포인트 (기존 호환성 유지)
@app.get("/api/v1/weather/{station_id}", response_model=WeatherInfo)
async def get_weather(
    station_id: str,
    redis_service: RedisService = Depends(get_redis_service)
):
    """날씨 데이터만 조회"""
    raw_data = redis_service.get_unified_data(station_id)
    
    if not raw_data:
        # 데이터가 없으면 서울 기본 관측소로 재시도
        seoul_id = get_seoul_station_id(redis_service)
        print(f"Station {station_id}의 데이터를 찾을 수 없어 서울 기본 관측소({seoul_id})로 재시도합니다.")
        raw_data = redis_service.get_unified_data(seoul_id)
        
        if not raw_data:
            raise HTTPException(
                status_code=404,
                detail=f"Station {station_id}의 날씨 데이터를 찾을 수 없습니다"
            )
    
    weather_data = redis_service.parse_weather_data(raw_data)
    return WeatherInfo(**weather_data)

# 서울 기본 관측소 ID 조회 엔드포인트
@app.get("/api/v1/weather/default-station-id")
async def get_default_station_id(
    redis_service: RedisService = Depends(get_redis_service)
):
    """서울 기본 관측소 ID 반환"""
    seoul_id = get_seoul_station_id(redis_service)
    seoul_data = redis_service.get_unified_data(seoul_id)
    region = seoul_data.get('location', '서울') if seoul_data else '서울'
    
    return {
        "station_id": seoul_id,
        "region": region
    }


# 회원가입 관련 Pydantic 모델
class SignupRequest(BaseModel):
    username: str = Field(..., min_length=4, max_length=50, description="아이디")
    password: str = Field(..., min_length=6, description="비밀번호")
    name: str = Field(..., min_length=1, max_length=100, description="이름")
    gender: str = Field(..., description="성별 (male, female, other)")
    home_address: str = Field(..., description="집 주소")
    work_address: str = Field(..., description="회사 주소")
    work_start_time: str = Field(..., pattern=r'^([0-1][0-9]|2[0-3]):[0-5][0-9]$', description="출근시간 (HH:MM 형식)")


class SignupResponse(BaseModel):
    success: bool
    message: str
    user_id: Optional[int] = None


class LoginRequest(BaseModel):
    username: str = Field(..., min_length=1, description="아이디")
    password: str = Field(..., min_length=1, description="비밀번호")


class LoginResponse(BaseModel):
    success: bool
    message: str
    user_id: Optional[int] = None
    username: Optional[str] = None
    name: Optional[str] = None
    home_address: Optional[str] = None
    home_latitude: Optional[str] = None
    home_longitude: Optional[str] = None
    work_address: Optional[str] = None
    work_latitude: Optional[str] = None
    work_longitude: Optional[str] = None


class AddressAutocompleteRequest(BaseModel):
    input: str = Field(..., min_length=1, description="주소 검색어")


class AddressAutocompleteResponse(BaseModel):
    predictions: list


# 회원가입 엔드포인트
@app.post("/api/v1/auth/signup", response_model=SignupResponse)
async def signup(
    request: SignupRequest,
    db: Session = Depends(get_db)
):
    """
    회원가입
    - 아이디, 비밀번호, 이름, 성별, 집주소, 회사주소, 출근시간을 받아서 저장
    - Google Maps API로 주소를 검증하고 좌표를 저장
    """
    try:
        # 1. 아이디 중복 확인
        try:
            existing_user = db.query(User).filter(User.user_id == request.username).first()
        except Exception as query_error:
            print(f"사용자 조회 오류: {query_error}")
            import traceback
            traceback.print_exc()
            raise HTTPException(
                status_code=500,
                detail=f"데이터베이스 쿼리 오류: {str(query_error)}"
            )
        
        if existing_user:
            raise HTTPException(
                status_code=400,
                detail="이미 사용 중인 아이디입니다"
            )
        
        # 2. 성별 검증
        try:
            gender_enum = Gender(request.gender.lower())
        except ValueError:
            raise HTTPException(
                status_code=400,
                detail="성별은 male, female, other 중 하나여야 합니다"
            )
        
        # 3. 집 주소 검증 및 좌표 가져오기
        # 상세 주소가 포함될 수 있으므로 기본 주소만 추출하여 검증
        print(f"집 주소 검증 시작: {request.home_address}")
        # 기본 주소 추출 (상세 주소 제거 시도)
        # 예: "서울시 강남구 테헤란로 123 101동 201호" -> "서울시 강남구 테헤란로 123"
        home_base_address = request.home_address
        # 숫자로 시작하는 상세 주소 패턴 제거 (예: "101동", "201호", "3층" 등)
        import re
        # 상세 주소 패턴 제거 (동/호수/층 등)
        home_base_address = re.sub(r'\s+\d+[동호층]?.*$', '', home_base_address).strip()
        
        home_info = await address_service.validate_and_get_coordinates(home_base_address)
        if not home_info:
            # 기본 주소 검증 실패 시 원본 주소로 재시도
            print(f"기본 주소 검증 실패, 원본 주소로 재시도: {home_base_address}")
            home_info = await address_service.validate_and_get_coordinates(request.home_address)
            if not home_info:
                print(f"집 주소 검증 실패: {request.home_address}")
                if not address_service.api_key:
                    raise HTTPException(
                        status_code=500,
                        detail="Google Maps API 키가 설정되지 않았습니다"
                    )
                raise HTTPException(
                    status_code=400,
                    detail=f"집 주소를 찾을 수 없습니다: {request.home_address}. 정확한 주소를 입력해주세요"
                )
        print(f"집 주소 검증 성공: {home_info['formatted_address']}")
        
        # 4. 회사 주소 검증 및 좌표 가져오기
        print(f"회사 주소 검증 시작: {request.work_address}")
        # 기본 주소 추출
        work_base_address = request.work_address
        work_base_address = re.sub(r'\s+\d+[동호층]?.*$', '', work_base_address).strip()
        
        work_info = await address_service.validate_and_get_coordinates(work_base_address)
        if not work_info:
            # 기본 주소 검증 실패 시 원본 주소로 재시도
            print(f"기본 주소 검증 실패, 원본 주소로 재시도: {work_base_address}")
            work_info = await address_service.validate_and_get_coordinates(request.work_address)
            if not work_info:
                print(f"회사 주소 검증 실패: {request.work_address}")
                raise HTTPException(
                    status_code=400,
                    detail=f"회사 주소를 찾을 수 없습니다: {request.work_address}. 정확한 주소를 입력해주세요"
                )
        print(f"회사 주소 검증 성공: {work_info['formatted_address']}")
        
        # 5. 비밀번호 해싱
        password_hash = hash_password(request.password)
        
        # 6. users 테이블에 사용자 기본 정보 저장
        new_user = User(
            user_id=request.username,
            password=password_hash
        )
        
        db.add(new_user)
        db.flush()  # ID를 얻기 위해 flush
        
        # 7. user_profile 테이블에 프로필 정보 저장
        # work_start_time을 commute_time으로 변환 (HH:MM -> Time)
        from datetime import time as dt_time
        commute_time = None
        if request.work_start_time:
            try:
                hour, minute = map(int, request.work_start_time.split(':'))
                commute_time = dt_time(hour=hour, minute=minute)
            except (ValueError, AttributeError):
                pass
        
        new_profile = UserProfile(
            id=new_user.id,
            name=request.name,
            gender=gender_enum.value,  # Enum 값을 문자열로 저장
            commute_time=commute_time,
            feedback_min=None  # 회원가입 시 기본값
        )
        db.add(new_profile)
        
        # 8. user_address 테이블에 주소 정보 저장
        new_address = UserAddress(
            id=new_user.id,
            home_address=request.home_address[5:],
            home_lat=float(home_info['latitude']),
            home_lon=float(home_info['longitude']),
            work_address=request.work_address[5:],
            work_lat=float(work_info['latitude']),
            work_lon=float(work_info['longitude'])
        )
        db.add(new_address)
        
        # 9. events 테이블에 기본 알림 설정을 생성 (회원가입 시 기본값 True)
        try:
            new_event = Event(
                id=new_user.id,
                notify_before_departure=True,
                notify_mask=True,
                notify_umbrella=True,
                notify_clothing=True,
                notify_music=True,
                notify_book=True,
                updated_at=datetime.utcnow()
            )
            db.add(new_event)
        except Exception as event_err:
            # 이벤트 생성 오류는 회원가입 전체 실패로 연결하지 않음
            print(f"⚠️ Event 생성 실패: {event_err}")
            import traceback
            traceback.print_exc()
        
        # 10. 모든 변경사항 커밋
        db.commit()
        db.refresh(new_user)
        
        return SignupResponse(
            success=True,
            message="회원가입이 완료되었습니다",
            user_id=new_user.id
        )
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        print(f"회원가입 오류: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"회원가입 중 오류가 발생했습니다: {str(e)}"
        )


# 로그인 엔드포인트
@app.post("/api/v1/auth/login", response_model=LoginResponse)
async def login(
    request: LoginRequest,
    db: Session = Depends(get_db)
):
    """
    로그인
    - 아이디와 비밀번호를 확인하여 로그인 처리
    """
    try:
        # 1. 사용자 조회
        user = db.query(User).filter(User.user_id == request.username).first()
        
        if not user:
            raise HTTPException(
                status_code=401,
                detail="아이디 또는 비밀번호가 올바르지 않습니다"
            )
        
        # 2. 비밀번호 검증
        if not verify_password(request.password, user.password):
            raise HTTPException(
                status_code=401,
                detail="아이디 또는 비밀번호가 올바르지 않습니다"
            )
        
        # 3. 프로필 및 주소 정보 조회
        profile = db.query(UserProfile).filter(UserProfile.id == user.id).first()
        address = db.query(UserAddress).filter(UserAddress.id == user.id).first()
        
        return LoginResponse(
            success=True,
            message="로그인 성공",
            user_id=user.id,
            username=user.user_id,
            name=profile.name if profile else None,
            home_address=address.home_address if address else None,
            home_latitude=str(address.home_lat) if address and address.home_lat else None,
            home_longitude=str(address.home_lon) if address and address.home_lon else None,
            work_address=address.work_address if address else None,
            work_latitude=str(address.work_lat) if address and address.work_lat else None,
            work_longitude=str(address.work_lon) if address and address.work_lon else None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"로그인 오류: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"로그인 중 오류가 발생했습니다: {str(e)}"
        )


# 주소 자동완성 엔드포인트
@app.post("/api/v1/address/autocomplete", response_model=AddressAutocompleteResponse)
async def autocomplete_address(request: AddressAutocompleteRequest):
    """
    주소 자동완성
    Google Maps API를 사용하여 주소를 검색
    """
    try:
        predictions = await address_service.autocomplete_address(request.input)
        return AddressAutocompleteResponse(predictions=predictions)
    except Exception as e:
        print(f"주소 자동완성 오류: {e}")
        return AddressAutocompleteResponse(predictions=[])


# 주소 검증 엔드포인트
class AddressValidateRequest(BaseModel):
    address: str = Field(..., description="검증할 주소")


class AddressValidateResponse(BaseModel):
    formatted_address: str
    latitude: float
    longitude: float
    is_valid: bool = True


@app.post("/api/v1/address/validate", response_model=AddressValidateResponse)
async def validate_address(request: AddressValidateRequest):
    """
    주소 검증
    Google Maps Geocoding API를 사용하여 주소를 검증하고 좌표를 반환
    """
    import logging
    logger = logging.getLogger(__name__)
    
    logger.info(f"주소 검증 요청 받음: {request.address}")
    
    # API 키 확인
    if not address_service.api_key:
        logger.error("Google Maps API 키가 설정되지 않았습니다")
        raise HTTPException(
            status_code=500,
            detail="Google Maps API 키가 설정되지 않았습니다"
        )
    
    try:
        result = await address_service.validate_and_get_coordinates(request.address)
        
        if not result:
            logger.warning(f"주소 검증 실패: {request.address}")
            # 검증 실패 시에도 원본 주소를 반환 (자동완성에서 선택한 주소는 이미 검증됨)
            # 하지만 좌표는 None으로 설정
            raise HTTPException(
                status_code=400,
                detail="주소를 찾을 수 없습니다. 정확한 주소를 입력해주세요"
            )
        
        logger.info(f"주소 검증 성공: {result['formatted_address']}")
        return AddressValidateResponse(
            formatted_address=result['formatted_address'],
            latitude=float(result['latitude']),
            longitude=float(result['longitude']),
            is_valid=True
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"주소 검증 오류: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"주소 검증 중 오류가 발생했습니다: {str(e)}"
        )


# 알림 설정 관련 Pydantic 모델
class EventSettingsResponse(BaseModel):
    """알림 설정 조회 응답"""
    user_id: int
    notify_before_departure: bool
    notify_mask: bool
    notify_umbrella: bool
    notify_clothing: bool
    notify_music: bool
    notify_book: bool


class EventSettingsRequest(BaseModel):
    """알림 설정 업데이트 요청"""
    notify_before_departure: Optional[bool] = None
    notify_mask: Optional[bool] = None
    notify_umbrella: Optional[bool] = None
    notify_clothing: Optional[bool] = None
    notify_music: Optional[bool] = None
    notify_book: Optional[bool] = None


# 알림 설정 조회
@app.get("/api/v1/events/settings", response_model=EventSettingsResponse)
async def get_event_settings(
    user_id: int,
    db: Session = Depends(get_db)
):
    """사용자의 알림 설정 조회"""
    try:
        event = db.query(Event).filter(Event.id == user_id).first()
        
        if not event:
            raise HTTPException(
                status_code=404,
                detail="사용자의 알림 설정을 찾을 수 없습니다"
            )
        
        return EventSettingsResponse(
            user_id=user_id,
            notify_before_departure=event.notify_before_departure,
            notify_mask=event.notify_mask,
            notify_umbrella=event.notify_umbrella,
            notify_clothing=event.notify_clothing,
            notify_music=event.notify_music,
            notify_book=event.notify_book
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"알림 설정 조회 중 오류가 발생했습니다: {str(e)}"
        )


# 알림 설정 업데이트
@app.put("/api/v1/events/settings", response_model=dict)
async def update_event_settings(
    user_id: int,
    request: EventSettingsRequest,
    db: Session = Depends(get_db)
):
    """사용자의 알림 설정 업데이트"""
    try:
        event = db.query(Event).filter(Event.id == user_id).first()
        
        if not event:
            raise HTTPException(
                status_code=404,
                detail="사용자의 알림 설정을 찾을 수 없습니다"
            )
        
        # 업데이트할 필드가 있으면 업데이트
        if request.notify_before_departure is not None:
            event.notify_before_departure = request.notify_before_departure
        if request.notify_mask is not None:
            event.notify_mask = request.notify_mask
        if request.notify_umbrella is not None:
            event.notify_umbrella = request.notify_umbrella
        if request.notify_clothing is not None:
            event.notify_clothing = request.notify_clothing
        if request.notify_music is not None:
            event.notify_music = request.notify_music
        if request.notify_book is not None:
            event.notify_book = request.notify_book
        
        db.commit()
        
        return {
            "success": True,
            "message": "알림 설정이 업데이트되었습니다"
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"알림 설정 업데이트 중 오류가 발생했습니다: {str(e)}"
        )


# Google Maps API 키 제공 엔드포인트
class MapsConfigResponse(BaseModel):
    """Maps API 설정 응답"""
    google_maps_api_key: str


@app.get("/api/v1/config/maps-api-key", response_model=MapsConfigResponse)
async def get_maps_api_key():
    """
    Google Maps API 키를 Flutter 앱에 제공
    환경 변수 GOOGLE_MAPS_API_KEY에서 가져온 값을 반환
    """
    if not GOOGLE_MAPS_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="Google Maps API 키가 설정되지 않았습니다"
        )
    return MapsConfigResponse(google_maps_api_key=GOOGLE_MAPS_API_KEY)


@app.get("/health")
async def health_check():
    """헬스 체크"""
    try:
        redis_client.ping()
        
        # Redis 연결 정보 및 샘플 키 확인
        redis_info = {
            "status": "healthy",
            "redis": "connected",
            "host": os.getenv('REDIS_HOST', 'localhost'),
            "port": os.getenv('REDIS_PORT', '6379'),
        }
        
        # 샘플 키 검색 (디버깅용)
        try:
            sample_keys = redis_client.keys("kma-stn:*")
            redis_info["sample_keys"] = sample_keys[:10]  # 최대 10개만
            redis_info["key_count"] = len(sample_keys)
        except:
            pass
        
        return redis_info
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}


# 공기질(미세먼지) 매칭 엔드포인트
class AirMatchRequest(BaseModel):
    places: list[str] = []


class AirPlaceResult(BaseModel):
    place: str
    matched_key: Optional[str] = None
    pm10: Optional[str] = None
    pm25: Optional[str] = None
    pm10_level: Optional[str] = None
    pm25_level: Optional[str] = None
    mask_required: Optional[str] = None


class AirMatchResponse(BaseModel):
    places: list[AirPlaceResult]
    mask_required: bool = False


def _normalize(s: str) -> str:
    return s.strip().lower() if s else ""


def _match_place_to_redis(place: str) -> Optional[tuple[str, dict]]:
    """주어진 장소 문자열에서 Redis의 air:대지역:세부분류 키를 찾아 반환
    반환값: (key, hash_dict) 또는 None
    매칭 전략:
    - 큰지역(LARGE_REGIONS) 중 place에 포함된 것이 있으면 그 지역의 모든 air 키 검색
    - 각 키의 세부분류(detail) 문자열이 place에 부분문자열로 포함되는지 확인
    - 없으면 그 큰지역의 첫 키를 반환(근사)
    - 큰지역이 없으면 전체 air:* 키들을 검색하여 부분매칭 시 반환
    """
    normalized = _normalize(place)
    try:
        # 우선 큰지역 포함 여부로 좁혀보기
        for region in LARGE_REGIONS:
            if region and region in place:
                pattern = f"air:{region}:*"
                keys = redis_client.keys(pattern)
                for k in keys:
                    # 키 형식: air:대지역:세부분류
                    parts = k.split(":", 2)
                    if len(parts) == 3:
                        detail = parts[2]
                        if detail and _normalize(detail) in normalized:
                            return k, redis_client.hgetall(k)
                # 근사: 첫 키 반환
                if keys:
                    return keys[0], redis_client.hgetall(keys[0])

        # 큰지역이 없거나 매칭 실패하면 전체 검색
        all_keys = redis_client.keys("air:*")
        for k in all_keys:
            parts = k.split(":", 2)
            if len(parts) == 3:
                detail = parts[2]
                if detail and _normalize(detail) in normalized:
                    return k, redis_client.hgetall(k)

        return None
    except Exception as e:
        print(f"Redis 매칭 중 오류: {e}")
        return None


@app.post("/api/v1/air/match", response_model=AirMatchResponse)
async def match_air_places(request: AirMatchRequest):
    """Flutter에서 보낸 장소 문자열 목록을 받아 Redis의 air 키에 매칭하고
    각 장소별 공기질 정보를 반환합니다. 전체적으로 마스크 필요 여부도 함께 반환.
    """
    results: list[AirPlaceResult] = []
    overall_mask = False

    try:
        for place in request.places:
            found = _match_place_to_redis(place)
            if found:
                key, data = found
                pm10 = data.get('pm10')
                pm25 = data.get('pm25')
                pm10_level = data.get('pm10_level')
                pm25_level = data.get('pm25_level')
                mask_required = data.get('mask_required')

                # pm*_level이 '나쁨' 또는 '매우나쁨'이면 마스크 필요로 간주
                is_bad = False
                def _level_is_bad(v):
                    if not v:
                        return False
                    val = v.decode() if hasattr(v, 'decode') else v
                    val = val.strip()
                    return val in ('나쁨', '매우나쁨')

                if _level_is_bad(pm10_level) or _level_is_bad(pm25_level):
                    is_bad = True

                if is_bad:
                    overall_mask = True

                results.append(AirPlaceResult(
                    place=place,
                    matched_key=key,
                    pm10=pm10,
                    pm25=pm25,
                    pm10_level=pm10_level,
                    pm25_level=pm25_level,
                    mask_required=mask_required
                ))
            else:
                results.append(AirPlaceResult(place=place))

        return AirMatchResponse(places=results, mask_required=overall_mask)
    except Exception as e:
        print(f"공기질 매칭 오류: {e}")
        raise HTTPException(status_code=500, detail=f"공기질 매칭 중 오류: {e}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

