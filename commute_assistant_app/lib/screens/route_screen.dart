import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/route_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/route_info.dart';

class RouteScreen extends StatefulWidget {
  final String? initialOrigin;
  final String? initialDestination;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;
  final bool showApprovalPrompt;
  final bool autoApprove;

  const RouteScreen({
    super.key,
    this.initialOrigin,
    this.initialDestination,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
    this.showApprovalPrompt = false,
    this.autoApprove = false,
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  RouteInfo? _lastRouteInfo;
  final DraggableScrollableController _draggableController = DraggableScrollableController();
  bool _isPanelExpanded = false;
  bool _routeApproved = false;
  bool _isMapReady = false;
  bool _isApproving = false;
  DateTime? _departAt;
  DateTime? _arriveBy;
  String? _targetCountdown;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoApprove) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _approveRoute(auto: true);
      });
    }
    // 드래그 패널 크기 변경 리스너
    _draggableController.addListener(() {
      if (_draggableController.isAttached) {
        final size = _draggableController.size;
        final newExpanded = size > 0.4;
        if (mounted && newExpanded != _isPanelExpanded) {
          setState(() {
            _isPanelExpanded = newExpanded;
          });
        }
      }
    });

    _loadInitialRoute();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _mapController = null;
    _isMapReady = false;
    _countdownTimer?.cancel();
    _draggableController.dispose();
    super.dispose();
  }

  void _loadInitialRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final routeProvider = context.read<RouteProvider>();
      if (routeProvider.routeInfo != null || routeProvider.isLoading) {
        return;
      }

      final authProvider = context.read<AuthProvider>();
      final origin = widget.initialOrigin ?? authProvider.homeAddress;
      final destination = widget.initialDestination ?? authProvider.workAddress;
      if (origin == null || destination == null) {
        return;
      }

      await routeProvider.searchRoute(
        origin: origin,
        destination: destination,
      );
    });
  }

  Future<void> _approveRoute({bool auto = false}) async {
    if (_isApproving) return;
    setState(() {
      _isApproving = true;
    });

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.userId;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _isApproving = false;
        });
      }
      return;
    }

    final apiService = context.read<ApiService>();
    try {
      final routeState = await apiService.getRouteState(userId);
      final departAtRaw = routeState?['depart_at']?.toString();
      final arriveByRaw = routeState?['arrive_by']?.toString();
      if (departAtRaw == null || departAtRaw.isEmpty) {
        return;
      }

      await apiService.approveRoute(
        userId: userId,
        departAt: departAtRaw,
      );

      _departAt = _parseServerTime(departAtRaw);
      _arriveBy = _parseServerTime(arriveByRaw);
      _startCountdown();

      if (!mounted) return;
      setState(() {
        _routeApproved = true;
      });
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('경로를 승인했어요.'),
          ),
        );
      }
    } catch (e) {
      print('경로 승인 저장 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isApproving = false;
        });
      }
    }
  }

  void _startDepartCountdown() {
    _startCountdown();
  }

  DateTime? _parseServerTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (!mounted) return;
    final target = _arriveBy ?? _departAt;
    if (target == null) return;
    final formatted = _formatCountdown(target);
    setState(() {
      _targetCountdown = formatted;
    });
  }

  String _formatCountdown(DateTime targetTime) {
    final diff = targetTime.difference(DateTime.now());
    if (diff.inMinutes <= 0) {
      return '지금 출발하세요';
    }
    if (diff.inHours >= 1) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      return '${hours}시간 ${minutes}분 남음';
    }
    return '${diff.inMinutes}분 남음';
  }

  void _updateMap(RouteInfo? routeInfo) {
    if (!mounted || !_isMapReady || _mapController == null || routeInfo == null) {
      return;
    }
    
    // 같은 경로 정보면 업데이트하지 않음
    if (_lastRouteInfo == routeInfo) return;
    _lastRouteInfo = routeInfo;

    _markers.clear();
    _polylines.clear();

    // 출발지 마커
    _markers.add(
      Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(routeInfo.originLat, routeInfo.originLng),
        infoWindow: InfoWindow(title: '출발지', snippet: routeInfo.origin),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    // 도착지 마커
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(routeInfo.destLat, routeInfo.destLng),
        infoWindow: InfoWindow(title: '도착지', snippet: routeInfo.destination),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    // 실제 경로 폴리라인
    if (routeInfo.routePoints.isNotEmpty) {
      final points = routeInfo.routePoints
          .map((point) => LatLng(point.lat, point.lng))
          .toList();
      
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: Colors.blue,
          width: 5,
          geodesic: true,
        ),
      );
    } else {
      // 경로 포인트가 없으면 직선으로 표시
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [
            LatLng(routeInfo.originLat, routeInfo.originLng),
            LatLng(routeInfo.destLat, routeInfo.destLng),
          ],
          color: Colors.blue,
          width: 5,
        ),
      );
    }

    // 지도 중심 이동
    final bounds = LatLngBounds(
      southwest: LatLng(
        routeInfo.originLat < routeInfo.destLat
            ? routeInfo.originLat
            : routeInfo.destLat,
        routeInfo.originLng < routeInfo.destLng
            ? routeInfo.originLng
            : routeInfo.destLng,
      ),
      northeast: LatLng(
        routeInfo.originLat > routeInfo.destLat
            ? routeInfo.originLat
            : routeInfo.destLat,
        routeInfo.originLng > routeInfo.destLng
            ? routeInfo.originLng
            : routeInfo.destLng,
      ),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );

    setState(() {});
  }

  IconData _getTravelModeIcon(String mode) {
    switch (mode) {
      case 'driving':
        return Icons.directions_car;
      case 'walking':
        return Icons.directions_walk;
      case 'bicycling':
        return Icons.directions_bike;
      case 'transit':
        return Icons.directions_transit;
      default:
        return Icons.route;
    }
  }

  String _getTravelModeName(String mode) {
    switch (mode) {
      case 'driving':
        return '자가용';
      case 'walking':
        return '걷기';
      case 'bicycling':
        return '자전거';
      case 'transit':
        return '대중교통';
      default:
        return '경로';
    }
  }

  Color _getTravelModeColor(String mode) {
    switch (mode) {
      case 'driving':
        return Colors.purple;
      case 'walking':
        return Colors.green;
      case 'bicycling':
        return Colors.orange;
      case 'transit':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildApprovedBanner(RouteInfo routeInfo) {
    final departAt = _departAt;
    final arriveBy = _arriveBy;
    final arriveText = arriveBy != null
        ? DateFormat('HH:mm', 'ko').format(arriveBy)
        : null;
    final departText = departAt != null
        ? DateFormat('HH:mm', 'ko').format(departAt)
        : null;
    final countdown = _targetCountdown ??
        ((arriveBy ?? departAt) != null ? _formatCountdown(arriveBy ?? departAt!) : null);
    final summary = '${_getTravelModeName(routeInfo.travelMode)} · ${routeInfo.duration} · ${routeInfo.distance}';

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.schedule,
              color: Colors.blue.shade700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    arriveText != null ? '출근 시간 $arriveText' : '출근 시간 확인 중',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  if (departText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '출발 시간 $departText',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                  if (countdown != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      countdown,
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 검색'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Consumer<RouteProvider>(
        builder: (context, routeProvider, _) {
          if (routeProvider.isLoading) {
            _mapController = null;
            _isMapReady = false;
            return const Center(child: CircularProgressIndicator());
          }

          if (routeProvider.error != null) {
            _mapController = null;
            _isMapReady = false;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      routeProvider.error!,
                      style: TextStyle(color: Colors.red.shade700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('돌아가기'),
                  ),
                ],
              ),
            );
          }

          final routeInfo = routeProvider.routeInfo;
          if (routeInfo != null) {
            // 경로 정보가 있으면 지도 업데이트
            if (_lastRouteInfo != routeInfo) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateMap(routeInfo);
              });
            }
            
            return Stack(
              children: [
                // 지도 (전체 화면)
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(routeInfo.originLat, routeInfo.originLng),
                    zoom: 12,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _isMapReady = true;
                    // 지도가 준비되면 경로 정보 업데이트
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && routeProvider.routeInfo != null) {
                        _updateMap(routeProvider.routeInfo);
                      }
                    });
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                if (widget.showApprovalPrompt && !_routeApproved)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.route,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '추천 경로가 준비됐어요. 승인하면 알림이 이어집니다.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _isApproving ? null : () => _approveRoute(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('승인'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_routeApproved)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: _buildApprovedBanner(routeInfo),
                  ),
                // 드래그 가능한 경로 옵션 패널
                DraggableScrollableSheet(
                  controller: _draggableController,
                  initialChildSize: 0.3, // 초기 높이 (30%)
                  minChildSize: 0.15, // 최소 높이 (15%)
                  maxChildSize: 0.9, // 최대 높이 (90%)
                  snap: true,
                  snapSizes: const [0.15, 0.6, 0.9],
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 드래그 핸들
                          Container(
                            margin: const EdgeInsets.only(top: 12, bottom: 8),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          // 헤더
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '경로 옵션 (${routeProvider.routes.length}개)',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _isPanelExpanded
                                            ? Icons.keyboard_arrow_down
                                            : Icons.keyboard_arrow_up,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isPanelExpanded = !_isPanelExpanded;
                                        });
                                        if (_draggableController.isAttached) {
                                          if (_isPanelExpanded) {
                                            _draggableController.animateTo(
                                              0.6,
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          } else {
                                            _draggableController.animateTo(
                                              0.15,
                                              duration: const Duration(milliseconds: 300),
                                              curve: Curves.easeInOut,
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                if (routeProvider.routes.length < 4)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '일부 이동 수단의 경로를 찾을 수 없습니다.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(),
                          // 경로 목록
                          Expanded(
                            child: ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: routeProvider.routes.length,
                              itemBuilder: (context, index) {
                                final route = routeProvider.routes[index];
                                final isSelected = routeProvider.routeInfo == route;
                                
                                return GestureDetector(
                                  onTap: () {
                                    routeProvider.selectRoute(route);
                                    _updateMap(route);
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: isSelected ? 4 : 1,
                                    color: isSelected 
                                        ? Colors.blue.shade50 
                                        : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isSelected 
                                            ? Colors.blue.shade700 
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    _getTravelModeIcon(route.travelMode),
                                                    color: isSelected 
                                                        ? Colors.blue.shade700 
                                                        : Colors.grey.shade600,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        _getTravelModeName(route.travelMode),
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 16,
                                                          color: isSelected 
                                                              ? Colors.blue.shade700 
                                                              : Colors.black,
                                                        ),
                                                      ),
                                                      Text(
                                                        '경로 ${index + 1}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey.shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              if (isSelected)
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.blue.shade700,
                                                  size: 24,
                                                ),
                                            ],
                                          ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _getTravelModeColor(route.travelMode).withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _getTravelModeIcon(route.travelMode),
                                                    size: 16,
                                                    color: _getTravelModeColor(route.travelMode),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _getTravelModeName(route.travelMode),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: _getTravelModeColor(route.travelMode),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            Icon(Icons.straighten,
                                                size: 18, color: Colors.grey.shade600),
                                            const SizedBox(width: 8),
                                            Text(
                                              route.distance,
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(width: 16),
                                            Icon(Icons.access_time,
                                                size: 18, color: Colors.grey.shade600),
                                            const SizedBox(width: 8),
                                            Text(
                                              route.duration,
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                          ],
                                        ),
                                          if (route.transitOptions.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            const Divider(height: 1),
                                            const SizedBox(height: 8),
                                            Text(
                                              '대중교통 상세 경로',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ...route.transitOptions.asMap().entries.map<Widget>((entry) {
                                              final index = entry.key;
                                              final transit = entry.value;
                                              final isLast = index == route.transitOptions.length - 1;
                                              
                                              return Column(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: transit.type == 'bus'
                                                          ? Colors.blue.shade50
                                                          : Colors.orange.shade50,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: transit.type == 'bus'
                                                            ? Colors.blue.shade200
                                                            : Colors.orange.shade200,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        // 아이콘
                                                        Container(
                                                          width: 40,
                                                          height: 40,
                                                          decoration: BoxDecoration(
                                                            color: transit.type == 'bus'
                                                                ? Colors.blue
                                                                : Colors.orange,
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Icon(
                                                            transit.type == 'bus'
                                                                ? Icons.directions_bus
                                                                : Icons.train,
                                                            color: Colors.white,
                                                            size: 20,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        // 정보
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Text(
                                                                    transit.name,
                                                                    style: const TextStyle(
                                                                      fontSize: 16,
                                                                      fontWeight: FontWeight.bold,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 8),
                                                                  Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal: 6,
                                                                      vertical: 2,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: transit.type == 'bus'
                                                                          ? Colors.blue.shade100
                                                                          : Colors.orange.shade100,
                                                                      borderRadius: BorderRadius.circular(4),
                                                                    ),
                                                                    child: Text(
                                                                      transit.type == 'bus' ? '버스' : '지하철',
                                                                      style: TextStyle(
                                                                        fontSize: 10,
                                                                        fontWeight: FontWeight.w600,
                                                                        color: transit.type == 'bus'
                                                                            ? Colors.blue.shade900
                                                                            : Colors.orange.shade900,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 4),
                                                              Text(
                                                                '${transit.stationName} → ${transit.departureStationName}',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors.grey.shade700,
                                                                ),
                                                              ),
                                                              if (transit.duration.isNotEmpty || transit.numStops > 0) ...[
                                                                const SizedBox(height: 4),
                                                                Row(
                                                                  children: [
                                                                    if (transit.duration.isNotEmpty) ...[
                                                                      Icon(
                                                                        Icons.access_time,
                                                                        size: 12,
                                                                        color: Colors.grey.shade600,
                                                                      ),
                                                                      const SizedBox(width: 4),
                                                                      Text(
                                                                        transit.duration,
                                                                        style: TextStyle(
                                                                          fontSize: 11,
                                                                          color: Colors.grey.shade600,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                    if (transit.numStops > 0) ...[
                                                                      if (transit.duration.isNotEmpty)
                                                                        const SizedBox(width: 12),
                                                                      Icon(
                                                                        Icons.stop_circle,
                                                                        size: 12,
                                                                        color: Colors.grey.shade600,
                                                                      ),
                                                                      const SizedBox(width: 4),
                                                                      Text(
                                                                        '${transit.numStops}개 역',
                                                                        style: TextStyle(
                                                                          fontSize: 11,
                                                                          color: Colors.grey.shade600,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ],
                                                                ),
                                                              ],
                                                              if (transit.departureTime.isNotEmpty) ...[
                                                                const SizedBox(height: 4),
                                                                Row(
                                                                  children: [
                                                                    Icon(
                                                                      Icons.schedule,
                                                                      size: 12,
                                                                      color: Colors.grey.shade600,
                                                                    ),
                                                                    const SizedBox(width: 4),
                                                                    Text(
                                                                      '출발: ${transit.departureTime}',
                                                                      style: TextStyle(
                                                                        fontSize: 11,
                                                                        color: Colors.grey.shade600,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 12),
                                                                    Text(
                                                                      '도착: ${transit.arrivalTime}',
                                                                      style: TextStyle(
                                                                        fontSize: 11,
                                                                        color: Colors.grey.shade600,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // 환승 표시 (마지막이 아닌 경우)
                                                  if (!isLast) ...[
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        const SizedBox(width: 20),
                                                        Container(
                                                          width: 2,
                                                          height: 20,
                                                          color: Colors.grey.shade300,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.grey.shade200,
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(
                                                                Icons.swap_horiz,
                                                                size: 12,
                                                                color: Colors.grey.shade700,
                                                              ),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                '환승',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors.grey.shade700,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                  ],
                                                ],
                                              );
                                            }).toList(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          }

          // 초기 상태
          _mapController = null;
          _isMapReady = false;
          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(37.5665, 126.9780),
              zoom: 12,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _isMapReady = true;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          );
        },
      ),
    );
  }
}
