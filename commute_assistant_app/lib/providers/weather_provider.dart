import 'package:flutter/foundation.dart';
import '../models/weather_info.dart';
import '../services/weather_service_api.dart';
import '../services/recommendation_service_api.dart';
import '../services/location_service.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/recommendation_detail.dart';

const bool kUseMockUi = false;

class WeatherProvider with ChangeNotifier {
  final WeatherServiceApi _weatherService;
  final RecommendationServiceApi _recommendationService;
  final LocationService _locationService;
  AuthProvider? _authProvider;  // ProxyProvider에서 업데이트될 수 있도록 final 제거
  bool _mounted = true;
  
  bool get mounted => _mounted;
  
  WeatherInfo? _weatherInfo;
  Recommendation? _recommendation;
  bool _isLoading = false;
  String? _error;
  String? _currentLocationAddress;

  final ApiService _apiService;

  bool _maskRequired = false;
  bool _umbrellaRequired = false;
  String _lastMaskKey = '';
  String _lastUmbrellaKey = '';

  bool get maskRequired => _maskRequired;
  bool get umbrellaRequired => _umbrellaRequired;

  WeatherProvider({
    required WeatherServiceApi weatherService,
    required RecommendationServiceApi recommendationService,
    required LocationService locationService,
    required ApiService apiService,
    AuthProvider? authProvider,
  })  : _weatherService = weatherService,
        _recommendationService = recommendationService,
        _locationService = locationService,
        _authProvider = authProvider,
        _apiService = apiService;

  WeatherInfo? get weatherInfo => _weatherInfo;
  Recommendation? get recommendation => _recommendation;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentLocationAddress => _currentLocationAddress;

  WeatherInfo _buildMockWeather() {
    return WeatherInfo(
      temperature: 24.0,
      condition: 'rainy',
      humidity: 82,
      windSpeed: 3.2,
      description: 108,
      location: '서울 강남구',
      weatherCategory: '비',
    );
  }

  Recommendation _buildMockRecommendation() {
    return Recommendation(
      clothing: '우산과 레인코트를 준비하세요',
      books: [
        '비 오는 날엔 커피 한 잔\n무라카미 하루키',
        '우산 속의 작은 세계\n김연수',
        '빗소리와 재즈\n이승우',
      ],
      music: [
        'Rainy Night\nThe Blue Notes\nJazz Trio',
        'Umbrella\nRihanna\nGood Girl Gone Bad',
        '비 오는 거리\n김건모\nBest of Kim',
      ],
      clothingItems: [
        RecommendationDetail(category: '우산', name: '컴팩트 우산', description: ''),
        RecommendationDetail(category: '아우터', name: '레인코트', description: ''),
        RecommendationDetail(category: '신발', name: '방수 스니커즈', description: ''),
      ],
    );
  }

  /// AuthProvider 업데이트 (ProxyProvider에서 호출)
  void updateAuthProvider(AuthProvider? authProvider) {
    _authProvider = authProvider;
  }

  Future<void> refreshMaskUmbrella() async {
    final auth = _authProvider;
    if (!_mounted) return;

    if (auth != null && auth.isLoggedIn) {
      await _updateMaskStateIfNeeded(auth);
      await _updateUmbrellaStateIfNeeded(auth);
    } else {
      await _updateMaskStateIfNeeded(null);
      await _updateUmbrellaStateIfNeeded(null);
    }
  }

  Future<void> _updateMaskStateIfNeeded(AuthProvider? authProvider) async {
    final coordinates = <Map<String, double>>[];

    try {
      final currentPosition = await _locationService.getCurrentPosition();
      if (currentPosition != null) {
        coordinates.add({
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
        });
      }
    } catch (e) {
      print('현재 위치 조회 오류: $e');
    }

    if (authProvider != null && authProvider.homeLatitude != null && authProvider.homeLongitude != null) {
      coordinates.add({
        'latitude': authProvider.homeLatitude!,
        'longitude': authProvider.homeLongitude!,
      });
    }

    if (authProvider != null && authProvider.workLatitude != null && authProvider.workLongitude != null) {
      coordinates.add({
        'latitude': authProvider.workLatitude!,
        'longitude': authProvider.workLongitude!,
      });
    }

    if (coordinates.isEmpty) {
      coordinates.add({
        'latitude': 37.5172,
        'longitude': 127.0473,
      });
    }

    final key = coordinates
        .map((c) => '${c['latitude']},${c['longitude']}')
        .join('|');
    if (key == _lastMaskKey) return;
    _lastMaskKey = key;

    try {
      final resp = await _apiService.postAirMatch(coordinates);
      final mask = resp != null && resp['mask_required'] == true;
      if (_mounted && mask != _maskRequired) {
        _maskRequired = mask;
        notifyListeners();
      }
    } catch (e) {
      print('마스크 상태 조회 오류: $e');
    }
  }

