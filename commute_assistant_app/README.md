# 출퇴근 도우미 앱 (Commute Assistant App)

구글 맵스 API를 활용한 대중교통 경로 안내 및 날씨 기반 추천 서비스를 제공하는 Flutter 앱입니다.

# 아이콘 적용 명령어

flutter pub get
dart run flutter_launcher_icons:main

## 주요 기능

### 1. 경로 안내
- 출발지와 도착지 입력을 통한 경로 검색
- Google Maps를 통한 시각적 경로 표시
- 대중교통(버스/지하철) 도착 시간 정보 제공
- 거리 및 소요 시간 표시

### 2. 날씨 기반 추천
- 현재 위치 기반 날씨 정보 제공
- 날씨에 따른 옷차림 추천
- 날씨에 맞는 도서 추천
- 날씨에 맞는 음악 추천

## 설정 방법

### 1. 필요한 패키지 설치

```bash
flutter pub get
```

### 2. Google Maps API 키 설정

1. [Google Cloud Console](https://console.cloud.google.com/)에서 프로젝트 생성
2. Maps SDK for Android 및 Directions API 활성화
3. API 키 생성
4. `android/app/src/main/AndroidManifest.xml` 파일에서 `YOUR_API_KEY`를 실제 API 키로 교체:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="여기에_실제_API_키_입력" />
```

5. `lib/main.dart` 파일에서도 API 키 설정:

```dart
const String googleMapsApiKey = '여기에_실제_API_키_입력';
```

### 3. 날씨 API 키 설정 (선택사항)

OpenWeatherMap 등의 날씨 API를 사용하려면 `lib/main.dart`에서 설정:

```dart
const String? weatherApiKey = '여기에_날씨_API_키_입력';
```

API 키가 없어도 기본 날씨 정보는 제공됩니다.

### 4. 외부 데이터베이스 연결 (옷차림/도서/음악 추천)

외부 데이터베이스에서 추천 정보를 가져오려면 `lib/main.dart`의 `RecommendationService` 설정 부분을 수정하세요:

```dart
final recommendationService = RecommendationService(
  onGetClothing: (condition) async {
    // 외부 DB에서 옷차림 정보 가져오기
    // 예: return await yourDatabase.getClothing(condition);
    return '외부 DB에서 가져온 옷차림 추천';
  },
  onGetBooks: (condition) async {
    // 외부 DB에서 도서 정보 가져오기
    // 예: return await yourDatabase.getBooks(condition);
    return ['도서1', '도서2', '도서3'];
  },
  onGetMusic: (condition) async {
    // 외부 DB에서 음악 정보 가져오기
    // 예: return await yourDatabase.getMusic(condition);
    return ['음악1', '음악2', '음악3'];
  },
);
```

## 프로젝트 구조

```
lib/
├── main.dart                          # 앱 진입점
├── models/                            # 데이터 모델
│   ├── route_info.dart               # 경로 정보 모델
│   └── weather_info.dart              # 날씨 정보 모델
├── services/                          # 서비스 레이어
│   ├── maps_service.dart             # Google Maps API 서비스
│   ├── weather_service.dart          # 날씨 API 서비스
│   └── recommendation_service.dart   # 추천 서비스 (외부 DB 연결)
├── providers/                         # 상태 관리
│   ├── route_provider.dart           # 경로 상태 관리
│   └── weather_provider.dart         # 날씨 상태 관리
└── screens/                           # 화면
    ├── home_screen.dart              # 메인 화면
    ├── route_screen.dart             # 경로 검색 화면
    └── weather_recommendation_screen.dart  # 날씨 추천 화면
```

## 사용된 주요 패키지

- `google_maps_flutter`: Google Maps 통합
- `http`: HTTP 요청
- `geolocator`: 위치 정보
- `provider`: 상태 관리
- `geocoding`: 주소-좌표 변환
- `intl`: 날짜/시간 포맷팅

## 실행 방법

```bash
flutter run
```

## 주의사항

1. Google Maps API는 사용량에 따라 비용이 발생할 수 있습니다.
2. Android 앱을 실행하려면 위치 권한이 필요합니다.
3. 실제 대중교통 도착 시간 정보는 Google Directions API의 TRANSIT 모드를 통해 제공됩니다.
4. 외부 데이터베이스 연결은 사용자가 직접 구현해야 합니다.

## 라이선스

이 프로젝트는 교육 목적으로 제작되었습니다.
