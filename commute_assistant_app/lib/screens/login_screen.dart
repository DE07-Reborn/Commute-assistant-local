import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/weather_provider.dart';
import '../services/api_service.dart';
import '../main.dart';
import '../services/notification_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (mounted) {
      if (success) {
        // 날씨 정보 다시 로드
        final weatherProvider = context.read<WeatherProvider>();
        weatherProvider.loadWeather();

        await _scheduleCommuteNotifications();
        
        Navigator.of(context).pop(); // 로그인 화면 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그인 성공'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? '로그인에 실패했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _scheduleCommuteNotifications() async {
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.userId;
    if (userId == null) {
      print('[Notification] schedule aborted: userId is null');
      return;
    }

    final apiService = context.read<ApiService>();
    final notificationService = context.read<NotificationService>();

    try {
      print('[Notification] fetching route state userId=$userId');
      final routeState = await apiService.getRouteState(userId);
      if (routeState == null) {
        print('[Notification] routeState is null');
        return;
      }

      final departAtRaw = routeState['depart_at']?.toString();
      if (departAtRaw == null || departAtRaw.isEmpty) {
        print('[Notification] depart_at missing in routeState=$routeState');
        return;
      }

      final parsed = DateTime.tryParse(departAtRaw);
      if (parsed == null) {
        print('[Notification] depart_at parse failed: $departAtRaw');
        return;
      }
      final departAt = parsed.isUtc ? parsed.toLocal() : parsed;

      print('[Notification] routeState depart_at=$departAt');
      // Trigger FCM scheduling via route update (test_mode=true).
      await apiService.saveRouteState(
        userId: userId,
        departAt: departAt.toIso8601String(),
        testMode: kNotificationTestMode,
      );
      // Local notifications disabled while using FCM.
      // await notificationService.scheduleCommuteNotifications(
      //   departAt: departAt,
      // );
      // await notificationService.showTestNotification();
      // await notificationService.showAfterDelay();
    } catch (e) {
      print('[Notification] schedule error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('로그인'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // 로고 또는 타이틀
                Icon(
                  Icons.person,
                  size: 80,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(height: 24),
                Text(
                  '출퇴근 도우미',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                ),
                const SizedBox(height: 48),
                // 아이디 입력
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: '아이디',
                    hintText: '아이디를 입력하세요',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '아이디를 입력해주세요';
                    }
                    if (value.length < 4) {
                      return '아이디는 4자 이상이어야 합니다';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                // 비밀번호 입력
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    hintText: '비밀번호를 입력하세요',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '비밀번호를 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                // 로그인 버튼
                Consumer<AuthProvider>(
                  builder: (context, authProvider, _) {
                    return ElevatedButton(
                      onPressed: authProvider.isLoggedIn ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '로그인',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 회원가입 버튼
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SignupScreen(),
                      ),
                    );
                  },
                  child: const Text('회원가입'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
