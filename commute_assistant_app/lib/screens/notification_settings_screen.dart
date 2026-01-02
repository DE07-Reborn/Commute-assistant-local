import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/event_settings_provider.dart';
import '../providers/auth_provider.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // 화면 진입 시 알림 설정 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final userId = authProvider.userId;
      if (userId != null) {
        context.read<EventSettingsProvider>().loadEventSettings(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 설정'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Consumer<EventSettingsProvider>(
        builder: (context, eventProvider, _) {
          if (eventProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 알림 설정 설명
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '알림 설정을 변경하면 즉시 저장됩니다',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 출발 전 알림
                  _buildSettingTile(
                    context: context,
                    title: '출발 전 알림',
                    description: '출발 시간 전에 알림을 받습니다',
                    icon: Icons.departure_board,
                    value: eventProvider.notifyBeforeDeparture,
                    onChanged: (value) async {
                      final authProvider = context.read<AuthProvider>();
                      final userId = authProvider.userId;
                      if (userId != null) {
                        await eventProvider.setNotifyBeforeDeparture(userId, value);
                        if (eventProvider.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('오류: ${eventProvider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  // 마스크 알림
                  _buildSettingTile(
                    context: context,
                    title: '마스크 알림',
                    description: '마스크 착용이 필요한 날씨를 알립니다',
                    icon: Icons.health_and_safety,
                    value: eventProvider.notifyMask,
                    onChanged: (value) async {
                      final authProvider = context.read<AuthProvider>();
                      final userId = authProvider.userId;
                      if (userId != null) {
                        await eventProvider.setNotifyMask(userId, value);
                        if (eventProvider.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('오류: ${eventProvider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  // 우산 알림
                  _buildSettingTile(
                    context: context,
                    title: '우산 알림',
                    description: '우산이 필요한 날씨를 알립니다',
                    icon: Icons.umbrella,
                    value: eventProvider.notifyUmbrella,
                    onChanged: (value) async {
                      final authProvider = context.read<AuthProvider>();
                      final userId = authProvider.userId;
                      if (userId != null) {
                        await eventProvider.setNotifyUmbrella(userId, value);
                        if (eventProvider.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('오류: ${eventProvider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  // 옷차림 알림
                  _buildSettingTile(
                    context: context,
                    title: '옷차림 알림',
                    description: '날씨에 맞는 옷차림을 추천합니다',
                    icon: Icons.checkroom,
                    value: eventProvider.notifyClothing,
                    onChanged: (value) async {
                      final authProvider = context.read<AuthProvider>();
                      final userId = authProvider.userId;
                      if (userId != null) {
                        await eventProvider.setNotifyClothing(userId, value);
                        if (eventProvider.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('오류: ${eventProvider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  // 음악 추천 알림
                  _buildSettingTile(
                    context: context,
                    title: '음악 추천',
                    description: '날씨에 맞는 음악을 추천합니다',
                    icon: Icons.music_note,
                    value: eventProvider.notifyMusic,
                    onChanged: (value) async {
                      final authProvider = context.read<AuthProvider>();
                      final userId = authProvider.userId;
                      if (userId != null) {
                        await eventProvider.setNotifyMusic(userId, value);
                        if (eventProvider.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('오류: ${eventProvider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                  // 도서 추천 알림
                  _buildSettingTile(
                    context: context,
                    title: '도서 추천',
                    description: '날씨에 맞는 도서를 추천합니다',
                    icon: Icons.library_books,
                    value: eventProvider.notifyBook,
                    onChanged: (value) async {
                      final authProvider = context.read<AuthProvider>();
                      final userId = authProvider.userId;
                      if (userId != null) {
                        await eventProvider.setNotifyBook(userId, value);
                        if (eventProvider.error != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('오류: ${eventProvider.error}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingTile({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.blue,
        ),
      ),
    );
  }
}
