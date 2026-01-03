import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/places_service.dart';

class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final Color dotColor;
  final Function(String address, double lat, double lng)? onAddressSelected;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.dotColor,
    this.onAddressSelected,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  PlacesService? _placesService;
  List<PlacePrediction> _predictions = [];
  bool _showSuggestions = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  bool _isSelecting = false; // 주소 선택 중 플래그

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _placesService = Provider.of<PlacesService>(context);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    // 주소 선택 중이면 검색하지 않음
    if (_isSelecting) return;
    
    final text = widget.controller.text;
    if (text.isNotEmpty) {
      _searchPlaces(text);
    } else {
      setState(() {
        _predictions = [];
        _showSuggestions = false;
      });
      _removeOverlay();
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _removeOverlay();
        }
      });
    }
  }

  Future<void> _searchPlaces(String input) async {
    if (input.length < 2 || _placesService == null) {
      setState(() {
        _predictions = [];
        _showSuggestions = false;
      });
      _removeOverlay();
      return;
    }

    final predictions = await _placesService!.getPlacePredictions(input);
    if (mounted) {
      setState(() {
        _predictions = predictions;
        _showSuggestions = predictions.isNotEmpty;
      });
      _updateOverlay();
    }
  }

  void _updateOverlay() {
    _removeOverlay();
    if (_showSuggestions && _predictions.isNotEmpty) {
      _overlayEntry = _createOverlay();
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlay() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? Size.zero;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _predictions.length,
                itemBuilder: (context, index) {
                  final prediction = _predictions[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      prediction.mainText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      prediction.secondaryText,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    onTap: () async {
                      // 주소 선택 시작
                      _isSelecting = true;
                      _removeOverlay();
                      
                      // 텍스트 설정 (이때 _onTextChanged가 호출되지만 _isSelecting이 true라서 무시됨)
                      widget.controller.text = prediction.description;
                      _focusNode.unfocus();

                      // Place 상세 정보 가져오기
                      if (_placesService == null) {
                        _isSelecting = false;
                        return;
                      }
                      
                      try {
                        final details = await _placesService!.getPlaceDetails(
                          prediction.placeId,
                        );
                        if (details != null && widget.onAddressSelected != null) {
                          widget.onAddressSelected!(
                            details['address'] as String,
                            details['lat'] as double,
                            details['lng'] as double,
                          );
                        }
                      } finally {
                        // 주소 선택 완료
                        _isSelecting = false;
                        // 예측 목록 초기화
                        setState(() {
                          _predictions = [];
                          _showSuggestions = false;
                        });
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.dotColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.circle,
              color: widget.dotColor,
              size: 12,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}
