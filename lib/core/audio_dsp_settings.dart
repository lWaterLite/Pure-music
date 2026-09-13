import 'dart:math' as math;

const double dspHighPassMinHz = 20.0;
const double dspHighPassMaxHz = 2000.0;
const double dspLowPassMinHz = 500.0;
const double dspLowPassMaxHz = 20000.0;
const double dspMinimumPassBandGapHz = 20.0;

final class AudioDspSettings {
  const AudioDspSettings({
    this.enabled = false,
    this.highPassHz = 20.0,
    this.lowPassHz = 20000.0,
    this.drive = 0.0,
    this.reverb = 0.0,
    this.punch = 0.0,
    this.limiterEnabled = false,
    this.limiterCeilingDb = -1.0,
  });

  final bool enabled;
  final double highPassHz;
  final double lowPassHz;
  final double drive;
  final double reverb;
  final double punch;
  final bool limiterEnabled;
  final double limiterCeilingDb;

  bool get hasToneShaping =>
      enabled &&
      (highPassHz > dspHighPassMinHz ||
          lowPassHz < dspLowPassMaxHz ||
          drive > 0.0001 ||
          reverb > 0.0001 ||
          punch > 0.0001);

  bool get isNeutral => !hasToneShaping && !limiterEnabled;

  AudioDspSettings normalized() {
    var highPassHz = _bounded(
      this.highPassHz,
      dspHighPassMinHz,
      dspHighPassMaxHz,
      dspHighPassMinHz,
    );
    var lowPassHz = _bounded(
      this.lowPassHz,
      dspLowPassMinHz,
      dspLowPassMaxHz,
      dspLowPassMaxHz,
    );
    if (lowPassHz <= highPassHz) {
      highPassHz = math.max(
        dspHighPassMinHz,
        math.min(highPassHz, lowPassHz - dspMinimumPassBandGapHz),
      );
      if (lowPassHz <= highPassHz) {
        lowPassHz = math.min(
          dspLowPassMaxHz,
          highPassHz + dspMinimumPassBandGapHz,
        );
      }
    }
    return AudioDspSettings(
      enabled: enabled,
      highPassHz: highPassHz,
      lowPassHz: lowPassHz,
      drive: _bounded(drive, 0.0, 1.0, 0.0),
      reverb: _bounded(reverb, 0.0, 1.0, 0.0),
      punch: _bounded(punch, 0.0, 1.0, 0.0),
      limiterEnabled: limiterEnabled,
      limiterCeilingDb: _bounded(limiterCeilingDb, -12.0, -0.1, -1.0),
    );
  }

