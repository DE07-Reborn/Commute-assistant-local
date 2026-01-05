import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_history_item.dart';
import '../providers/auth_provider.dart';
import '../providers/event_settings_provider.dart';
import '../providers/notification_history_provider.dart';
import '../services/api_service.dart';
import '../screens/recommendation_tab_screen.dart';
import '../screens/route_screen.dart';

class NotificationService {
  NotificationService({
    required GlobalKey<NavigatorState> navigatorKey,
    this.testMode = false,
  }) : _navigatorKey = navigatorKey;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final GlobalKey<NavigatorState> _navigatorKey;
  final bool testMode;

  Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    print('[Notification] initialize start');
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'route_approval',
          actions: [
            DarwinNotificationAction.plain(
              'approve_route',
              '경로 승인',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    await _requestPermissions();
    print('[Notification] initialize done');
  }

  Future<void> _requestPermissions() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  Future<void> scheduleCommuteNotifications({
    required DateTime departAt,
  }) async {
    print('[Notification] schedule start departAt=$departAt testMode=$testMode');
    await _plugin.cancelAll();
    final settings = await _loadEventSettings();

    final DateTime baseTime = testMode
        ? DateTime.now().add(const Duration(seconds: 40))
        : departAt;

    final Duration minusThirty = testMode
        ? const Duration(seconds: 30)
        : const Duration(minutes: 30);
    final Duration minusFifteen = testMode
        ? const Duration(seconds: 15)
        : const Duration(minutes: 15);
    final Duration minusFive = testMode
        ? const Duration(seconds: 5)
        : const Duration(minutes: 5);
    final Duration plusTen = testMode
        ? const Duration(seconds: 10)
        : const Duration(minutes: 10);

    print('[Notification] baseTime=$baseTime');
    if (settings.notifyBeforeDeparture) {
      await _scheduleNotification(
        id: 1001,
        type: 'route',
        scheduledAt: baseTime.subtract(minusThirty),
        title: '추천 경로가 준비됐어요',
        body: '경로를 확인하고 승인해주세요.',
        withApprovalAction: true,
      );
    }

    if (settings.notifyClothing) {
      await _scheduleNotification(
        id: 1002,
        type: 'weather',
        scheduledAt: baseTime.subtract(minusFifteen),
        title: '날씨/옷 추천',
        body: '출발 전에 오늘 옷차림을 확인하세요.',
      );
    }

    if (settings.notifyMask || settings.notifyUmbrella) {
      final maskContent = _maskNotificationContent(
        settings.notifyMask,
        settings.notifyUmbrella,
      );
      await _scheduleNotification(
        id: 1003,
        type: 'mask',
        scheduledAt: baseTime.subtract(minusFive),
        title: maskContent.title,
        body: maskContent.body,
      );
    }

    if (settings.notifyBeforeDeparture) {
      await _scheduleNotification(
        id: 1004,
        type: 'depart',
        scheduledAt: baseTime,
        title: '출발 시간이에요',
        body: '추천 경로로 출발하세요.',
      );
    }

    if (settings.notifyMusic || settings.notifyBook) {
      final mediaContent = _mediaNotificationContent(
        settings.notifyMusic,
        settings.notifyBook,
      );
      await _scheduleNotification(
        id: 1005,
        type: 'music',
        scheduledAt: baseTime.add(plusTen),
        title: mediaContent.title,
        body: mediaContent.body,
      );
    }
    print('[Notification] schedule done');
  }

  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
    print('[Notification] canceled all');
  }

