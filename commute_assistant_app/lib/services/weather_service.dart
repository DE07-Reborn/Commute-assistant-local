import '../models/weather_info.dart';
import 'redis_service.dart';

class WeatherService {
  // Redis에서 날씨 데이터를 가져옵니다
  // Docker 컨테이너 내부의 Redis에 저장된 날씨 데이터를 사용합니다
  final RedisService redisService;
  final String redisKey; // Redis에서 가져올 키 (예: 'kma-stn:130', 'kma-stn:251')

  WeatherService({
    required this.redisService,
    required this.redisKey,
  });

  Future<WeatherInfo?> getCurrentWeather() async {
    try {
      // Redis에서 날씨 데이터 가져오기
      return await _getWeatherFromRedis();
    } catch (e) {
      print('날씨 데이터 가져오기 실패: $e');
      // Redis 연결 실패 시 null 반환 (에러 처리)
      return null;
    }
  }

  /// Redis에서 전체 데이터 가져오기 (날씨 + 추천 정보)
  Future<Map<String, dynamic>?> getFullData() async {
    try {
      // Redis 연결 확인
      if (!redisService.isConnected) {
        await redisService.connect();
      }

      // Redis에서 데이터 가져오기
      final data = await redisService.getWeatherData(redisKey);
      
      if (data == null || data.isEmpty) {
        print('Redis에서 데이터를 찾을 수 없습니다. 키: $redisKey');
        return null;
      }

      return data;
    } catch (e) {
      print('Redis에서 전체 데이터 가져오기 실패: $e');
      return null;
    }
  }

  /// Redis에서 날씨 데이터 가져오기
  Future<WeatherInfo?> _getWeatherFromRedis() async {
    try {
      // Redis 연결 확인
      if (!redisService.isConnected) {
        await redisService.connect();
      }

      // Redis에서 데이터 가져오기
      final data = await redisService.getWeatherData(redisKey);
      
      if (data == null || data.isEmpty) {
        print('Redis에서 날씨 데이터를 찾을 수 없습니다. 키: $redisKey');
        return null;
      }

      // 데이터 파싱
      // ws: 풍속, ta: 기온, hm: 습도, wc: 날씨 카테고리
      final ws = _parseDouble(data['ws'] ?? '0');
      final ta = _parseDouble(data['ta'] ?? '0');
      final hm = _parseDouble(data['hm'] ?? '0').toInt(); // hm은 double로 저장되어 있을 수 있음
      // 웨더 카테고리의 마지막 날씨 부분만 가져와서 처리
      final category = data['weather_category']?.toString() ?? '';
      final wc = category.split('-').last;

      // 날씨 카테고리를 condition으로 변환
      final condition = _mapWeatherCategoryToCondition(wc);
      
      // description 설정
      final description = data['ws'] ?? -99;

      return WeatherInfo(
        temperature: ta,
        condition: condition,
        humidity: hm,
        windSpeed: ws,
        description: description,
        location: data['location']?.toString(),
        weatherCategory: wc,
      );
    } catch (e) {
      print('Redis에서 날씨 데이터 가져오기 실패: $e');
      rethrow;
    }
  }

  /// 문자열을 double로 변환
  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  /// 날씨 카테고리(한글)를 condition으로 변환
  String _mapWeatherCategoryToCondition(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('비') || lower.contains('rain')) {
      return 'rainy';
    } else if (lower.contains('눈') || lower.contains('snow')) {
      return 'snowy';
    } else if (lower.contains('흐림') || lower.contains('cloud')) {
      return 'cloudy';
    } else if (lower.contains('맑음') || lower.contains('화창') || lower.contains('sunny') || lower.contains('clear')) {
      return 'sunny';
    } else {
      return 'sunny'; // 기본값
    }
  }

}

