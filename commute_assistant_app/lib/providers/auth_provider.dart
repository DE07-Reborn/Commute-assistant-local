import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

const bool kForceMockLogin = false;

class AuthProvider with ChangeNotifier {
  final ApiService apiService;
  
  bool _isLoggedIn = false;
  int? _userId;
  String? _username;
  String? _name;
  String? _error;
  String? _commuteTime;
  String? _homeAddress;
  double? _homeLatitude;
  double? _homeLongitude;
  String? _workAddress;
  double? _workLatitude;
  double? _workLongitude;

  AuthProvider({required this.apiService});

  bool get isLoggedIn => _isLoggedIn;
  int? get userId => _userId;
  String? get username => _username;
  String? get name => _name;
  String? get error => _error;
  String? get commuteTime => _commuteTime;
  String? get homeAddress => _homeAddress;
  double? get homeLatitude => _homeLatitude;
  double? get homeLongitude => _homeLongitude;
  String? get workAddress => _workAddress;
  double? get workLatitude => _workLatitude;
  double? get workLongitude => _workLongitude;

  /// 로그인
  Future<bool> login(String username, String password) async {
    if (kForceMockLogin) {
      _isLoggedIn = true;
      _userId = 1;
      _username = username;
      _name = '테스트 사용자';
      _commuteTime = '08:30';
      _homeAddress = '서울시 강남구 테헤란로 123';
      _homeLatitude = 37.4981;
      _homeLongitude = 127.0276;
      _workAddress = '서울시 종로구 세종대로 110';
      _workLatitude = 37.5665;
      _workLongitude = 126.9780;
      _error = null;
      notifyListeners();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && _userId != null) {
        await apiService.saveFcmToken(_userId!, token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        if (_userId != null) {
          apiService.saveFcmToken(_userId!, newToken);
        }
      });
      return true;
    }
    
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.login(username, password);
      
      if (response['success'] == true) {
        _isLoggedIn = true;
        _userId = response['user_id'];

        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && _userId != null) {
          await apiService.saveFcmToken(_userId!, token);
        }

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          if (_userId != null) {
            apiService.saveFcmToken(_userId!, newToken);
          }
        });

        _username = response['username'];
        _name = response['name'];
        _commuteTime = response['commute_time'];
        _homeAddress = response['home_address'];
        _homeLatitude = response['home_latitude'] != null 
            ? double.tryParse(response['home_latitude'].toString()) 
            : null;
        _homeLongitude = response['home_longitude'] != null 
            ? double.tryParse(response['home_longitude'].toString()) 
            : null;
        _workAddress = response['work_address'];
        _workLatitude = response['work_latitude'] != null
          ? double.tryParse(response['work_latitude'].toString())
          : null;
        _workLongitude = response['work_longitude'] != null
          ? double.tryParse(response['work_longitude'].toString())
          : null;
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response['message'] ?? '로그인에 실패했습니다';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoggedIn = false;
      notifyListeners();
      return false;
    }
  }

  /// 로그아웃
  void logout() {
    _isLoggedIn = false;
    _userId = null;
    _username = null;
    _name = null;
    _commuteTime = null;
    _homeAddress = null;
    _homeLatitude = null;
    _homeLongitude = null;
    _error = null;
    notifyListeners();
  }

  /// 회원가입
  Future<bool> signup({
    required String username,
    required String password,
    required String name,
    required String gender,
    required String homeAddress,
    required String workAddress,
    required String workStartTime,
  }) async {
    _error = null;
    notifyListeners();

    try {
      final response = await apiService.signup(
        username: username,
        password: password,
        name: name,
        gender: gender,
        homeAddress: homeAddress,
        workAddress: workAddress,
        workStartTime: workStartTime,
      );
      
      if (response['success'] == true) {
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response['message'] ?? '회원가입에 실패했습니다';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
