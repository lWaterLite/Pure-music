import 'dart:math' as math;

import 'package:pure_music/core/equalizer_action_state.dart';

final class ParsedWaveletEq {
  const ParsedWaveletEq({required this.gains, this.preampDb});

  final List<double> gains;
  final double? preampDb;
}

final class WaveletEqPresetSource {
  const WaveletEqPresetSource({required this.name, required this.content});

  final String name;
  final String content;
}

final class ParsedWaveletEqPreset {
  const ParsedWaveletEqPreset({
    required this.name,
    required this.gains,
    required this.preampDb,
  });

  final String name;
  final List<double> gains;
  final double preampDb;
}

final class WaveletEqBatchParseResult {
  const WaveletEqBatchParseResult({
    required this.presets,
    required this.failed,
  });

  final List<ParsedWaveletEqPreset> presets;
  final int failed;
}

const _maxWaveletFrequencyHz = 100000.0;
const _maxWaveletPointCount = 20000;
final _waveletPreampPattern = RegExp(
  r'^\s*preamp\s*:\s*([+-]?(?:\d+(?:[.,]\d+)?|\.\d+)(?:[eE][+-]?\d+)?)',
  multiLine: true,
  caseSensitive: false,
);
final _waveletHeaderPattern = RegExp(
  r'^\s*graphiceq\s*:',
  multiLine: true,
  caseSensitive: false,
);
final _waveletPairPattern = RegExp(
  r'^\s*(\d+(?:[.,]\d+)?)[ \t]*(?:hz)?[ \t]*(?::[ \t]*|[ \t]+)([+-]?(?:\d+(?:[.,]\d+)?|\.\d+)(?:[eE][+-]?\d+)?)\s*(?:db)?\s*$',
  caseSensitive: false,
);

ParsedWaveletEq parseWaveletEqContent(String content) {
  final normalized = content.replaceAll('\uFEFF', '');
  final preampDb = _parseWaveletNumber(
    _waveletPreampPattern.firstMatch(normalized)?.group(1),
  );
  final header = _waveletHeaderPattern.firstMatch(normalized);
  final region = header == null ? normalized : normalized.substring(header.end);
  final pointsByFrequency = <double, double>{};
  for (final token in region.split(RegExp(r'[;\r\n]+'))) {
    final match = _waveletPairPattern.firstMatch(token);
    if (match == null) continue;
    final frequency = _parseWaveletNumber(match.group(1));
    final gain = _parseWaveletNumber(match.group(2));
    if (frequency == null ||
        gain == null ||
        frequency <= 0.0 ||
        frequency > _maxWaveletFrequencyHz) {
      continue;
    }
    if (pointsByFrequency.length >= _maxWaveletPointCount &&
        !pointsByFrequency.containsKey(frequency)) {
      continue;
    }
    pointsByFrequency[frequency] = gain
        .clamp(eqGainMinDb, eqGainMaxDb)
        .toDouble();
  }

  final points = pointsByFrequency.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if (points.isEmpty) {
    throw const FormatException('No valid GraphicEQ pairs found');
  }

  final gains = <double>[];
  for (final frequency in eqBandFrequenciesHz) {
    gains.add(_interpolateLogFrequency(frequency, points));
  }
  return ParsedWaveletEq(gains: List.unmodifiable(gains), preampDb: preampDb);
}

WaveletEqBatchParseResult parseWaveletEqBatch(
  Iterable<WaveletEqPresetSource> sources, {
  required double fallbackPreampDb,
}) {
  final presets = <ParsedWaveletEqPreset>[];
  var failed = 0;
  final fallback = normalizedEqPreampDb(fallbackPreampDb);
  for (final source in sources) {
    try {
      final parsed = parseWaveletEqContent(source.content);
      presets.add(
        ParsedWaveletEqPreset(
          name: source.name,
          gains: parsed.gains,
          preampDb: normalizedEqPreampDb(parsed.preampDb ?? fallback),
        ),
      );
    } catch (_) {
      failed++;
    }
  }
  return WaveletEqBatchParseResult(
    presets: List.unmodifiable(presets),
    failed: failed,
  );
}

double? _parseWaveletNumber(String? value) {
  if (value == null) return null;
  final number = double.tryParse(value.replaceAll(',', '.'));
  return number != null && number.isFinite ? number : null;
}

double _interpolateLogFrequency(
  double targetFrequency,
  List<MapEntry<double, double>> points,
) {
  if (targetFrequency <= points.first.key) return points.first.value;
  if (targetFrequency >= points.last.key) return points.last.value;
  for (var i = 0; i < points.length - 1; i++) {
    final first = points[i];
    final second = points[i + 1];
    if (targetFrequency < first.key || targetFrequency > second.key) {
      continue;
    }
    final denominator = math.log(second.key) - math.log(first.key);
    if (denominator.abs() < 1e-12) return second.value;
    final position =
        (math.log(targetFrequency) - math.log(first.key)) / denominator;
    return (first.value + (second.value - first.value) * position)
        .clamp(eqGainMinDb, eqGainMaxDb)
        .toDouble();
  }
  return 0.0;
}
