import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/route_provider.dart';
import '../models/route_info.dart';

class RouteScreen extends StatefulWidget {
  final String? initialOrigin;
  final String? initialDestination;
  final double? originLat;
  final double? originLng;
  final double? destLat;
  final double? destLng;

  const RouteScreen({
    super.key,
    this.initialOrigin,
    this.initialDestination,
    this.originLat,
    this.originLng,
    this.destLat,
    this.destLng,
  });

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  RouteInfo? _lastRouteInfo;
  final DraggableScrollableController _draggableController = DraggableScrollableController();
  bool _isPanelExpanded = false;

  @override
  void initState() {
    super.initState();
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
    
    // 초기값이 있으면 경로 검색 수행
    if (widget.initialOrigin != null && widget.initialDestination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final routeProvider = context.read<RouteProvider>();
          routeProvider.searchRoute(
            origin: widget.initialOrigin!,
            destination: widget.initialDestination!,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _draggableController.dispose();
    super.dispose();
  }

  void _updateMap(RouteInfo? routeInfo) {
    if (routeInfo == null) return;
    
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
            return const Center(child: CircularProgressIndicator());
          }

          if (routeProvider.error != null) {
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
            if (_mapController != null) {
              _updateMap(routeInfo);
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
                                            }),
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
          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(37.5665, 126.9780),
              zoom: 12,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          );
        },
      ),
    );
  }
}

