import 'package:flutter_test/flutter_test.dart';
import 'package:pure_music/core/equalizer_preset_parser.dart';

void main() {
  test('parses a GraphicEQ line and interpolates on a log scale', () {
    final parsed = parseWaveletEqContent(
      'Preamp: -3.5 dB\n'
      'GraphicEQ: 31 -2; 62 -1; 1000 4; 16000 1; 20000 1;',
    );

    expect(parsed.preampDb, -3.5);
    expect(parsed.gains, hasLength(10));
    expect(parsed.gains.first, closeTo(-2.0, 0.0001));
    expect(parsed.gains[5], closeTo(4.0, 0.0001));
    expect(parsed.gains.last, closeTo(1.0, 0.0001));
  });

  test('ignores malformed and duplicate points while clamping gains', () {
    final parsed = parseWaveletEqContent(
      '31 100; 31 16; bad; 1000 -30; 16000 2; 20000 2;',
    );

    expect(parsed.gains.first, 15.0);
    expect(parsed.gains[5], -15.0);
    expect(parsed.gains.last, 2.0);
  });

  test('isolates malformed files during batch parsing', () {
    final result = parseWaveletEqBatch(const [
      WaveletEqPresetSource(
        name: 'valid',
        content: 'GraphicEQ: 31 1; 16000 2;',
      ),
      WaveletEqPresetSource(name: 'broken', content: 'not an EQ preset'),
      WaveletEqPresetSource(
        name: 'with-preamp',
        content: 'Preamp: -4\nGraphicEQ: 31 0; 16000 0;',
      ),
    ], fallbackPreampDb: -1);

    expect(result.presets, hasLength(2));
    expect(result.failed, 1);
    expect(result.presets[0].name, 'valid');
    expect(result.presets[0].preampDb, -1);
    expect(result.presets[1].preampDb, -4);
  });
}
