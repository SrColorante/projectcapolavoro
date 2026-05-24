import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RichColorBoard extends StatefulWidget {
  const RichColorBoard({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorSelected;

  @override
  State<RichColorBoard> createState() => _RichColorBoardState();
}

class _RichColorBoardState extends State<RichColorBoard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late double _hue;
  late double _saturation;
  late double _lightness;
  late TextEditingController _hexController;

  // Predefined rich curated palettes
  static const Map<String, List<Color>> _groups = {
    'Pastelli Eleganti': [
      Color(0xFFDCD0FF), // Lavender
      Color(0xFFB2DFDB), // Soft Mint
      Color(0xFFBBDEFB), // Ice Blue
      Color(0xFFFFE0B2), // Peach Cream
      Color(0xFFF8BBD0), // Blush Pink
      Color(0xFFE1BEE7), // Pale Lilac
      Color(0xFFC8E6C9), // Pearl Sage
      Color(0xFFFFF9C4), // Vanilla
    ],
    'Luminosi & Vivaci': [
      Color(0xFFFFD600), // Sunflower Yellow
      Color(0xFFFF6D00), // Sunset Orange
      Color(0xFFD500F9), // Neon Violet
      Color(0xFF00E5FF), // Cyan Teal
      Color(0xFF00E676), // Emerald Green
      Color(0xFFFF4081), // Hot Pink
      Color(0xFF2979FF), // Electric Blue
      Color(0xFFE040FB), // Electric Magenta
    ],
    'Toni Nordici & Muti': [
      Color(0xFF37474F), // Nordic Slate
      Color(0xFF1A237E), // Dark Indigo
      Color(0xFF558B2F), // Sage Green
      Color(0xFF8D6E63), // Muted Sand
      Color(0xFF00695C), // Muted Teal
      Color(0xFF90A4AE), // Arctic Blue
      Color(0xFF827717), // Olive Muted
      Color(0xFF4E342E), // Muted Cocoa
    ],
    'Profondi & Neutrali': [
      Color(0xFF1C1C1E), // Carbon Obsidian
      Color(0xFF212121), // Dark Charcoal
      Color(0xFF757575), // Slate Gray
      Color(0xFFCFD8DC), // Platinum Silver
      Color(0xFFECEFF1), // Alabaster White
      Color(0xFFFFFFFF), // Pure White
      Color(0xFF050505), // Deep Black
      Color(0xFF000000), // Absolute Black
    ],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _updateHSLValues(widget.selectedColor);
    _hexController = TextEditingController(text: _colorToHex(widget.selectedColor));
  }

  @override
  void didUpdateWidget(covariant RichColorBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedColor.value != widget.selectedColor.value) {
      _updateHSLValues(widget.selectedColor);
      _hexController.text = _colorToHex(widget.selectedColor);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _updateHSLValues(Color color) {
    final hsl = HSLColor.fromColor(color);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  String _colorToHex(Color color) {
    return color.value.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  void _onPresetSelected(Color color) {
    HapticFeedback.selectionClick();
    _updateHSLValues(color);
    _hexController.text = _colorToHex(color);
    widget.onColorSelected(color);
  }

  void _onHSLChanged() {
    final hslColor = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness);
    final color = hslColor.toColor();
    _hexController.text = _colorToHex(color);
    widget.onColorSelected(color);
  }

  void _onHexChanged(String value) {
    String cleanHex = value.replaceAll('#', '').trim();
    if (cleanHex.length == 6) {
      cleanHex = 'FF$cleanHex'; // Add full opacity by default
    }
    if (cleanHex.length == 8) {
      final val = int.tryParse(cleanHex, radix: 16);
      if (val != null) {
        final color = Color(val);
        setState(() {
          _updateHSLValues(color);
        });
        widget.onColorSelected(color);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isDark ? 0.05 : 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(isDark ? 0.12 : 0.4),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Elegant Glassy TabBar
          TabBar(
            controller: _tabController,
            indicatorColor: widget.selectedColor,
            labelColor: isDark ? Colors.white : Colors.black87,
            unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.palette_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Palette Curate', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.tune_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Personalizza', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: SizedBox(
              height: 290,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // --- Tab 1: Predefined groups ---
                  _buildCuratedTab(isDark),
                  // --- Tab 2: Custom HSL and HEX ---
                  _buildCustomTab(isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratedTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final title = _groups.keys.elementAt(index);
        final list = _groups[title]!;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: list.map((color) {
                  final isSelected = color.value == widget.selectedColor.value;
                  return InkWell(
                    onTap: () => _onPresetSelected(color),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? (isDark ? Colors.white : Colors.black)
                              : Colors.transparent,
                          width: isSelected ? 2.5 : 0,
                        ),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: color.withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            )
                          else
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 3,
                              offset: const Offset(0, 1.5),
                            ),
                        ],
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomTab(bool isDark) {
    final hslColor = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness);
    final activeColor = hslColor.toColor();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dynamic Custom HEX Input & Color Preview
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _hexController,
                    onChanged: _onHexChanged,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(9),
                    ],
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Colore HEX',
                      prefixText: '#',
                      prefixStyle: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontWeight: FontWeight.bold,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      filled: true,
                      fillColor: Colors.black.withOpacity(isDark ? 0.08 : 0.03),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(isDark ? 0.08 : 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: widget.selectedColor, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Beautiful glowing color preview card
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 72,
                height: 48,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(isDark ? 0.2 : 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    activeColor.computeLuminance() > 0.5 ? 'CHIARO' : 'SCURO',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: activeColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- Slider H: Hue (Tonalità) ---
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  'HUE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 10,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    // Elegant rainbow gradient track
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                  ),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(
                        colors: [
                          Colors.red,
                          Colors.orange,
                          Colors.yellow,
                          Colors.green,
                          Colors.cyan,
                          Colors.blue,
                          Colors.purple,
                          Colors.red,
                        ],
                      ),
                    ),
                    child: Slider(
                      value: _hue,
                      min: 0.0,
                      max: 360.0,
                      onChanged: (val) {
                        setState(() {
                          _hue = val;
                          _onHSLChanged();
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 32,
                child: Text(
                  '${_hue.round()}°',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // --- Slider S: Saturation (Saturazione) ---
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  'SAT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 10,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                  ),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(
                        colors: [
                          HSLColor.fromAHSL(1.0, _hue, 0.0, _lightness).toColor(),
                          HSLColor.fromAHSL(1.0, _hue, 1.0, _lightness).toColor(),
                        ],
                      ),
                    ),
                    child: Slider(
                      value: _saturation,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) {
                        setState(() {
                          _saturation = val;
                          _onHSLChanged();
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 32,
                child: Text(
                  '${(_saturation * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // --- Slider L: Lightness (Luminosità) ---
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  'LGT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 10,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                  ),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black,
                          HSLColor.fromAHSL(1.0, _hue, _saturation, 0.5).toColor(),
                          Colors.white,
                        ],
                      ),
                    ),
                    child: Slider(
                      value: _lightness,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) {
                        setState(() {
                          _lightness = val;
                          _onHSLChanged();
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 32,
                child: Text(
                  '${(_lightness * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