  Future<void> _updateUmbrellaStateIfNeeded(AuthProvider? authProvider) async {
    final coordinates = <Map<String, dynamic>>[];

    try {
      final currentPosition = await _locationService.getCurrentPosition();
      if (currentPosition != null) {
        coordinates.add({
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
          'kind': 'current',
        });
      }
    } catch (e) {
      print('현재 위치 조회 오류: $e');
    }

    if (authProvider != null && authProvider.homeLatitude != null && authProvider.homeLongitude != null) {
      coordinates.add({
        'latitude': authProvider.homeLatitude!,
        'longitude': authProvider.homeLongitude!,
        'kind': 'home',
      });
    }

    if (authProvider != null && authProvider.workLatitude != null && authProvider.workLongitude != null) {
      coordinates.add({
        'latitude': authProvider.workLatitude!,
        'longitude': authProvider.workLongitude!,
        'kind': 'work',
      });
    }

    if (coordinates.isEmpty) {
      coordinates.add({
        'latitude': 37.5172,
        'longitude': 127.0473,
        'kind': 'current',
      });
    }

    final key = coordinates.map((c) => '${c['latitude']},${c['longitude']}').join('|');
    if (key == _lastUmbrellaKey) return;
    _lastUmbrellaKey = key;

    try {
      final resp = await _apiService.postUmbrellaMatch(authProvider?.userId, coordinates);
      final umbrella = resp != null && resp['umbrella_required'] == true;
      if (_mounted && umbrella != _umbrellaRequired) {
        _umbrellaRequired = umbrella;
        notifyListeners();
      }
    } catch (e) {
      print('우산 상태 조회 오류: $e');
    }
  }

