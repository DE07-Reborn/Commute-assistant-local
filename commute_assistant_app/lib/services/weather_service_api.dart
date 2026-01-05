import '../models/weather_info.dart';
import 'api_service.dart';

/// FastAPI를 통해 날씨 데이터를 가져오는 서비스
class WeatherServiceApi {
  final ApiService apiService;
  final String stationId;
  
  WeatherServiceApi({
    required this.apiService,
    required this.stationId,
  });
  
  /// 현재 날씨 정보 가져오기
  Future<WeatherInfo?> getCurrentWeather() async {
    try {
      final data = await apiService.get('/api/v1/weather/$stationId');
      
      if (data == null) {
        print('날씨 데이터를 가져올 수 없습니다.');
        return null;
      }
      
      return WeatherInfo(
        temperature: (data['temperature'] as num).toDouble(),
        condition: data['condition'] as String,
        humidity: data['humidity'] as int,
        windSpeed: (data['windSpeed'] as num).toDouble(),
        description: data['description'] as int,
        location: data['location'] as String?,
        weatherCategory: data['weatherCategory'] as String?,
      );
    } catch (e) {
      print('날씨 데이터 파싱 오류: $e');
      return null;
    }
  }
  
  /// 통합 데이터 가져오기 (날씨 + 도서 + 음악)
  Future<Map<String, dynamic>?> getUnifiedData([String? customStationId]) async {
    try {
      final id = customStationId ?? stationId;
      return await apiService.get('/api/v1/data/$id');
    } catch (e) {
      print('통합 데이터 가져오기 오류: $e');
      return null;
    }
  }
  
  /// 좌표 기반 통합 데이터 가져오기 (날씨 + 도서 + 음악)
  Future<Map<String, dynamic>?> getUnifiedDataByCoordinates(double latitude, double longitude) async {
    try {
      // 가장 가까운 관측소 ID 찾기
      final nearestStationId = await getNearestStationId(latitude, longitude);
      if (nearestStationId != null) {
        return await getUnifiedData(nearestStationId);
      }
      return null;
    } catch (e) {
      print('좌표 기반 통합 데이터 가져오기 오류: $e');
      return null;
    }
  }
  
  /// 좌표 기반으로 가장 가까운 관측소의 날씨 정보 가져오기
  Future<WeatherInfo?> getWeatherByCoordinates(double latitude, double longitude) async {
    try {
      final data = await apiService.get('/api/v1/weather/by-coordinates?latitude=$latitude&longitude=$longitude');
      
      if (data == null) {
        print('좌표 기반 날씨 데이터를 가져올 수 없습니다.');
        return null;
      }
      
      return WeatherInfo(
        temperature: (data['temperature'] as num).toDouble(),
        condition: data['condition'] as String,
        humidity: data['humidity'] as int,
        windSpeed: (data['windSpeed'] as num).toDouble(),
        description: data['description'] as int,
        location: data['location'] as String?,
        weatherCategory: data['weatherCategory'] as String?,
      );
    } catch (e) {
      print('좌표 기반 날씨 데이터 파싱 오류: $e');
      return null;
    }
  }
  
  /// 가장 가까운 관측소 ID 찾기
  Future<String?> getNearestStationId(double latitude, double longitude) async {
    try {
      final data = await apiService.get('/api/v1/weather/nearest-station?latitude=$latitude&longitude=$longitude');
      
      if (data == null) {
        print('가장 가까운 관측소를 찾을 수 없습니다.');
        return null;
      }
      
      return data['station_id'] as String?;
    } catch (e) {
      print('가장 가까운 관측소 찾기 오류: $e');
      return null;
    }
  }
}