  AudioDspSettings copyWith({
    bool? enabled,
    double? highPassHz,
    double? lowPassHz,
    double? drive,
    double? reverb,
    double? punch,
    bool? limiterEnabled,
    double? limiterCeilingDb,
  }) {
    var nextHighPassHz = _bounded(
      highPassHz,
      dspHighPassMinHz,
      dspHighPassMaxHz,
      this.highPassHz,
    );
    var nextLowPassHz = _bounded(
      lowPassHz,
      dspLowPassMinHz,
      dspLowPassMaxHz,
      this.lowPassHz,
    );
    if (nextLowPassHz <= nextHighPassHz) {
      if (highPassHz != null && lowPassHz == null) {
        nextLowPassHz = math.min(
          dspLowPassMaxHz,
          nextHighPassHz + dspMinimumPassBandGapHz,
        );
      } else if (lowPassHz != null && highPassHz == null) {
        nextHighPassHz = math.max(
          dspHighPassMinHz,
          nextLowPassHz - dspMinimumPassBandGapHz,
        );
      } else {
        nextHighPassHz = math.max(
          dspHighPassMinHz,
          nextLowPassHz - dspMinimumPassBandGapHz,
        );
      }
    }
    return AudioDspSettings(
      enabled: enabled ?? this.enabled,
      highPassHz: nextHighPassHz,
      lowPassHz: nextLowPassHz,
      drive: _bounded(drive, 0.0, 1.0, this.drive),
      reverb: _bounded(reverb, 0.0, 1.0, this.reverb),
      punch: _bounded(punch, 0.0, 1.0, this.punch),
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      limiterCeilingDb: _bounded(
        limiterCeilingDb,
        -12.0,
        -0.1,
        this.limiterCeilingDb,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'highPassHz': highPassHz,
    'lowPassHz': lowPassHz,
    'drive': drive,
    'reverb': reverb,
    'punch': punch,
    'limiterEnabled': limiterEnabled,
    'limiterCeilingDb': limiterCeilingDb,
  };

  factory AudioDspSettings.fromMap(Object? value) {
    final map = value is Map ? value : const <String, Object?>{};
    return AudioDspSettings(
      enabled: map['enabled'] is bool ? map['enabled'] as bool : false,
      highPassHz: _bounded(
        map['highPassHz'],
        dspHighPassMinHz,
        dspHighPassMaxHz,
        dspHighPassMinHz,
      ),
      lowPassHz: _bounded(
        map['lowPassHz'],
        dspLowPassMinHz,
        dspLowPassMaxHz,
        dspLowPassMaxHz,
      ),
      drive: _bounded(map['drive'], 0.0, 1.0, 0.0),
      reverb: _bounded(map['reverb'], 0.0, 1.0, 0.0),
      punch: _bounded(map['punch'], 0.0, 1.0, 0.0),
      limiterEnabled: map['limiterEnabled'] is bool
          ? map['limiterEnabled'] as bool
          : false,
      limiterCeilingDb: _bounded(map['limiterCeilingDb'], -12.0, -0.1, -1.0),
    ).normalized();
  }
}

final class BuiltInAudioPreset {
  const BuiltInAudioPreset({
    required this.id,
    required this.name,
    required this.gains,
    this.preampDb = 0.0,
  });

  final String id;
  final String name;
  final List<double> gains;
  final double preampDb;
}

const builtInAudioPresets = <BuiltInAudioPreset>[
  BuiltInAudioPreset(
    id: 'flat',
    name: '平直',
    gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  ),
  BuiltInAudioPreset(
    id: 'rock',
    name: '摇滚',
    gains: [3.0, 2.0, 1.0, -0.5, -1.0, -0.5, 0.5, 1.5, 2.5, 2.0],
    preampDb: -0.5,
  ),
  BuiltInAudioPreset(
    id: 'pop',
    name: '流行',
    gains: [1.5, 1.5, 0.5, -0.5, -1.0, -1.0, 0.0, 1.0, 1.5, 1.0],
    preampDb: -0.5,
  ),
  BuiltInAudioPreset(
    id: 'jazz',
    name: '爵士',
    gains: [1.0, 0.5, 0.0, -0.5, -0.5, 0.5, 1.0, 1.5, 1.0, 0.5],
    preampDb: -0.25,
  ),
  BuiltInAudioPreset(
    id: 'classical',
    name: '古典',
    gains: [1.5, 1.0, 0.5, 0.0, -0.5, -0.5, 0.0, 0.5, 1.5, 2.0],
    preampDb: -0.5,
  ),
  BuiltInAudioPreset(
    id: 'dance',
    name: '舞曲',
    gains: [3.5, 3.0, 1.0, -1.5, -2.0, -1.0, 1.0, 2.0, 3.0, 2.5],
    preampDb: -1.0,
  ),
  BuiltInAudioPreset(
    id: 'electronic',
    name: '电子',
    gains: [2.5, 2.5, 1.5, -1.0, -1.5, -1.0, 0.5, 1.5, 2.0, 1.5],
    preampDb: -0.75,
  ),
  BuiltInAudioPreset(
    id: 'hiphop',
    name: '嘻哈',
    gains: [3.5, 3.0, 2.0, 0.0, -1.0, -1.0, 0.0, 0.5, 1.0, 0.5],
    preampDb: -0.75,
  ),
  BuiltInAudioPreset(
    id: 'vocal',
    name: '人声',
    gains: [-2.5, -1.5, -0.5, 0.0, 1.0, 2.0, 2.5, 1.5, 0.5, -0.5],
    preampDb: -0.5,
  ),
  BuiltInAudioPreset(
    id: 'acoustic',
    name: '原声',
    gains: [1.5, 1.0, 0.0, -0.5, -1.0, 0.0, 1.0, 1.5, 1.0, 0.5],
    preampDb: -0.25,
  ),
  BuiltInAudioPreset(
    id: 'bass',
    name: '低音增强',
    gains: [4.0, 3.5, 2.0, 0.5, -1.0, -1.5, -0.5, 0.0, 0.5, 1.0],
    preampDb: -1.0,
  ),
  BuiltInAudioPreset(
    id: 'treble',
    name: '高音增强',
    gains: [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.5, 3.5, 3.5],
    preampDb: -1.0,
  ),
];

double _bounded(Object? value, double min, double max, double fallback) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite) return fallback;
  return number.clamp(min, max).toDouble();
}
