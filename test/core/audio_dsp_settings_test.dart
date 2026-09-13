import 'package:flutter_test/flutter_test.dart';
import 'package:pure_music/core/audio_dsp_settings.dart';
import 'package:pure_music/core/equalizer_action_state.dart';
import 'package:pure_music/core/preference.dart';
import 'package:pure_music/core/enums.dart';

void main() {
  test('normalizes persisted DSP values into supported ranges', () {
    final settings = AudioDspSettings.fromMap({
      'enabled': true,
      'highPassHz': 5000,
      'lowPassHz': 100,
      'drive': 2,
      'reverb': -1,
      'punch': 0.6,
    });

    expect(settings.enabled, isTrue);
    expect(settings.highPassHz, 480);
    expect(settings.lowPassHz, 500);
    expect(settings.drive, 1);
    expect(settings.reverb, 0);
    expect(settings.punch, 0.6);
  });

  test('built-in presets include neutral and standard EQ configurations', () {
    expect(builtInAudioPresets.map((preset) => preset.id), contains('flat'));
    expect(builtInAudioPresets.map((preset) => preset.id), contains('rock'));
    expect(builtInAudioPresets.map((preset) => preset.id), contains('pop'));
    expect(builtInAudioPresets.map((preset) => preset.id), contains('jazz'));
    expect(
      builtInAudioPresets.map((preset) => preset.id),
      contains('classical'),
    );
    expect(builtInAudioPresets.map((preset) => preset.id), contains('dance'));
    expect(
      builtInAudioPresets.map((preset) => preset.id),
      contains('electronic'),
    );
    expect(builtInAudioPresets.map((preset) => preset.id), contains('hiphop'));
    expect(builtInAudioPresets.map((preset) => preset.id), contains('vocal'));
    expect(
      builtInAudioPresets.map((preset) => preset.id),
      contains('acoustic'),
    );
    expect(builtInAudioPresets.map((preset) => preset.id), contains('bass'));
    expect(builtInAudioPresets.map((preset) => preset.id), contains('treble'));

    final flat = builtInAudioPresets.firstWhere(
      (preset) => preset.id == 'flat',
    );
    final bass = builtInAudioPresets.firstWhere(
      (preset) => preset.id == 'bass',
    );
    expect(flat.gains, everyElement(0));
    expect(flat.preampDb, 0);
    expect(bass.gains.first, greaterThan(bass.gains[4]));

    final vocal = builtInAudioPresets.firstWhere(
      (preset) => preset.id == 'vocal',
    );
    final dance = builtInAudioPresets.firstWhere(
      (preset) => preset.id == 'dance',
    );
    final treble = builtInAudioPresets.firstWhere(
      (preset) => preset.id == 'treble',
    );
    expect(vocal.gains[6], greaterThan(vocal.gains[0]));
    expect(dance.gains[3], lessThan(-1.0));
    expect(treble.gains[8], greaterThan(treble.gains[0]));

    for (final preset in builtInAudioPresets) {
      expect(preset.gains, hasLength(eqBandCount));
      expect(preset.gains, everyElement(inInclusiveRange(-4.0, 4.0)));
      expect(preset.preampDb, inInclusiveRange(-2.0, 0.0));
    }
  });

  test('keeps the peak limiter independent from the creative DSP switch', () {
    const settings = AudioDspSettings(limiterEnabled: true);

    expect(settings.isNeutral, isFalse);
    expect(settings.hasToneShaping, isFalse);
    expect(settings.copyWith(limiterEnabled: false).isNeutral, isTrue);
  });

  test('preserves the EQ switch independently from the effects chain', () {
    final preference = PlaybackPreference.fromMap({
      'playMode': PlayMode.forward.name,
      'eqEnabled': false,
      'audioDspSettings': {'enabled': true, 'drive': 0.2},
    });

    expect(preference.eqEnabled, isFalse);
    expect(preference.audioDspSettings.enabled, isTrue);
    expect(preference.toMap()['eqEnabled'], isFalse);
  });
}
