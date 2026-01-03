import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../providers/weather_provider.dart';
import '../providers/route_provider.dart';
import '../providers/saved_location_provider.dart';
import '../providers/recent_search_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/saved_location.dart';
import '../models/recent_search.dart';
import '../widgets/address_autocomplete_field.dart';
import 'route_screen.dart';
import 'recommendation_tab_screen.dart';
import 'login_screen.dart';
import 'notification_settings_screen.dart';
import 'notification_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  bool _isDateFormatInitialized = false;
  String? _originAddress;
  String? _destinationAddress;
  double? _originLat;
  double? _originLng;
  double? _destLat;
  double? _destLng;
  String _currentGreeting = '';
  bool _maskRequired = false;
  String _lastMaskKey = '';
  Map<String, dynamic>? _routeState;
  bool _isRouteStateLoading = false;
  String? _routeStateError;
  int? _routeStateUserId;
  DateTime? _lastRouteStateFetch;
  Timer? _minuteTicker;

  @override
  void initState() {
    super.initState();
    // 한국어 날짜 포맷팅 초기화
    initializeDateFormatting('ko', null).then((_) {
      if (mounted) {
        setState(() {
          _isDateFormatInitialized = true;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WeatherProvider>().loadWeather();
    });
    
    // 인삿말 초기화
    _currentGreeting = _getGreeting();
    
    // 매 분마다 인삿말 업데이트
    _startGreetingTimer();

    _minuteTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
  
  void _startGreetingTimer() {
    // 매 분마다 인삿말 확인 및 업데이트
    Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        final newGreeting = _getGreeting();
        if (newGreeting != _currentGreeting) {
          setState(() {
            _currentGreeting = newGreeting;
          });
        }
        _startGreetingTimer();  // 재귀적으로 계속 실행
      }
    });
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _minuteTicker?.cancel();
    super.dispose();
  }

  void _maybeLoadRouteState(AuthProvider authProvider) {
    if (!authProvider.isLoggedIn || authProvider.userId == null) {
      return;
    }
    if (!_isBeforeCommuteTime(authProvider)) {
      return;
    }
    if (_isRouteStateLoading) {
      return;
    }
    final userId = authProvider.userId!;
    final now = DateTime.now();
    if (_routeStateUserId == userId && _lastRouteStateFetch != null) {
      if (now.difference(_lastRouteStateFetch!) < const Duration(minutes: 1)) {
        return;
      }
    }

    _routeStateUserId = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRouteState(userId);
    });
  }

  Future<void> _loadRouteState(int userId) async {
    if (_isRouteStateLoading) return;
    setState(() {
      _isRouteStateLoading = true;
      _routeStateError = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final data = await apiService.getRouteState(userId);
      if (!mounted) return;
      setState(() {
        _routeState = data;
        _routeStateError = null;
        _lastRouteStateFetch = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routeState = null;
        _routeStateError = '경로 정보를 불러올 수 없습니다';
        _lastRouteStateFetch = DateTime.now();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isRouteStateLoading = false;
      });
    }
  }


  Future<void> _updateMaskStateIfNeeded(WeatherProvider weatherProvider, AuthProvider authProvider) async {
    // 준비할 장소 리스트
    List<String> places = [];

    if (authProvider.isLoggedIn) {
      if (weatherProvider.currentLocationAddress != null) {
        places.add(weatherProvider.currentLocationAddress!);
      }
      if (authProvider.workAddress != null) {
        places.add(authProvider.workAddress!);
      }
      if (places.isEmpty) {
        places.add('서울 강남구');
      }
    } else {
      // 로그인 안 한 경우: 현재 위치가 한국인지 간단히 검사
      final addr = weatherProvider.currentLocationAddress;
      if (addr == null) {
        places = ['서울 강남구'];
      } else {
        final lower = addr.toLowerCase();
        if (lower.contains('korea') || lower.contains('대한민국') || lower.contains('한국')) {
          places = [addr];
        } else {
          places = ['서울 강남구'];
        }
      }
    }

    final key = places.join('|');
    if (key == _lastMaskKey) return; // 중복 호출 방지
    _lastMaskKey = key;

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final resp = await api.postAirMatch(places);
      final mask = resp != null && resp['mask_required'] == true;
      if (mounted) {
        setState(() {
          _maskRequired = mask;
        });
      }
    } catch (e) {
      print('마스크 상태 조회 오류: $e');
    }
  }

  Future<void> _searchRoute() async {
    if (_originController.text.isEmpty || _destinationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('출발지와 도착지를 모두 입력해주세요')),
      );
      return;
    }

    if (_originAddress == null || _destinationAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('주소 목록에서 주소를 선택해주세요'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 최근 검색에 추가
      context.read<RecentSearchProvider>().addSearch(
            _originAddress!,
            _destinationAddress!,
          );

      // 경로 검색 시작
      final routeProvider = context.read<RouteProvider>();
      await routeProvider.searchRoute(
        origin: _originAddress!,
        destination: _destinationAddress!,
      );

      // 로딩 닫기
      if (mounted) {
        Navigator.pop(context);
      }

      // 경로 검색 결과 확인
      if (routeProvider.error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(routeProvider.error!),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 경로 화면으로 이동 (검색 완료 후)
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RouteScreen(),
          ),
        );
      }
    } catch (e) {
      // 로딩 닫기
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('경로 검색 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getGreeting() {
    final now = DateTime.now();
    final hour = now.hour;
    if (hour >= 0 && hour < 6) {
      return '하루를 시작해볼까요?👋';
    } else if (hour >= 6 && hour < 12) {
      return '좋은 아침이에요👋';
    } else if (hour >= 12 && hour < 18) {
      return '좋은 오후에요👋';
    } else {
      return '좋은 저녁이에요👋';
    }
  }

  bool _isBeforeCommuteTime(AuthProvider authProvider) {
    final commuteTime = authProvider.commuteTime;
    if (commuteTime == null || commuteTime.isEmpty) {
      return false;
    }
    final parts = commuteTime.split(':');
    if (parts.length != 2) {
      return false;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return false;
    }
    final now = DateTime.now();
    final commuteAt = DateTime(now.year, now.month, now.day, hour, minute);
    return now.isBefore(commuteAt);
  }

  String _formatDurationMinutes(int totalSeconds) {
    final minutes = (totalSeconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rem = minutes % 60;
      return rem == 0 ? '${hours}시간' : '${hours}시간 ${rem}분';
    }
    return '${minutes}분';
  }

  String _formatDistanceKm(num meters) {
    final km = meters / 1000.0;
    return km >= 10 ? '${km.toStringAsFixed(0)}km' : '${km.toStringAsFixed(1)}km';
  }

  String _segmentLabel(Map<String, dynamic> segment) {
    final type = (segment['type'] ?? '').toString().toLowerCase();
    if (type == 'walk') {
      return '도보';
    }
    if (type == 'transit') {
      final transit = segment['transit'];
      if (transit is Map<String, dynamic>) {
        final vehicle = (transit['vehicle'] ?? '').toString().toUpperCase();
        switch (vehicle) {
          case 'BUS':
            return '버스';
          case 'SUBWAY':
            return '지하철';
          case 'TRAIN':
            return '기차';
        }
        final line = transit['line']?.toString();
        if (line != null && line.isNotEmpty) {
          return line;
        }
      }
      return '대중교통';
    }
    if (type == 'drive') {
      return '자동차';
    }
    if (type.isEmpty) {
      return '이동';
    }
    return type;
  }

  String _buildSegmentSummary(List<dynamic> segments) {
    final parts = <String>[];
    for (final segment in segments) {
      if (segment is! Map<String, dynamic>) continue;
      final durationSec = segment['duration_sec'];
      if (durationSec is! int) continue;
      parts.add('${_segmentLabel(segment)} ${_formatDurationMinutes(durationSec)}');
    }
    return parts.take(4).join(' · ');
  }

  Widget _buildCommuteRecommendationCard(AuthProvider authProvider) {
    if (!_isBeforeCommuteTime(authProvider)) {
      return const SizedBox.shrink();
    }

    if (_isRouteStateLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_routeStateError != null) {
      return Text(
        _routeStateError!,
        style: TextStyle(fontSize: 12, color: Colors.red.shade600),
      );
    }

    final route = _routeState?['route'];
    if (route is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }

    final totalDuration = route['total_duration_sec'] ?? _routeState?['total_duration_sec'];
    final totalDistance = route['total_distance_m'] ?? _routeState?['total_distance_m'];
    final segments = route['segments'] is List ? route['segments'] as List : <dynamic>[];
    final durationText = totalDuration is int ? _formatDurationMinutes(totalDuration) : '시간 정보 없음';
    final distanceText = totalDistance is num ? _formatDistanceKm(totalDistance) : '거리 정보 없음';
    final segmentSummary = _buildSegmentSummary(segments);
    final commuteTime = authProvider.commuteTime ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RouteScreen(
              initialOrigin: authProvider.homeAddress,
              initialDestination: authProvider.workAddress,
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.route,
                  color: Colors.blue.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '출근 $commuteTime 추천 경로',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$durationText · $distanceText',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (segmentSummary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        segmentSummary,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 인사말 및 로그인/로그아웃
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Consumer<AuthProvider>(
                        builder: (context, authProvider, _) {
                          final greeting = authProvider.isLoggedIn
                              ? '$_currentGreeting ${authProvider.name ?? authProvider.username ?? "사용자"}님'
                              : '$_currentGreeting 사용자님';
                          return Text(
                            greeting,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          );
                        },
                      ),
                    ),
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, _) {
                        if (authProvider.isLoggedIn) {
                          // 알림 설정 버튼과 로그아웃 버튼
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 알림 기록 버튼
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const NotificationHistoryScreen(),
                                    ),
                                  );
                                },
                                child: Tooltip(
                                  message: '알림 기록',
                                  child: Icon(
                                    Icons.history,
                                    size: 20,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 알림 설정 버튼
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const NotificationSettingsScreen(),
                                    ),
                                  );
                                },
                                child: Tooltip(
                                  message: '알림 설정',
                                  child: Icon(
                                    Icons.notifications,
                                    size: 20,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 로그아웃 버튼
                              GestureDetector(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('로그아웃'),
                                      content: const Text('로그아웃 하시겠습니까?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('취소'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            authProvider.logout();
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('로그아웃되었습니다'),
                                                backgroundColor: Colors.blue,
                                              ),
                                            );
                                          },
                                          child: const Text('로그아웃'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Tooltip(
                                  message: '로그아웃',
                                  child: Icon(
                                    Icons.logout,
                                    size: 20,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          );
                        } else {
                          // 로그인 버튼
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                            },
                            child: Tooltip(
                              message: '로그인',
                              child: Icon(
                                Icons.login,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  if (!authProvider.isLoggedIn) {
                    return const SizedBox.shrink();
                  }
                  _maybeLoadRouteState(authProvider);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildCommuteRecommendationCard(authProvider),
                  );
                },
              ),
              const SizedBox(height: 16),
              // 날씨 정보 카드
              Consumer<WeatherProvider>(
                builder: (context, weatherProvider, _) {
                  if (weatherProvider.isLoading) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    );
                  }

                  final weather = weatherProvider.weatherInfo;
                  if (weather == null) {
                    return const SizedBox.shrink();
                  }

                  // 마스크 상태 업데이트 (비동기 호출)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final authProvider = context.read<AuthProvider>();
                    _updateMaskStateIfNeeded(weatherProvider, authProvider);
                  });

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade600,
                              Colors.blue.shade700,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 위치 정보 및 마스크 아이콘
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  weather.location ?? '서울시 강남구',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // 온도 및 날씨 상태
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _getWeatherIcon(weather.condition, weather.weatherCategory, 48),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${weather.temperature == 0 ? '0' : weather.temperature.toStringAsFixed(0)}°',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                          height: 1,
                                        ),
                                      ),
                                      Text(
                                        weather.description,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 마스크 이미지 (오른쪽 끝)
                                Opacity(
                                  opacity: _maskRequired ? 1.0 : 0.35,
                                  child: Image.asset(
                                    'assets/images/mask.png',
                                    width: 40,
                                    height: 40,
                                    color: Colors.white,
                                    colorBlendMode: BlendMode.modulate,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // 상세 정보
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildWeatherDetail(
                                  Icons.water_drop,
                                  '습도 ${weather.humidity}%',
                                ),
                                _buildWeatherDetail(
                                  Icons.air,
                                  '바람 ${weather.windSpeed.toStringAsFixed(0)}m/s',
                                ),
                                _buildWeatherDetail(
                                  Icons.wb_sunny,
                                  '자외선 ${weather.uvIndex ?? "보통"}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // 빠른 경로 검색
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '빠른 경로 검색',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        AddressAutocompleteField(
                          controller: _originController,
                          hintText: '출발지',
                          dotColor: Colors.blue.shade700,
                          onAddressSelected: (address, lat, lng) {
                            setState(() {
                              _originAddress = address;
                              _originLat = lat;
                              _originLng = lng;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        AddressAutocompleteField(
                          controller: _destinationController,
                          hintText: '도착지',
                          dotColor: Colors.red.shade700,
                          onAddressSelected: (address, lat, lng) {
                            setState(() {
                              _destinationAddress = address;
                              _destLat = lat;
                              _destLng = lng;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _searchRoute,
                            icon: const Icon(Icons.search, color: Colors.white),
                            label: const Text(
                              '경로 검색',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 오늘의 추천
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '오늘의 추천 ✨',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RecommendationTabScreen(),
                              ),
                            );
                          },
                          child: const Text('더보기'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const RecommendationTabScreen(isCompact: true),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // 저장된 장소 또는 출근 경로
              Consumer<AuthProvider>(
                builder: (context, authProvider, _) {
                  final isLoggedIn = authProvider.isLoggedIn;
                  if (!isLoggedIn) {
                    return const SizedBox.shrink();
                  }
                  
                  // 로그인한 경우
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '출근',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _buildCommuteRouteCard(authProvider),
                        const SizedBox(height: 12),
                        Text(
                          '저장된 장소',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Consumer<SavedLocationProvider>(
                          builder: (context, provider, _) {
                            return SizedBox(
                              height: 100,
                              child: provider.locations.isEmpty
                                  ? const Center(
                                      child: Text('저장된 장소가 없습니다'),
                                    )
                                  : ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: provider.locations.length,
                                      itemBuilder: (context, index) {
                                        final location = provider.locations[index];
                                        return _buildSavedLocationCard(location);
                                      },
                                    ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // 최근 검색
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '최근 검색',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Consumer<RecentSearchProvider>(
                      builder: (context, provider, _) {
                        if (provider.searches.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('최근 검색 내역이 없습니다'),
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: provider.searches.length,
                          itemBuilder: (context, index) {
                            final search = provider.searches[index];
                            return _buildRecentSearchItem(search);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _getWeatherIcon(String condition, String? weatherCategory, double size) {
    IconData icon;
    Color color = Colors.white;

    // weatherCategory를 우선 확인 (한글 날씨 카테고리)
    if (weatherCategory != null) {
      final category = weatherCategory.toLowerCase();
      if (category.contains('비') || category.contains('rain')) {
        icon = Icons.umbrella;
      } else if (category.contains('눈') || category.contains('snow')) {
        icon = Icons.ac_unit;
      } else if (category.contains('흐림') || category.contains('cloud')) {
        icon = Icons.cloud;
      } else if (category.contains('맑음') || category.contains('화창') || category.contains('sunny') || category.contains('clear')) {
        icon = Icons.wb_sunny;
      } else {
        // condition으로 fallback
        switch (condition) {
          case 'rainy':
            icon = Icons.umbrella;
            break;
          case 'snowy':
            icon = Icons.ac_unit;
            break;
          case 'cloudy':
            icon = Icons.cloud;
            break;
          default:
            icon = Icons.wb_sunny;
        }
      }
    } else {
      // condition만 사용
    switch (condition) {
      case 'rainy':
        icon = Icons.umbrella;
        break;
      case 'snowy':
        icon = Icons.ac_unit;
        break;
      case 'cloudy':
        icon = Icons.cloud;
        break;
      default:
        icon = Icons.wb_sunny;
      }
    }

    return Icon(icon, color: color, size: size);
  }

  Widget _buildWeatherDetail(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildSavedLocationCard(SavedLocation location) {
    IconData icon;
    Color color;

    switch (location.type) {
      case 'home':
        icon = Icons.home;
        color = Colors.blue;
        break;
      case 'work':
        icon = Icons.work;
        color = Colors.orange;
        break;
      default:
        icon = Icons.favorite;
        color = Colors.red;
    }

    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                location.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  location.address,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommuteRouteCard(AuthProvider authProvider) {
    final homeAddress = authProvider.homeAddress ?? '집';
    final workAddress = authProvider.workAddress ?? '직장';
    
    // 도로명 주소부터만 추출하는 함수
    String _extractRoadName(String address) {
      // 주소 포맷: "시도 구군 (읍면동) 도로명 건물번호"
      final parts = address.split(' ');
      
      // 최소 3개 이상의 부분이 있어야 도로명이 있음
      if (parts.length >= 3) {
        // 처음 2개(시도, 구군)를 제외하고 나머지(도로명 이후)만 반환
        return parts.skip(2).join(' ').trim();
      }
      
      return address;
    }
    
    final homeRoadName = _extractRoadName(homeAddress);
    final workRoadName = _extractRoadName(workAddress);

    return GestureDetector(
      onTap: () {
        if (authProvider.homeAddress != null && authProvider.workAddress != null) {
          // 경로 검색 화면으로 직접 이동
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RouteScreen(
                initialOrigin: authProvider.homeAddress!,
                initialDestination: authProvider.workAddress!,
                originLat: authProvider.homeLatitude,
                originLng: authProvider.homeLongitude,
                destLat: authProvider.workLatitude,
                destLng: authProvider.workLongitude,
              ),
            ),
          );
        }
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_forward,
                  color: Colors.blue.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$homeRoadName → $workRoadName',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '집에서 직장으로 이동',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSearchItem(RecentSearch search) {
    String formattedDate;
    if (_isDateFormatInitialized) {
      final dateFormat = DateFormat('M월 d일 HH:mm', 'ko');
      formattedDate = dateFormat.format(search.searchTime);
    } else {
      // 초기화 전에는 영어 포맷 사용
      formattedDate = DateFormat('MMM d, HH:mm').format(search.searchTime);
    }
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.history,
            color: Colors.blue.shade700,
            size: 20,
          ),
        ),
        title: Text(
          '${search.origin} → ${search.destination}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          formattedDate,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
        onTap: () {
          _originController.text = search.origin;
          _destinationController.text = search.destination;
          _searchRoute();
        },
      ),
    );
  }
}
