import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/notification_history_item.dart';
import '../providers/notification_history_provider.dart';
import 'recommendation_tab_screen.dart';
import 'route_screen.dart';

class NotificationHistoryScreen extends StatelessWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 기록'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '전체 삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              context.read<NotificationHistoryProvider>().clear();
            },
          ),
        ],
      ),
      body: Consumer<NotificationHistoryProvider>(
        builder: (context, provider, _) {
          if (provider.items.isEmpty) {
            return Center(
              child: Text(
                '알림 기록이 없습니다.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = provider.items[index];
              final formattedTime =
                  DateFormat('M월 d일 HH:mm', 'ko').format(item.receivedAt);

              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: _buildTypeIcon(item.type),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(item.body),
                      const SizedBox(height: 6),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  trailing: Icon(Icons.arrow_forward_ios,
                      size: 16, color: Colors.grey.shade400),
                  onTap: () => _navigateByType(context, item.type),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTypeIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'route':
        icon = Icons.route;
        color = Colors.blue;
        break;
      case 'depart':
        icon = Icons.departure_board;
        color = Colors.indigo;
        break;
      case 'weather':
        icon = Icons.checkroom;
        color = Colors.orange;
        break;
      case 'mask':
        icon = Icons.masks;
        color = Colors.green;
        break;
      case 'music':
        icon = Icons.music_note;
        color = Colors.purple;
        break;
      default:
        icon = Icons.notifications;
        color = Colors.grey;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _navigateByType(BuildContext context, String type) {
    switch (type) {
      case 'route':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RouteScreen(showApprovalPrompt: true),
          ),
        );
        break;
      case 'depart':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RouteScreen(),
          ),
        );
        break;
      case 'weather':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RecommendationTabScreen(
              initialTabIndex: 0,
              highlightMessage: '날씨와 옷차림을 확인하세요.',
            ),
          ),
        );
        break;
      case 'mask':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RecommendationTabScreen(
              initialTabIndex: 0,
              highlightMessage: '마스크/우산 필요 여부를 확인하세요.',
            ),
          ),
        );
        break;
      case 'music':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RecommendationTabScreen(
              initialTabIndex: 2,
              highlightMessage: '음악/도서 추천을 확인하세요.',
            ),
          ),
        );
        break;
      default:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RouteScreen(),
          ),
        );
    }
  }
}
