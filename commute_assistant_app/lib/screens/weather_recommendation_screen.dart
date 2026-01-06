import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/weather_provider.dart';

class WeatherRecommendationScreen extends StatelessWidget {
  const WeatherRecommendationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('날씨 기반 추천'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Consumer<WeatherProvider>(
        builder: (context, weatherProvider, _) {
          if (weatherProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (weatherProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text(
                    weatherProvider.error!,
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => weatherProvider.loadWeather(),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }

          final weather = weatherProvider.weatherInfo;
          final recommendation = weatherProvider.recommendation;

          if (weather == null || recommendation == null) {
            return const Center(child: Text('날씨 정보를 불러올 수 없습니다'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 날씨 정보 카드
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _getWeatherIcon(weather.condition, 64),
                        const SizedBox(height: 16),
                        Text(
                          '${weather.temperature == 0 ? '0.0' : weather.temperature.toStringAsFixed(1)}°C',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          weather.condition,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildWeatherDetail(
                              context,
                              Icons.water_drop,
                              '${weather.humidity}%',
                              '습도',
                            ),
                            _buildWeatherDetail(
                              context,
                              Icons.air,
                              '${weather.windSpeed.toStringAsFixed(1)}m/s',
                              '풍속',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 옷차림 추천
                _buildRecommendationCard(
                  context,
                  '옷차림 추천',
                  Icons.checkroom,
                  recommendation.clothing,
                  Colors.purple,
                ),
                const SizedBox(height: 16),
                // 도서 추천
                _buildRecommendationCard(
                  context,
                  '도서 추천',
                  Icons.menu_book,
                  recommendation.books.join('\n• '),
                  Colors.orange,
                  prefix: '• ',
                ),
                const SizedBox(height: 16),
                // 음악 추천
                _buildRecommendationCard(
                  context,
                  '음악 추천',
                  Icons.music_note,
                  recommendation.music.join('\n• '),
                  Colors.green,
                  prefix: '• ',
                ),
                const SizedBox(height: 16),
                // 새로고침 버튼
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => weatherProvider.loadWeather(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('날씨 정보 새로고침'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _getWeatherIcon(String condition, double size) {
    IconData icon;
    Color color;

    switch (condition) {
      case 'rainy':
        icon = Icons.umbrella;
        color = Colors.blue;
        break;
      case 'snowy':
        icon = Icons.ac_unit;
        color = Colors.lightBlue;
        break;
      case 'cloudy':
        icon = Icons.cloud;
        color = Colors.grey;
        break;
      default:
        icon = Icons.wb_sunny;
        color = Colors.orange;
    }

    return Icon(icon, color: color, size: size);
  }

  Widget _buildWeatherDetail(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue.shade700),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(
    BuildContext context,
    String title,
    IconData icon,
    String content,
    Color color, {
    String? prefix,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              prefix != null ? '$prefix$content' : content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

