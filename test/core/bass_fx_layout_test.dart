import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_music/native/bass/bass.dart';

void main() {
  test('BASS_FX compressor2 uses official gain/threshold/ratio layout', () {
    expect(sizeOf<BASS_BFX_COMPRESSOR2>(), 24);
    expect(sizeOf<BASS_BFX_REVERB>(), 16);
    expect(BASS_BFX_CHANALL, -1);

    final params = calloc<BASS_BFX_COMPRESSOR2>();
    params.ref
      ..fGain = 1.5
      ..fThreshold = -6
      ..fRatio = 3
      ..fAttack = 5
      ..fRelease = 120
      ..lChannel = BASS_BFX_CHANALL;

    final floats = params.cast<Float>();
    expect(floats[0], 1.5);
    expect(floats[1], -6);
    expect(floats[2], 3);
    expect(floats[3], 5);
    expect(floats[4], 120);
    expect(params.ref.lChannel, -1);
    calloc.free(params);
  });
}
