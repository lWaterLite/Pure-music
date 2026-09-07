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

Future<void> showReplayGainBatchWriteDialog({
  required BuildContext context,
  required List<Album> albums,
  required rust_replay_gain.ReplayGainScanMode mode,
}) async {
  final jobs = albums
      .map(
        (album) => _ReplayGainAlbumJob(
          name: album.name,
          paths: album.works.map((audio) => audio.path).toList(growable: false),
        ),
      )
      .where((job) => job.paths.isNotEmpty)
      .toList(growable: false);
  if (jobs.isEmpty) {
    logger.w('[replay gain] batch skipped without playable albums');
    return;
  }

  final paths = jobs.expand((job) => job.paths).toList(growable: false);
  final modeName = _modeName(mode);
  logger.i(
    '[replay gain] batch requested mode=$modeName albums=${jobs.length} '
    'tracks=${paths.length}',
  );
  final existingTagCount = await _existingReplayGainTagCount(paths);
  if (!context.mounted) return;
  if (existingTagCount > 0) {
    logger.i(
      '[replay gain] batch overwrite confirmation mode=$modeName '
      'albums=${jobs.length} taggedTracks=$existingTagCount',
    );
    final confirmed = await showDangerConfirmDialog(
      context: context,
      title: '覆盖回放增益标签？',
      message: '所选 ${jobs.length} 张专辑中有 $existingTagCount 首歌曲已有回放增益标签。'
          '继续将覆盖所选类型的增益与峰值标签。',
      confirmLabel: '覆盖并继续',
    );
    if (!confirmed || !context.mounted) {
      logger.i('[replay gain] batch cancelled before write mode=$modeName');
      return;
    }
  }

  logger.i(
    '[replay gain] batch dialog opened mode=$modeName albums=${jobs.length}',
  );
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReplayGainBatchWriteDialog(jobs: jobs, mode: mode),
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

class _ReplayGainAlbumJob {
  const _ReplayGainAlbumJob({required this.name, required this.paths});

  final String name;
  final List<String> paths;
}

class _ReplayGainBatchWriteDialog extends StatefulWidget {
  const _ReplayGainBatchWriteDialog({required this.jobs, required this.mode});

  final List<_ReplayGainAlbumJob> jobs;
  final rust_replay_gain.ReplayGainScanMode mode;

  @override
  State<_ReplayGainBatchWriteDialog> createState() =>
      _ReplayGainBatchWriteDialogState();
}

class _ReplayGainBatchWriteDialogState
    extends State<_ReplayGainBatchWriteDialog> {
  rust_replay_gain.ReplayGainProgress? _trackProgress;
  int _currentAlbumIndex = 0;
  int _completedAlbums = 0;
  int _failedAlbums = 0;
  int _failedTracks = 0;
  String? _message;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_writeAlbums());
  }

  Future<void> _writeAlbums() async {
    final modeName = _modeName(widget.mode);
    logger.i(
      '[replay gain] batch write started mode=$modeName albums=${widget.jobs.length}',
    );
    for (var index = 0; index < widget.jobs.length; index++) {
      final job = widget.jobs[index];
      rust_replay_gain.ReplayGainProgress? finalProgress;
      if (mounted) {
        setState(() {
          _currentAlbumIndex = index;
          _trackProgress = null;
          _message = '正在处理第 ${index + 1} 张专辑…';
        });
      }
      logger.i(
        '[replay gain] batch album started mode=$modeName '
        'index=${index + 1}/${widget.jobs.length} tracks=${job.paths.length}',
      );
      try {
        await for (final progress in rust_replay_gain.writeReplayGain(
          paths: job.paths,
          mode: widget.mode,
        )) {
          finalProgress = progress;
          if (mounted) setState(() => _trackProgress = progress);
        }
        _failedTracks += finalProgress?.failed.toInt() ?? 0;
        logger.i(
          '[replay gain] batch album completed mode=$modeName '
          'index=${index + 1}/${widget.jobs.length} '
          'failed=${finalProgress?.failed ?? 0}',
        );
      } catch (error, trace) {
        _failedAlbums++;
        _failedTracks += finalProgress?.failed.toInt() ?? 0;
        logger.e(
          '[replay gain] batch album failed mode=$modeName '
          'index=${index + 1}/${widget.jobs.length}',
          error: error,
          stackTrace: trace,
        );
        if (mounted) {
          setState(() => _message = '第 ${index + 1} 张专辑处理失败，继续下一张…');
        }
      }
      if (mounted) setState(() => _completedAlbums = index + 1);
    }

    logger.i(
      '[replay gain] batch write completed mode=$modeName '
      'albums=${widget.jobs.length} failedAlbums=$_failedAlbums '
      'failedTracks=$_failedTracks',
    );
    if (!mounted) return;
    PlayService.instance.playbackService.refreshReplayGain();
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final currentJob = widget.jobs[_currentAlbumIndex];
    final trackProgress = _trackProgress;
    final trackCompleted = trackProgress?.completed.toInt() ?? 0;
    final trackTotal = trackProgress?.total.toInt() ?? currentJob.paths.length;
    final trackProgressValue = trackTotal == 0 ? 0.0 : trackCompleted / trackTotal;
    final albumProgressValue = widget.jobs.isEmpty
        ? 0.0
        : _completedAlbums / widget.jobs.length;
    final title = switch (widget.mode) {
      rust_replay_gain.ReplayGainScanMode.album => '批量写入专辑回放增益',
      rust_replay_gain.ReplayGainScanMode.track => '批量写入音轨回放增益',
    };
    final message = _done
        ? _failedAlbums == 0 && _failedTracks == 0
            ? '已完成'
            : '已完成，$_failedAlbums 张专辑、$_failedTracks 首歌曲处理失败'
        : _message ?? trackProgress?.message ?? '正在准备…';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: 20.0),
            Text('专辑进度：$_completedAlbums / ${widget.jobs.length}'),
            const SizedBox(height: 8.0),
            LinearProgressIndicator(
              value: albumProgressValue.clamp(0.0, 1.0),
              borderRadius: AppRadius.xsCircular,
            ),
            const SizedBox(height: 20.0),
            Text(
              '当前专辑：${currentJob.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8.0),
            Text('歌曲进度：$trackCompleted / $trackTotal'),
            const SizedBox(height: 8.0),
            LinearProgressIndicator(
              value: trackProgressValue.clamp(0.0, 1.0),
              borderRadius: AppRadius.xsCircular,
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
