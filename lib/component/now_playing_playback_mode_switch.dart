import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pure_music/core/enums.dart';
import 'package:pure_music/core/settings.dart';
import 'package:pure_music/play_service/play_service.dart';

class NowPlayingPlaybackModeSwitch extends StatelessWidget {
  const NowPlayingPlaybackModeSwitch({super.key, this.color});

  final Color? color;

  void _changeMode({required bool shuffle, required PlayMode playMode}) {
    final playbackService = PlayService.instance.playbackService;
    if (shuffle) {
      playbackService.useShuffle(false);
      playbackService.setPlayMode(PlayMode.forward);
      return;
    }

    switch (playMode) {
      case PlayMode.forward:
      case PlayMode.loop:
        playbackService.setPlayMode(PlayMode.singleLoop);
        break;
      case PlayMode.singleLoop:
        playbackService.useShuffle(true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foregroundColor =
        color ??
        (AppSettings.instance.useMaterialYouForControls
            ? scheme.primary
            : scheme.onSurface);
    final playbackService = PlayService.instance.playbackService;

    return ListenableBuilder(
      listenable: Listenable.merge([
        playbackService.shuffle,
        playbackService.playMode,
      ]),
      builder: (context, _) {
        final shuffle = playbackService.shuffle.value;
        final playMode = playbackService.playMode.value;
        final modeText = switch (true) {
          _ when shuffle => '随机播放',
          _ when playMode == PlayMode.singleLoop => '单曲循环',
          _ => '顺序播放',
        };
        final icon = switch (true) {
          _ when shuffle => Symbols.shuffle,
          _ when playMode == PlayMode.singleLoop => Symbols.repeat_one,
          _ => Symbols.repeat,
        };

        return IconButton(
          tooltip: modeText,
          onPressed: () => _changeMode(shuffle: shuffle, playMode: playMode),
          icon: Icon(icon, fill: 0.0, weight: 400.0),
          color: foregroundColor,
        );
      },
    );
  }
}
