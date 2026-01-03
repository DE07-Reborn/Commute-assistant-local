import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/weather_provider.dart';
import '../models/recommendation_detail.dart';

class RecommendationTabScreen extends StatefulWidget {
  final bool isCompact;
  final int? initialTabIndex;
  final String? highlightMessage;

  const RecommendationTabScreen({
    super.key,
    this.isCompact = false,
    this.initialTabIndex,
    this.highlightMessage,
  });

  @override
  State<RecommendationTabScreen> createState() => _RecommendationTabScreenState();
}

class _RecommendationTabScreenState extends State<RecommendationTabScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  final Map<int, AnimationController> _scrollControllers = {};

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex ?? 0;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _selectedIndex,
    );
    _tabController.addListener(() {
      setState(() {
        _selectedIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherProvider>(
      builder: (context, weatherProvider, _) {
        final recommendation = weatherProvider.recommendation;
        final weather = weatherProvider.weatherInfo;

        if (recommendation == null || weather == null) {
          if (widget.isCompact) {
            return const SizedBox.shrink();
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text('오늘의 추천'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: Text('날씨 정보를 불러올 수 없습니다'),
            ),
          );
        }

        if (widget.isCompact) {
          return _buildCompactView(recommendation, weather);
        }

        // 전체 화면 버전
        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: const Text('오늘의 추천 ✨'),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.highlightMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.notifications_active,
                            color: Colors.blue.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.highlightMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 날씨 정보 요약
                Card(
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
                    child: Row(
                      children: [
                        Icon(
                          _getWeatherIconData(weather.condition),
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${weather.temperature == 0 ? '0' : weather.temperature.toStringAsFixed(0)}°C',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                weather.description,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 탭 버튼들
                Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        0,
                        Icons.checkroom,
                        '옷차림',
                        Colors.blue,
                        _selectedIndex == 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTabButton(
                        1,
                        Icons.menu_book,
                        '도서',
                        Colors.orange,
                        _selectedIndex == 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTabButton(
                        2,
                        Icons.music_note,
                        '음악',
                        Colors.green,
                        _selectedIndex == 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 추천 내용
                _buildRecommendationContent(_selectedIndex, recommendation, weather),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getWeatherIconData(String condition) {
    switch (condition) {
      case 'rainy':
        return Icons.umbrella;
      case 'snowy':
        return Icons.ac_unit;
      case 'cloudy':
        return Icons.cloud;
      default:
        return Icons.wb_sunny;
    }
  }

  Widget _buildCompactView(recommendation, weather) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTabButton(
                0,
                Icons.checkroom,
                '옷차림',
                Colors.blue,
                _selectedIndex == 0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTabButton(
                1,
                Icons.menu_book,
                '도서',
                Colors.orange,
                _selectedIndex == 1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTabButton(
                2,
                Icons.music_note,
                '음악',
                Colors.green,
                _selectedIndex == 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: _buildRecommendationContent(_selectedIndex, recommendation, weather),
        ),
      ],
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label, Color color, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey.shade600,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationContent(
    int index,
    recommendation,
    weather,
  ) {
    switch (index) {
      case 0:
        return _buildClothingRecommendations(recommendation, weather);
      case 1:
        return _buildBookRecommendations(recommendation);
      case 2:
        return _buildMusicRecommendations(recommendation);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildClothingRecommendations(recommendation, weather) {
    final recommendations = _getClothingRecommendations(weather.condition);

    if (widget.isCompact) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: recommendations.length,
        itemBuilder: (context, index) {
          final rec = recommendations[index];
          return Container(
            width: 140,
            margin: EdgeInsets.only(right: index < recommendations.length - 1 ? 12 : 0),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rec.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    if (recommendations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('추천 정보가 없습니다'),
        ),
      );
    }

    return Column(
      children: recommendations.map((rec) {
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
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
                    Icons.checkroom,
                    color: Colors.blue.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec.category,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rec.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBookRecommendations(recommendation) {
    if (widget.isCompact) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: recommendation.books.length,
        itemBuilder: (context, index) {
          final bookLink = recommendation.bookLinks != null && 
                           recommendation.bookLinks!.isNotEmpty &&
                           index < recommendation.bookLinks!.length
                           ? recommendation.bookLinks![index]
                           : null;
          
          final hasValidLink = bookLink != null && 
                              bookLink.toString().trim().isNotEmpty &&
                              (bookLink.toString().startsWith('http://') || 
                               bookLink.toString().startsWith('https://'));
          
          return Container(
            width: 220,
            margin: EdgeInsets.only(right: index < recommendation.books.length - 1 ? 12 : 0),
            child: GestureDetector(
              onTap: hasValidLink
                  ? () => _launchUrl(bookLink!)
                  : null,
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book, color: Colors.orange, size: 22),
                      const SizedBox(height: 8),
                      ClipRect(
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          height: 50,
                          width: double.infinity,
                          child: _buildAutoScrollText(
                            recommendation.books[index],
                            index,
                            fontSize: 14,
                            isCompact: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (recommendation.books.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('추천 도서가 없습니다'),
        ),
      );
    }

    return Column(
      children: recommendation.books.asMap().entries.map<Widget>((entry) {
        final index = entry.key;
        final book = entry.value;
        final bookLink = recommendation.bookLinks != null && 
                         recommendation.bookLinks!.isNotEmpty &&
                         index < recommendation.bookLinks!.length
                         ? recommendation.bookLinks![index]
                         : null;
        
        final hasValidLink = bookLink != null && 
                            bookLink.toString().trim().isNotEmpty &&
                            (bookLink.toString().startsWith('http://') || 
                             bookLink.toString().startsWith('https://'));
        
        return GestureDetector(
          onTap: hasValidLink
              ? () => _launchUrl(bookLink!)
              : null,
          child: Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.menu_book,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildAutoScrollText(
                      book,
                      index,
                      fontSize: 16,
                      isCompact: false,
                    ),
                  ),
                  if (hasValidLink)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.open_in_new,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMusicRecommendations(recommendation) {
    if (widget.isCompact) {
      return ListView.builder(
        key: ValueKey('music_${recommendation.music.length}_${recommendation.music.join('|')}'), // 음악 리스트가 변경될 때 리빌드
        scrollDirection: Axis.horizontal,
        itemCount: recommendation.music.length,
        itemBuilder: (context, index) {
          return Container(
            width: 132,
            margin: EdgeInsets.only(right: index < recommendation.music.length - 1 ? 6 : 0),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_note, color: Colors.green, size: 22),
                      const SizedBox(height: 3),
                      ClipRect(
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          height: 50,
                          width: double.infinity,
                          child: _buildAutoScrollText(
                            recommendation.music[index],
                            1000 + index, // 도서와 겹치지 않도록 offset 추가
                            fontSize: 14,
                            isCompact: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    if (recommendation.music.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text('추천 음악이 없습니다'),
        ),
      );
    }

    return Column(
      key: ValueKey('music_full_${recommendation.music.length}_${recommendation.music.join('|')}'), // 음악 리스트가 변경될 때 리빌드
      children: recommendation.music.asMap().entries.map<Widget>((entry) {
        final index = entry.key as int;
        final music = entry.value;
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 6),
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
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: Colors.green.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAutoScrollText(
                    music,
                    2000 + index, // 도서와 겹치지 않도록 offset 추가
                    fontSize: 16,
                    isCompact: false,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<RecommendationDetail> _getClothingRecommendations(String condition) {
    switch (condition) {
      case 'rainy':
        return [
          RecommendationDetail(category: '아우터', name: '우비', description: ''),
          RecommendationDetail(category: '아우터', name: '레인코트', description: ''),
        ];
      case 'snowy':
        return [
          RecommendationDetail(category: '아우터', name: '패딩', description: ''),
          RecommendationDetail(category: '아우터', name: '코트', description: ''),
        ];
      case 'cloudy':
        return [
          RecommendationDetail(category: '아우터', name: '가벼운 재킷', description: ''),
          RecommendationDetail(category: '아우터', name: '가디건', description: ''),
        ];
      default: // sunny
        return [
          RecommendationDetail(category: '아우터', name: '가벼운 재킷', description: ''),
          RecommendationDetail(category: '상의', name: '반팔', description: ''),
        ];
    }
  }

  /// 자동 스크롤 텍스트 위젯
  Widget _buildAutoScrollText(String text, int index, {double fontSize = 14, bool isCompact = false}) {
    // 애니메이션 컨트롤러가 없으면 생성
    if (!_scrollControllers.containsKey(index)) {
      _scrollControllers[index] = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 20),  // 천천히 움직이도록 시간 증가
      )..repeat();
    }
    
    final controller = _scrollControllers[index]!;
    
    // 줄바꿈이 있는 경우
    final hasNewline = text.contains('\n');
    final lines = text.split('\n');
    
    return LayoutBuilder(
      builder: (context, constraints) {
        if (hasNewline && lines.length >= 2) {
          // 2줄 이상인 경우 (도서: 제목\n저자 또는 음악: 트랙\n앨범\n아티스트)
          if (lines.length == 2) {
            // 도서 형식: 제목\n저자
            final title = lines[0];
            final author = lines[1];
            return ClipRect(
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
              height: isCompact ? 40 : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: isCompact ? 18 : null,
                    child: _buildScrollableText(
                      title,
                      controller,
                      constraints.maxWidth,
                      fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1.1),
                  SizedBox(
                    height: isCompact ? 18 : null,
                    child: _buildScrollableText(
                      author,
                      controller,
                      constraints.maxWidth,
                      fontSize - 2,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              ),
            );
          } else if (lines.length >= 3) {
            // 음악 형식: 트랙\n앨범\n아티스트
            final trackName = lines[0];
            final albumName = lines[1];
            final artists = lines[2];
            return ClipRect(
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
              height: isCompact ? 50 : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: isCompact ? 15 : null,
                    child: _buildScrollableText(
                      trackName,
                      controller,
                      constraints.maxWidth,
                      fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: isCompact ? 15 : null,
                    child: _buildScrollableText(
                      albumName,
                      controller,
                      constraints.maxWidth,
                      fontSize - 1,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 1.1),
                  SizedBox(
                    height: isCompact ? 15 : null,
                    child: _buildScrollableText(
                      artists,
                      controller,
                      constraints.maxWidth,
                      fontSize - 2,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              ),
            );
          }
        }
        
        // 줄바꿈이 없는 경우
        {
          // 줄바꿈이 없는 경우
          return ClipRect(
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              height: isCompact ? 40 : null,
              child: _buildScrollableText(
                text,
                controller,
                constraints.maxWidth,
                fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
      },
    );
  }
  
  /// 스크롤 가능한 텍스트 위젯
  Widget _buildScrollableText(
    String text,
    AnimationController controller,
    double maxWidth,
    double fontSize, {
    FontWeight fontWeight = FontWeight.bold,
    Color? color,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              height: 1.1,
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        // 텍스트가 컨테이너보다 길면 자동 스크롤
        if (textPainter.width > constraints.maxWidth) {
          // 제목 전체가 보이도록 스크롤 거리 계산
          // 제목이 컨테이너 너비만큼 보이고, 나머지 부분이 완전히 보이도록 스크롤
          final gap = 80.0;  // 간격
          final scrollDistance = textPainter.width - constraints.maxWidth;  // 실제 스크롤해야 할 거리
          final totalScrollDistance = scrollDistance + gap;  // 스크롤 거리 + 간격
          
          return ClipRect(
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: constraints.maxWidth,
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  // 한 방향으로만 천천히 움직이고 간격 후 다시 시작
                  final value = controller.value;
                  // 0에서 totalScrollDistance까지 이동한 후 다시 0으로 (무한 반복)
                  final offset = (value * totalScrollDistance) % totalScrollDistance;
                  
                  return Stack(
                    clipBehavior: Clip.none,  // 텍스트가 잘리지 않도록
                    children: [
                      // 첫 번째 텍스트 (왼쪽에서 오른쪽으로 스크롤)
                      Transform.translate(
                        offset: Offset(-offset, 0),
                        child: Text(
                          text,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: fontWeight,
                            color: color,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,  // visible로 변경하여 전체가 보이도록
                        ),
                      ),
                      // 간격 후 반복되는 두 번째 텍스트
                      Transform.translate(
                        offset: Offset(textPainter.width + gap - offset, 0),
                        child: Text(
                          text,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: fontWeight,
                            color: color,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,  // visible로 변경하여 전체가 보이도록
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        } else {
          // 텍스트가 짧으면 그냥 표시
          return Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
              height: 1.1,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        }
      },
    );
  }

  /// URL 실행 함수
  Future<void> _launchUrl(String url) async {
    try {
      print('URL 실행 시도: $url');
      
      // URL 형식 검증 및 HTML 엔티티 변환
      String urlString = url.trim();
      
      // HTML 엔티티 변환 (&amp; -> &)
      urlString = urlString.replaceAll('&amp;', '&');
      urlString = urlString.replaceAll('&lt;', '<');
      urlString = urlString.replaceAll('&gt;', '>');
      urlString = urlString.replaceAll('&quot;', '"');
      urlString = urlString.replaceAll('&#39;', "'");
      
      if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
        print('URL 형식이 올바르지 않습니다: $urlString');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('올바른 링크 형식이 아닙니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final uri = Uri.parse(urlString);
      print('파싱된 URI: $uri');
      
      // canLaunchUrl을 사용하지 않고 직접 실행 시도
      // Android 11+에서 canLaunchUrl이 false를 반환할 수 있지만 실제로는 실행 가능할 수 있음
      try {
        print('URL 직접 실행 시도');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('URL 실행 성공');
      } catch (launchError) {
        print('URL 직접 실행 실패: $launchError');
        // canLaunchUrl로 재시도
        if (await canLaunchUrl(uri)) {
          print('canLaunchUrl 확인 후 재시도');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          print('URL 실행 불가능');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('링크를 열 수 없습니다. 브라우저가 설치되어 있는지 확인해주세요.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('URL 실행 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('링크를 열 수 없습니다: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
