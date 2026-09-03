import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pure_music/component/danger_confirm_dialog.dart';
import 'package:pure_music/core/design_tokens.dart';
import 'package:pure_music/core/utils.dart';
import 'package:pure_music/library/audio_library.dart';
import 'package:pure_music/native/rust/api/replay_gain.dart' as rust_replay_gain;
import 'package:pure_music/native/rust/api/tag_reader.dart' as rust_tag_reader;
import 'package:pure_music/play_service/play_service.dart';

Future<void> showReplayGainWriteDialog({
  required BuildContext context,
  required Album album,
  required rust_replay_gain.ReplayGainScanMode mode,
}) async {
  final paths = album.works.map((audio) => audio.path).toList(growable: false);
  final modeName = _modeName(mode);
  if (paths.isEmpty) {
    logger.w('[replay gain] skipped empty album name=${album.name} mode=$modeName');
    return;
  }
  logger.i(
    '[replay gain] requested album=${album.name} mode=$modeName total=${paths.length}',
  );
  final existingTagCount = await _existingReplayGainTagCount(paths);
  if (!context.mounted) return;
  if (existingTagCount > 0) {
    logger.i(
      '[replay gain] overwrite confirmation album=${album.name} '
      'mode=$modeName taggedTracks=$existingTagCount',
    );
    final confirmed = await showDangerConfirmDialog(
      context: context,
      title: '覆盖回放增益标签？',
      message: '此专辑已有回放增益标签。继续将覆盖所选类型的增益与峰值标签。',
      confirmLabel: '覆盖并继续',
    );
    if (!confirmed || !context.mounted) {
      logger.i('[replay gain] cancelled before write album=${album.name} mode=$modeName');
      return;
    }
  }
  logger.i('[replay gain] dialog opened album=${album.name} mode=$modeName');
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReplayGainWriteDialog(
      albumName: album.name,
      paths: paths,
      mode: mode,
    ),
  );
}

Future<int> _existingReplayGainTagCount(List<String> paths) async {
  var count = 0;
  for (final path in paths) {
    try {
      final metadata = await rust_tag_reader.readAudioExtraMetadata(path: path);
      final values = [
        metadata.replaygainTrackGain,
        metadata.replaygainTrackPeak,
        metadata.replaygainAlbumGain,
        metadata.replaygainAlbumPeak,
      ];
      if (values.any((value) => value?.trim().isNotEmpty == true)) count++;
    } catch (error, trace) {
      logger.w(
        '[replay gain] existing-tag check failed path=$path',
        error: error,
        stackTrace: trace,
      );
    }
  }
  return count;
}

class _ReplayGainWriteDialog extends StatefulWidget {
  const _ReplayGainWriteDialog({
    required this.albumName,
    required this.paths,
    required this.mode,
  });

  final String albumName;
  final List<String> paths;
  final rust_replay_gain.ReplayGainScanMode mode;

  @override
  State<_ReplayGainWriteDialog> createState() => _ReplayGainWriteDialogState();
}

class _ReplayGainWriteDialogState extends State<_ReplayGainWriteDialog> {
  StreamSubscription<rust_replay_gain.ReplayGainProgress>? _subscription;
  rust_replay_gain.ReplayGainProgress? _progress;
  String? _error;
  bool _done = false;
  bool _writeFailed = false;

  @override
  void initState() {
    super.initState();
    logger.i(
      '[replay gain] write started album=${widget.albumName} '
      'mode=${_modeName(widget.mode)} total=${widget.paths.length}',
    );
    _subscription = rust_replay_gain
        .writeReplayGain(paths: widget.paths, mode: widget.mode)
        .listen(
          (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onError: (Object error, StackTrace trace) {
            _writeFailed = true;
            logger.e(
              '[replay gain] write failed album=${widget.albumName} '
              'mode=${_modeName(widget.mode)}',
              error: error,
              stackTrace: trace,
            );
            if (mounted) {
              setState(() {
              _error = error.toString();
              _done = true;
            });
            }
          },
          onDone: () {
            final progress = _progress;
            logger.i(
              '[replay gain] write ${_writeFailed ? 'finished with error' : 'completed'} '
              'album=${widget.albumName} '
              'mode=${_modeName(widget.mode)} total=${progress?.total ?? widget.paths.length} '
              'failed=${progress?.failed ?? 0}',
            );
            if (!mounted) return;
            PlayService.instance.playbackService.refreshReplayGain();
            setState(() => _done = true);
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final completed = progress?.completed.toInt() ?? 0;
    final total = progress?.total.toInt() ?? widget.paths.length;
    final failed = progress?.failed.toInt() ?? 0;
    final progressValue = total == 0 ? 0.0 : completed / total;
    final title = switch (widget.mode) {
      rust_replay_gain.ReplayGainScanMode.album => '写入专辑回放增益',
      rust_replay_gain.ReplayGainScanMode.track => '写入音轨回放增益',
    };
    final message = _error ??
        (_done
            ? failed == 0
                ? '已完成'
                : '已完成，$failed 首歌曲处理失败'
            : progress?.message ?? '正在准备…');

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 16.0),
            LinearProgressIndicator(
              value: progressValue.clamp(0.0, 1.0),
              borderRadius: AppRadius.xsCircular,
            ),
            const SizedBox(height: 8.0),
            Text(
              '$completed / $total',
              textAlign: TextAlign.end,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _done ? () => Navigator.pop(context) : null,
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

String _modeName(rust_replay_gain.ReplayGainScanMode mode) => switch (mode) {
  rust_replay_gain.ReplayGainScanMode.album => 'album',
  rust_replay_gain.ReplayGainScanMode.track => 'track',
};
