import 'package:flutter/foundation.dart';
import '../models/saved_location.dart';

class SavedLocationProvider with ChangeNotifier {
  final List<SavedLocation> _locations = [
    SavedLocation(
      id: '1',
      name: '집',
      address: '서울시 강남구',
      type: 'home',
    ),
  ];

  List<SavedLocation> get locations => _locations;

  void addLocation(SavedLocation location) {
    _locations.add(location);
    notifyListeners();
  }

  void removeLocation(String id) {
    _locations.removeWhere((loc) => loc.id == id);
    notifyListeners();
  }
}

