import 'package:flutter_test/flutter_test.dart';
import 'package:pure_music/core/lyric_match_scoring.dart';

void main() {
  test('normalizes compatible version suffixes before scoring', () {
    final result = scoreLyricMatch(
      title: '夜に駆ける (Live)',
      artist: 'YOASOBI',
      album: 'THE BOOK',
      candidateTitle: '夜に駆ける',
      candidateArtist: 'YOASOBI',
      candidateAlbum: 'THE BOOK',
      audioDurationSeconds: 260,
      candidateDurationSeconds: 262,
    );

    expect(result.titleMatched, isTrue);
    expect(result.identityMatched, isTrue);
    expect(result.score, greaterThanOrEqualTo(75));
  });

  test('album similarity contributes to an otherwise ambiguous match', () {
    final sameAlbum = scoreLyricMatch(
      title: 'Song',
      artist: 'Artist',
      album: 'Target Album',
      candidateTitle: 'Song',
      candidateArtist: 'Artist',
      candidateAlbum: 'Target Album',
    );
    final otherAlbum = scoreLyricMatch(
      title: 'Song',
      artist: 'Artist',
      album: 'Target Album',
      candidateTitle: 'Song',
      candidateArtist: 'Artist',
      candidateAlbum: 'Other Album',
    );

    expect(sameAlbum.score, greaterThan(otherAlbum.score));
  });

  test('duration mismatch reduces the score multiplicatively', () {
    final close = scoreLyricMatch(
      title: 'Song',
      artist: 'Artist',
      candidateTitle: 'Song',
      candidateArtist: 'Artist',
      audioDurationSeconds: 200,
      candidateDurationSeconds: 202,
    );
    final far = scoreLyricMatch(
      title: 'Song',
      artist: 'Artist',
      candidateTitle: 'Song',
      candidateArtist: 'Artist',
      audioDurationSeconds: 200,
      candidateDurationSeconds: 240,
    );

    expect(close.score, greaterThan(far.score));
    expect(far.score, lessThan(75));
  });
}
