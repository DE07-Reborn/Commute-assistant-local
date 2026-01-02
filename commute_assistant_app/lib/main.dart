import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'screens/home_screen.dart';
import 'providers/route_provider.dart';
import 'providers/weather_provider.dart';
import 'providers/saved_location_provider.dart';
import 'providers/recent_search_provider.dart';
import 'providers/places_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/event_settings_provider.dart';
import 'services/maps_service.dart';
import 'services/weather_service_api.dart';
import 'services/recommendation_service_api.dart';
import 'services/places_service.dart';
import 'services/api_service.dart';
import 'services/location_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<String> _apiKeyFuture;
  
  @override
  void initState() {
    super.initState();
    // FastAPI에서 Google Maps API 키 로드
    _apiKeyFuture = _fetchGoogleMapsApiKey();
  }
  
  Future<String> _fetchGoogleMapsApiKey() async {
    const String apiBaseUrl = 'http://10.0.2.2:8000';
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/config/maps-api-key'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final apiKey = data['google_maps_api_key'] as String;
        print('✅ FastAPI에서 Google Maps API 키 로드 성공');
        return apiKey;
      } else {
        print('❌ FastAPI에서 API 키 로드 실패: ${response.statusCode}');
        // 폴백: 기본값 사용
        return 'AIzaSyD0R-e5sVfzsjbpq1g_hY4eS452dZ4ZL78';
      }
    } catch (e) {
      print('⚠️ FastAPI에서 API 키 로드 중 오류: $e');
      // 폴백: 기본값 사용
      return 'AIzaSyD0R-e5sVfzsjbpq1g_hY4eS452dZ4ZL78';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _apiKeyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // API 키 로드 중에는 로딩 화면 표시
          return MaterialApp(
            title: '출퇴근 도우미',
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('앱 초기화 중...'),
                  ],
                ),
              ),
            ),
          );
        }
        
        if (snapshot.hasError) {
          print('❌ API 키 로드 오류: ${snapshot.error}');
        }
        
        // API 키 가져오기 (에러 시 폴백값 사용)
        final googleMapsApiKey = snapshot.data ?? 'AIzaSyD0R-e5sVfzsjbpq1g_hY4eS452dZ4ZL78';
        
        // ============================================
        // FastAPI 설정
        // ============================================
        // FastAPI 서버를 통해 Redis에 저장된 통합 데이터를 가져옵니다
        // 
        // 주의사항:
        // - Android 에뮬레이터에서 접근: baseUrl을 'http://10.0.2.2:8000'로 설정
        // - iOS 시뮬레이터에서 접근: baseUrl을 'http://localhost:8000'로 설정
        // - 실제 디바이스에서 접근: PC의 실제 IP 주소 사용 (예: 'http://192.168.0.100:8000')
        // - FastAPI 서버가 실행 중이어야 합니다
        //
        const String apiBaseUrl = 'http://10.0.2.2:8000'; // FastAPI 서버 주소
        const String stationId = '108'; // 서울 기본 관측소 ID (로그인 안 했을 때 사용)

        // 서비스 인스턴스 생성
        final mapsService = MapsService(apiKey: googleMapsApiKey);
        final placesService = PlacesService(apiKey: googleMapsApiKey);
        
        // FastAPI 서비스 생성
        final apiService = ApiService(baseUrl: apiBaseUrl);
        final weatherService = WeatherServiceApi(
          apiService: apiService,
          stationId: stationId,
        );
        
        // 추천 서비스 - FastAPI를 통해 음악과 도서 추천 정보를 가져옵니다
        final recommendationService = RecommendationServiceApi(
          weatherService: weatherService,
        );
        
        // 위치 서비스
        final locationService = LocationService();

        return MultiProvider(
          providers: [
            // ============================================
            // Google Maps 관련 Provider
            // ============================================
            // API 키를 문자열로 전역 제공 (필요시 직접 주입 가능)
            Provider<String>.value(value: googleMapsApiKey),
            // MapsService 인스턴스 제공 (경로 검색용)
            Provider<MapsService>.value(value: mapsService),
            // PlacesService 인스턴스 제공 (주소 자동완성용)
            Provider<PlacesService>.value(value: placesService),
            // ============================================
            // 비즈니스 로직 Provider
            // ============================================
            ChangeNotifierProvider(
              create: (_) => RouteProvider(mapsService: mapsService),
            ),
            ChangeNotifierProvider(
              create: (_) => AuthProvider(apiService: apiService),
            ),
            ChangeNotifierProxyProvider<AuthProvider, WeatherProvider>(
              create: (_) => WeatherProvider(
                weatherService: weatherService,
                recommendationService: recommendationService,
                locationService: locationService,
                authProvider: null, // ProxyProvider에서 업데이트됨
              ),
              update: (context, authProvider, previous) {
                // 이전 provider가 있으면 재사용 (dispose 방지)
                if (previous != null) {
                  // authProvider만 업데이트
                  previous.updateAuthProvider(authProvider);
                  
                  // 로그인 상태가 변경되고 날씨가 없으면 로드
                  if (authProvider.isLoggedIn && previous.weatherInfo == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (previous.mounted) {
                        previous.loadWeather();
                      }
                    });
                  }
                  
                  return previous;
                }
                
                // 새로운 provider 생성
                final provider = WeatherProvider(
                  weatherService: weatherService,
                  recommendationService: recommendationService,
                  locationService: locationService,
                  authProvider: authProvider,
                );
                
                // 로그인 상태가 변경되고 날씨가 없으면 로드
                if (authProvider.isLoggedIn) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (provider.mounted) {
                      provider.loadWeather();
                    }
                  });
                }
                
                return provider;
              },
            ),
            ChangeNotifierProvider(
              create: (_) => SavedLocationProvider(),
            ),
            ChangeNotifierProvider(
              create: (_) => RecentSearchProvider(),
            ),
            ChangeNotifierProvider(
              create: (_) => PlacesProvider(placesService: placesService),
            ),
            ChangeNotifierProvider(
              create: (_) => EventSettingsProvider(apiService: apiService),
            ),
            // ApiService를 전역으로 제공하여 UI에서 직접 호출 가능하도록 함
            Provider.value(value: apiService),
          ],
          child: MaterialApp(
            title: '출퇴근 도우미',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                centerTitle: true,
                elevation: 0,
              ),
            ),
            home: const HomeScreen(),
          ),
        );
      },
    );
  }
}
