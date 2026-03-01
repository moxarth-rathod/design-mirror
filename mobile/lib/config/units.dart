import 'package:flutter/foundation.dart';

enum DimensionUnit {
  meters,
  feet,
  inches,
}

class DimensionFormatter {
  DimensionFormatter._();

  static final ValueNotifier<DimensionUnit> currentUnit =
      ValueNotifier(DimensionUnit.meters);

  static const double _metersToFeet = 3.28084;
  static const double _metersToInches = 39.3701;

  static String format(double meters) {
    switch (currentUnit.value) {
      case DimensionUnit.meters:
        return '${meters.toStringAsFixed(2)}m';
      case DimensionUnit.feet:
        final ft = meters * _metersToFeet;
        return '${ft.toStringAsFixed(1)} ft';
      case DimensionUnit.inches:
        final inches = meters * _metersToInches;
        return '${inches.round()}"';
    }
  }

  static String formatCompact(double wM, double dM, double hM) {
    final w = format(wM);
    final d = format(dM);
    final h = format(hM);
    return '$w × $d × $h';
  }

  static String unitLabel() {
    switch (currentUnit.value) {
      case DimensionUnit.meters:
        return 'm';
      case DimensionUnit.feet:
        return 'ft';
      case DimensionUnit.inches:
        return '"';
    }
  }
}