  /// 위치 기반 날씨 로딩
  Future<void> loadWeather() async {
    if (!_mounted) return;
    
    _isLoading = true;
    if (kUseMockUi) {
      _weatherInfo = _buildMockWeather();
      _recommendation = _buildMockRecommendation();
      _maskRequired = false;
      _umbrellaRequired = false;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    _error = null;
    notifyListeners();

    try {
      // 로그인한 사용자인 경우 위치 비교
      if (_authProvider != null && _authProvider!.isLoggedIn) {
        await _loadWeatherWithLocationCheck();
      } else {
        // 로그인하지 않은 경우 기본 날씨 로딩
        await _loadDefaultWeather();
      }
    } catch (e) {
      if (_mounted) {
        _error = '날씨 정보 로딩 중 오류가 발생했습니다: $e';
      }
    } finally {
      if (_mounted) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 위치 확인 후 날씨 로딩
  Future<void> _loadWeatherWithLocationCheck() async {
    if (!_mounted) return;
    
    try {
      // 현재 위치 가져오기
      final currentPosition = await _locationService.getCurrentPosition();
      if (!_mounted) return;
      
      if (currentPosition == null) {
        print('현재 위치를 가져올 수 없어 기본 날씨를 로딩합니다.');
        await _loadDefaultWeather();
        return;
      }

      // 현재 위치 주소 가져오기
      _currentLocationAddress = await _locationService.getAddressFromCoordinates(
        currentPosition.latitude,
        currentPosition.longitude,
      );
      if (!_mounted) return;

      // 집 주소 좌표 가져오기
      final homeLat = _authProvider!.homeLatitude;
      final homeLng = _authProvider!.homeLongitude;

      double targetLat = currentPosition.latitude;
      double targetLng = currentPosition.longitude;

      // 서울 중심 좌표 (강남구 기준)
      const seoulCenterLat = 37.5172;
      const seoulCenterLng = 127.0473;

      // 현재 위치가 대한민국(한국) 내부인지 간단히 판별합니다.
      // LocationService.getAddressFromCoordinates가 반환하는 문자열에 국가명이 포함되므로
      // '대한민국', '한국', 'korea' 여부로 판별합니다.
      final addrLower = _currentLocationAddress?.toLowerCase() ?? '';
      final isInKorea = addrLower.contains('대한민국') || addrLower.contains('한국') || addrLower.contains('korea');

      if (!isInKorea) {
        // 한국 내 지역이 아니면 서울(강남구)로 고정
        print('현재 위치가 한국 내 지역이 아님으로 간주, 강남구 좌표로 매칭합니다. 주소: $_currentLocationAddress');
        targetLat = seoulCenterLat;
        targetLng = seoulCenterLng;
      } else if (homeLat != null && homeLng != null) {
        // 집 주소와 현재 위치 비교 (1km 이내면 같은 위치로 간주)
        final isAtHome = _locationService.isSameLocation(
          homeLat,
          homeLng,
          currentPosition.latitude,
          currentPosition.longitude,
          thresholdMeters: 1000.0,
        );

        if (isAtHome) {
          print('집 주소와 현재 위치가 일치합니다. 집 주소 기준으로 날씨를 가져옵니다.');
          print('집 주소: ${_authProvider?.homeAddress}');
          // 집 주소 좌표 사용
          targetLat = homeLat;
          targetLng = homeLng;
        } else {
          print('집 주소와 현재 위치가 다릅니다. 현재 위치 기준으로 날씨를 가져옵니다.');
          print('집 주소: ${_authProvider?.homeAddress}');
          print('현재 위치: $_currentLocationAddress');
          // 현재 위치 좌표 사용
        }
      } else {
        print('집 주소 좌표 정보가 없어 현재 위치 기준으로 날씨를 가져옵니다.');
        // 현재 위치 좌표 사용
      }

      // 좌표 기반으로 가장 가까운 관측소의 날씨 데이터 가져오기
      final weather = await _weatherService.getWeatherByCoordinates(targetLat, targetLng);
      if (!_mounted) return;
      
      if (weather != null) {
        _weatherInfo = weather;
        // 좌표를 전달하여 해당 위치의 통합 데이터(도서, 음악) 가져오기
        _recommendation = await _recommendationService.getRecommendations(
          weather.condition,
          latitude: targetLat,
          longitude: targetLng,
        );
        if (!_mounted) return;
        _error = null;
      } else {
        // 좌표 기반 조회 실패 시 강남구 좌표로 재시도
        print('좌표 기반 날씨 조회 실패, 강남구 좌표로 재시도합니다.');
        const gangnamLat = 37.5172;  // 강남구 위도
        const gangnamLng = 127.0473;  // 강남구 경도
        
        final gangnamWeather = await _weatherService.getWeatherByCoordinates(gangnamLat, gangnamLng);
        if (!_mounted) return;
        
        if (gangnamWeather != null) {
          _weatherInfo = gangnamWeather;
          // 강남구 좌표로 통합 데이터 가져오기
          _recommendation = await _recommendationService.getRecommendations(
            gangnamWeather.condition,
            latitude: gangnamLat,
            longitude: gangnamLng,
          );
          if (!_mounted) return;
          _error = null;
        } else {
          // 강남구 조회도 실패 시 기본 날씨 로딩
          print('강남구 좌표 기반 날씨 조회도 실패, 기본 날씨를 로딩합니다.');
          await _loadDefaultWeather();
      }
      }
      
    } catch (e) {
      if (_mounted) {
        print('위치 기반 날씨 로딩 오류: $e');
        // 오류 발생 시 기본 날씨 로딩
        await _loadDefaultWeather();
      }
    }
  }

  /// 기본 날씨 로딩
  Future<void> _loadDefaultWeather() async {
    if (!_mounted) return;
    
    final weather = await _weatherService.getCurrentWeather();
    if (!_mounted) return;
    
    if (weather != null) {
      _weatherInfo = weather;
      _recommendation = await _recommendationService.getRecommendations(
        weather.condition,
      );
      _error = null;
    } else {
      _error = '날씨 정보를 가져올 수 없습니다.';
    }
  }
  
  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }
}

