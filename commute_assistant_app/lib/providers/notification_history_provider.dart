import 'package:flutter/foundation.dart';
import '../models/notification_history_item.dart';

class NotificationHistoryProvider with ChangeNotifier {
  static const int _maxItems = 50;
  final List<NotificationHistoryItem> _items = [];

  List<NotificationHistoryItem> get items => List.unmodifiable(_items);

  void addItem(NotificationHistoryItem item) {
    _items.insert(0, item);
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
