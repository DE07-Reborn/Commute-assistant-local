import 'dart:convert';
import 'package:http/http.dart' as http;

/// FastAPI 서버와 통신하는 기본 서비스
class ApiService {
  final String baseUrl;
  
  ApiService({required this.baseUrl});
  
  /// GET 요청
  Future<Map<String, dynamic>?> get(String endpoint) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        print('API 요청 실패: ${response.statusCode}, URL: $url');
        print('응답 본문: ${response.body}');
        return null;
      }
    } catch (e) {
      print('API 요청 오류: $e');
      return null;
    }
  }
  
  /// POST 요청
  Future<Map<String, dynamic>?> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        // 에러 응답도 파싱하여 상세 정보 반환
        try {
          final errorData = json.decode(response.body) as Map<String, dynamic>;
          throw Exception(errorData['detail'] ?? '요청 실패');
        } catch (_) {
          throw Exception('요청 실패: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('API POST 요청 오류: $e');
      rethrow;
    }
  }

  /// PUT 요청
  Future<Map<String, dynamic>?> put(String endpoint, Map<String, dynamic> body) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        // 에러 응답도 파싱하여 상세 정보 반환
        try {
          final errorData = json.decode(response.body) as Map<String, dynamic>;
          throw Exception(errorData['detail'] ?? '요청 실패');
        } catch (_) {
          throw Exception('요청 실패: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('API PUT 요청 오류: $e');
      rethrow;
    }
  }
  
  /// 로그인
  Future<Map<String, dynamic>> login(String username, String password) async {
    final body = {
      'username': username,
      'password': password,
    };
    return await post('/api/v1/auth/login', body) ?? {};
  }
  
  /// 회원가입
  Future<Map<String, dynamic>> signup({
    required String username,
    required String password,
    required String name,
    required String gender,
    required String homeAddress,
    required String workAddress,
    required String workStartTime,
  }) async {
    final body = {
      'username': username,
      'password': password,
      'name': name,
      'gender': gender,
      'home_address': homeAddress,
      'work_address': workAddress,
      'work_start_time': workStartTime,
    };
    return await post('/api/v1/auth/signup', body) ?? {};
  }

  /// 알림 설정 조회
  Future<Map<String, dynamic>?> getEventSettings(int userId) async {
    return await get('/api/v1/events/settings?user_id=$userId');
  }

  /// 알림 설정 업데이트
  Future<Map<String, dynamic>?> updateEventSettings(int userId, Map<String, dynamic> settings) async {
    return await put('/api/v1/events/settings?user_id=$userId', settings);
  }

  /// 공기질 장소 매칭
  Future<Map<String, dynamic>?> postAirMatch(List<String> places) async {
    try {
      final url = Uri.parse('$baseUrl/api/v1/air/match');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'places': places}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        try {
          final errorData = json.decode(response.body) as Map<String, dynamic>;
          throw Exception(errorData['detail'] ?? '요청 실패');
        } catch (_) {
          throw Exception('요청 실패: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('공기질 매칭 API 오류: $e');
      rethrow;
    }
  }

  /// 출근 경로 상태 조회
  Future<Map<String, dynamic>?> getRouteState(int userId) async {
    return await get('/api/v1/route?user_id=$userId');
  }

  /// 출근 경로 승인 상태 저장
  Future<Map<String, dynamic>?> approveRoute({
    required int userId,
    required String departAt,
  }) async {
    return await post('/api/v1/route/approve', {
      'user_id': userId,
      'depart_at': departAt,
    });
  }
}
