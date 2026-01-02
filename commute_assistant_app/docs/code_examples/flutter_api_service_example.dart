/// Flutter 앱에서 FastAPI를 사용하는 예시
/// 기존 Redis 직접 연결 대신 FastAPI를 통해 데이터 조회
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl;
  
  ApiService({this.baseUrl = 'http://localhost:8000'});
  
  /// 날씨 데이터 조회
  Future<WeatherInfo?> getWeatherData(String stationId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/weather/$stationId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return WeatherInfo.fromJson(data);
      } else {
        print('Failed to load weather: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching weather data: $e');
      return null;
    }
  }
  
  /// 도서 추천 조회
  Future<List<BookInfo>> getBookRecommendations(String weatherCondition) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/recommendations/books?weather_condition=$weatherCondition'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final books = (data['books'] as List)
            .map((book) => BookInfo.fromJson(book))
            .toList();
        return books;
      } else {
        print('Failed to load book recommendations: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching book recommendations: $e');
      return [];
    }
  }
  
  /// 음악 추천 조회
  Future<List<MusicTrack>> getMusicRecommendations(String weatherCondition) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/recommendations/music?weather_condition=$weatherCondition'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final music = (data['music'] as List)
            .map((track) => MusicTrack.fromJson(track))
            .toList();
        return music;
      } else {
        print('Failed to load music recommendations: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching music recommendations: $e');
      return [];
    }
  }
}

/// 모델 클래스
class WeatherInfo {
  final double temperature;
  final String condition;
  final int humidity;
  final double windSpeed;
  final String description;
  final String? location;
  
  WeatherInfo({
    required this.temperature,
    required this.condition,
    required this.humidity,
    required this.windSpeed,
    required this.description,
    this.location,
  });
  
  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      temperature: (json['temperature'] as num).toDouble(),
      condition: json['condition'] as String,
      humidity: json['humidity'] as int,
      windSpeed: (json['windSpeed'] as num).toDouble(),
      description: json['description'] as String,
      location: json['location'] as String?,
    );
  }
}

class BookInfo {
  final String title;
  final String author;
  final String? link;
  
  BookInfo({
    required this.title,
    required this.author,
    this.link,
  });
  
  factory BookInfo.fromJson(Map<String, dynamic> json) {
    return BookInfo(
      title: json['title'] as String,
      author: json['author'] as String,
      link: json['link'] as String?,
    );
  }
}

class MusicTrack {
  final String trackName;
  final String artists;
  final String albumName;
  
  MusicTrack({
    required this.trackName,
    required this.artists,
    required this.albumName,
  });
  
  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      trackName: json['trackName'] as String,
      artists: json['artists'] as String,
      albumName: json['albumName'] as String,
    );
  }
}