  Future<_EventNotificationSettings> _loadEventSettings() async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return const _EventNotificationSettings();
    }

    final authProvider = context.read<AuthProvider>();
    final eventProvider = context.read<EventSettingsProvider>();
    final userId = authProvider.userId;
    if (userId != null) {
      await eventProvider.loadEventSettings(userId);
    }

    return _EventNotificationSettings(
      notifyBeforeDeparture: eventProvider.notifyBeforeDeparture,
      notifyMask: eventProvider.notifyMask,
      notifyUmbrella: eventProvider.notifyUmbrella,
      notifyClothing: eventProvider.notifyClothing,
      notifyMusic: eventProvider.notifyMusic,
      notifyBook: eventProvider.notifyBook,
    );
  }

  Future<void> _scheduleNotification({
    required int id,
    required String type,
    required DateTime scheduledAt,
    required String title,
    required String body,
    bool withApprovalAction = false,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final target = tz.TZDateTime.from(scheduledAt, tz.local);
    if (target.isBefore(now)) {
      print('[Notification] skip id=$id type=$type target=$target now=$now');
      return;
    }

    print('[Notification] scheduling id=$id type=$type target=$target');
    final payload = json.encode({'type': type});

    final androidDetails = AndroidNotificationDetails(
      'commute_notifications',
      'Commute Notifications',
      channelDescription: '출퇴근 알림',
      importance: Importance.max,
      priority: Priority.high,
      actions: withApprovalAction
          ? [
              const AndroidNotificationAction(
                'approve_route',
                '경로 승인',
                showsUserInterface: true,
              ),
            ]
          : null,
    );

    final iosDetails = DarwinNotificationDetails(
      categoryIdentifier: withApprovalAction ? 'route_approval' : null,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      target,
      notificationDetails,
      payload: payload,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    print('[Notification] scheduled id=$id type=$type');
  }

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
    final type = _parseType(response.payload);
    if (type != null) {
      _recordHistory(type);
    }

    if (response.actionId == 'approve_route') {
      await _approveRouteFromNotification();
      _navigateToRoute(autoApprove: true);
      return;
    }

    _navigateByType(type);
  }

  String? _parseType(String? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }
    try {
      final data = json.decode(payload) as Map<String, dynamic>;
      return data['type'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _approveRouteFromNotification() async {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final apiService = context.read<ApiService>();
    final userId = authProvider.userId;
    if (userId == null) {
      return;
    }

    try {
      final routeState = await apiService.getRouteState(userId);
      final departAt = routeState?['depart_at']?.toString();
      if (departAt == null || departAt.isEmpty) {
        return;
      }
      await apiService.approveRoute(userId: userId, departAt: departAt);
    } catch (e) {
      print('[Notification] approve route error: $e');
    }
  }

  void _navigateByType(String? type) {
    switch (type) {
      case 'route':
        _navigateToRoute(showApprovalPrompt: true);
        break;
      case 'depart':
        _navigateToRoute();
        break;
      case 'weather':
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const RecommendationTabScreen(
              initialTabIndex: 0,
              highlightMessage: '날씨와 옷차림을 확인하세요.',
            ),
          ),
        );
        break;
      case 'mask':
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const RecommendationTabScreen(
              initialTabIndex: 0,
              highlightMessage: '마스크/우산 필요 여부를 확인하세요.',
            ),
          ),
        );
        break;
      case 'music':
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const RecommendationTabScreen(
              initialTabIndex: 2,
              highlightMessage: '음악/도서 추천을 확인하세요.',
            ),
          ),
        );
        break;
      default:
        _navigateToRoute();
    }
  }

  void _navigateToRoute({bool showApprovalPrompt = false, bool autoApprove = false}) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          showApprovalPrompt: showApprovalPrompt,
          autoApprove: autoApprove,
        ),
      ),
    );
  }

  void _recordHistory(String type) {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final content = _defaultNotificationContent(type);
    final historyProvider = context.read<NotificationHistoryProvider>();
    historyProvider.addItem(
      NotificationHistoryItem(
        type: type,
        title: content.title,
        body: content.body,
        receivedAt: DateTime.now(),
      ),
    );
  }

  _NotificationContent _defaultNotificationContent(String type) {
    switch (type) {
      case 'route':
        return const _NotificationContent(
          title: '추천 경로가 준비됐어요',
          body: '경로를 확인하고 승인해주세요.',
        );
      case 'weather':
        return const _NotificationContent(
          title: '날씨/옷 추천',
          body: '출발 전에 오늘 옷차림을 확인하세요.',
        );
      case 'mask':
        return const _NotificationContent(
          title: '마스크/우산 체크',
          body: '마스크 또는 우산이 필요할 수 있어요.',
        );
      case 'depart':
        return const _NotificationContent(
          title: '출발 시간이에요',
          body: '추천 경로로 출발하세요.',
        );
      case 'music':
        return const _NotificationContent(
          title: '음악/도서 추천',
          body: '이동 중 즐길 콘텐츠를 확인하세요.',
        );
      default:
        return const _NotificationContent(
          title: '알림',
          body: '알림을 확인하세요.',
        );
    }
  }
}

class _NotificationContent {
  final String title;
  final String body;

  const _NotificationContent({required this.title, required this.body});
}

class _EventNotificationSettings {
  final bool notifyBeforeDeparture;
  final bool notifyMask;
  final bool notifyUmbrella;
  final bool notifyClothing;
  final bool notifyMusic;
  final bool notifyBook;

  const _EventNotificationSettings({
    this.notifyBeforeDeparture = true,
    this.notifyMask = true,
    this.notifyUmbrella = true,
    this.notifyClothing = true,
    this.notifyMusic = true,
    this.notifyBook = true,
  });
}

_NotificationContent _maskNotificationContent(bool notifyMask, bool notifyUmbrella) {
  if (notifyMask && notifyUmbrella) {
    return const _NotificationContent(
      title: '마스크/우산 체크',
      body: '마스크 또는 우산이 필요할 수 있어요.',
    );
  }
  if (notifyMask) {
    return const _NotificationContent(
      title: '마스크 체크',
      body: '마스크가 필요할 수 있어요.',
    );
  }
  return const _NotificationContent(
    title: '우산 체크',
    body: '우산이 필요할 수 있어요.',
  );
}

_NotificationContent _mediaNotificationContent(bool notifyMusic, bool notifyBook) {
  if (notifyMusic && notifyBook) {
    return const _NotificationContent(
      title: '음악/도서 추천',
      body: '이동 중 즐길 콘텐츠를 확인하세요.',
    );
  }
  if (notifyMusic) {
    return const _NotificationContent(
      title: '음악 추천',
      body: '이동 중 들을 음악을 확인하세요.',
    );
  }
  return const _NotificationContent(
    title: '도서 추천',
    body: '이동 중 읽을 도서를 확인하세요.',
  );
}
