import 'dart:async';

import 'package:pure_music/core/global_hotkey_binding.dart';
import 'package:pure_music/core/hotkey_binding.dart';
import 'package:pure_music/core/paths.dart' as app_paths;
import 'package:pure_music/core/preference.dart';
import 'package:pure_music/component/hotkey_ui_feedback.dart';
import 'package:pure_music/core/hotkey_focus_state.dart';
import 'package:pure_music/core/immersive.dart';
import 'package:pure_music/core/settings.dart';
import 'package:pure_music/play_service/play_service.dart';
import 'package:pure_music/native/bass/bass_player.dart';
import 'package:pure_music/core/utils.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

class GlobalHotkeyUpdateResult {
  const GlobalHotkeyUpdateResult._({this.error});

  const GlobalHotkeyUpdateResult.success() : error = null;

  final String? error;

  bool get isSuccess => error == null;
}

class HotkeysHelper {
  static final List<HotKey> _inAppKeys = [];
  static final Map<GlobalHotkeyAction, HotKey> _globalHotkeys = {};
  static bool _windowToggleInProgress = false;
  static bool _inAppPaused = false;
  static bool _recordingSuspended = false;
  static bool _restoreInAppAfterRecording = false;

  static bool _canHandlePlaybackHotkey() => canHandleInAppPlaybackHotkey(
    textInputFocused: isTextInputFocusedForHotkeys(),
  );

  static String inAppLabel(HotkeyAction action) =>
      (AppSettings.instance.inAppHotkeys[action] ?? defaultInAppBinding(action))
          .label;

  static Future<void> registerHotKeys() async {
    await _registerInApp();
  }

  static Future<void> reload() async {
    await _unregisterInApp();
    await unregisterGlobalHotkeys();
    if (_recordingSuspended) return;
    await registerHotKeys();
    await registerGlobalHotkeys();
  }

  static Future<void> unregisterAll() async {
    await hotKeyManager.unregisterAll();
    _inAppKeys.clear();
    _globalHotkeys.clear();
    _recordingSuspended = false;
    _restoreInAppAfterRecording = false;
  }

  static Future<void> onFocusChanges(bool focus) async {
    _inAppPaused = focus;
    if (focus) {
      await _unregisterInApp();
    } else {
      await _registerInApp();
    }
  }

  static Future<void> pauseForRecording() async {
    await suspendForHotkeyRecording();
  }

  static Future<void> resumeAfterRecording() async {
    await resumeAfterHotkeyRecording();
  }

  static Future<void> _registerInApp() async {
    if (_inAppPaused || _inAppKeys.isNotEmpty) return;
    final bindings = AppSettings.instance.inAppHotkeys;
    for (final action in inAppHotkeyActions) {
      final binding = bindings[action] ?? defaultInAppBinding(action);
      final hotKey = binding.toHotKey(
        scope: HotKeyScope.inapp,
        identifier: 'inapp.${action.name}',
      );
      if (hotKey == null) continue;
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _handleInAppHotkey(action),
      );
      _inAppKeys.add(hotKey);
    }
  }

  static Future<void> _unregisterInApp() async {
    for (final key in _inAppKeys) {
      await hotKeyManager.unregister(key);
    }
    _inAppKeys.clear();
  }

  static Future<void> unregisterGlobalHotkeys() async {
    final hotkeys = _globalHotkeys.values.toList();
    _globalHotkeys.clear();
    for (final hotkey in hotkeys) {
      await hotKeyManager.unregister(hotkey);
    }
  }

  static void _handleInAppHotkey(HotkeyAction action) {
    if (action != HotkeyAction.escape &&
        action != HotkeyAction.fullscreen &&
        !_canHandlePlaybackHotkey()) {
      return;
    }
    switch (action) {
      case HotkeyAction.playPause:
        _togglePlayback();
      case HotkeyAction.previous:
        _skipPrevious();
      case HotkeyAction.next:
        _skipNext();
      case HotkeyAction.volumeUp:
        _changeVolume(0.05);
      case HotkeyAction.volumeDown:
        _changeVolume(-0.05);
      case HotkeyAction.immersive:
        unawaited(_toggleImmersive());
      case HotkeyAction.fullscreen:
        unawaited(_toggleFullscreen());
      case HotkeyAction.escape:
        unawaited(_handleEscape());
    }
  }

  static Future<void> registerGlobalHotkeys() async {
    if (_recordingSuspended) return;
    await unregisterGlobalHotkeys();
    for (final action in GlobalHotkeyAction.values) {
      final binding = AppSettings.instance.globalHotkeys[action];
      if (binding == null || !binding.isValid) continue;
      try {
        await _registerGlobalHotkey(action, binding);
      } catch (err, trace) {
        logger.e(
          '全局快捷键注册失败：${action.storageKey}',
          error: err,
          stackTrace: trace,
        );
      }
    }
  }

  static Future<void> suspendForHotkeyRecording() async {
    if (_recordingSuspended) return;
    _recordingSuspended = true;
    _restoreInAppAfterRecording = _inAppKeys.isNotEmpty;
    await _unregisterInApp();
    await unregisterGlobalHotkeys();
  }

  static Future<void> resumeAfterHotkeyRecording() async {
    if (!_recordingSuspended) return;
    _recordingSuspended = false;
    await registerGlobalHotkeys();
    if (_restoreInAppAfterRecording && !_inAppPaused) {
      await _registerInApp();
    }
    _restoreInAppAfterRecording = false;
  }

  static Future<GlobalHotkeyUpdateResult> updateGlobalHotkey(
    GlobalHotkeyAction action,
    GlobalHotkeyBinding binding,
  ) async {
    if (!binding.isValid) {
      return const GlobalHotkeyUpdateResult._(
        error: '快捷键必须包含 Ctrl、Alt 或 Shift，且只能有一个主键',
      );
    }
    final settings = AppSettings.instance;
    final previousBindings = Map<GlobalHotkeyAction, GlobalHotkeyBinding>.from(
      settings.globalHotkeys,
    );
    if (previousBindings.entries.any(
      (entry) =>
          entry.key != action && entry.value.signature == binding.signature,
    )) {
      return const GlobalHotkeyUpdateResult._(error: '该快捷键已分配给其他操作');
    }
    if (previousBindings[action]?.signature == binding.signature) {
      return const GlobalHotkeyUpdateResult.success();
    }

    final previousHotkey = _globalHotkeys.remove(action);
    if (previousHotkey != null) {
      await hotKeyManager.unregister(previousHotkey);
    }
    try {
      await _registerGlobalHotkey(action, binding);
    } catch (err, trace) {
      logger.e('全局快捷键更新失败：${action.storageKey}', error: err, stackTrace: trace);
      await _restoreGlobalHotkey(
        action,
        previousBindings[action],
        previousHotkey,
      );
      return const GlobalHotkeyUpdateResult._(error: '该快捷键已被系统或其他程序占用');
    }

    settings.globalHotkeys = Map<GlobalHotkeyAction, GlobalHotkeyBinding>.from(
      previousBindings,
    )..[action] = binding;
    if (await settings.saveSettings()) {
      return const GlobalHotkeyUpdateResult.success();
    }

    settings.globalHotkeys = previousBindings;
    final currentHotkey = _globalHotkeys.remove(action);
    if (currentHotkey != null) {
      await hotKeyManager.unregister(currentHotkey);
    }
    await _restoreGlobalHotkey(action, previousBindings[action], previousHotkey);
    return const GlobalHotkeyUpdateResult._(error: '快捷键设置保存失败');
  }

  static Future<void> _restoreGlobalHotkey(
    GlobalHotkeyAction action,
    GlobalHotkeyBinding? binding,
    HotKey? previousHotkey,
  ) async {
    if (binding == null || previousHotkey == null) return;
    try {
      await _registerGlobalHotkey(action, binding);
    } catch (err, trace) {
      logger.e(
        '恢复原全局快捷键失败：${action.storageKey}',
        error: err,
        stackTrace: trace,
      );
    }
  }

  static Future<void> _registerGlobalHotkey(
    GlobalHotkeyAction action,
    GlobalHotkeyBinding binding,
  ) async {
    final hotkey = binding.toHotKey(action);
    await hotKeyManager.register(
      hotkey,
      keyDownHandler: (_) => _handleGlobalHotkey(action),
    );
    _globalHotkeys[action] = hotkey;
  }

  static void _handleGlobalHotkey(GlobalHotkeyAction action) {
    switch (action) {
      case GlobalHotkeyAction.previousTrack:
        _skipPrevious();
      case GlobalHotkeyAction.nextTrack:
        _skipNext();
      case GlobalHotkeyAction.togglePlayback:
        _togglePlayback();
      case GlobalHotkeyAction.toggleDesktopLyric:
        unawaited(_toggleDesktopLyric());
      case GlobalHotkeyAction.volumeUp:
        _changeVolume(0.05);
      case GlobalHotkeyAction.volumeDown:
        _changeVolume(-0.05);
    }
  }

  static void _togglePlayback() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    final state = playbackService.playerState;
    if (state == PlayerState.playing) {
      playbackService.pause();
      showHotkeyToast(text: '暂停', icon: Icons.pause);
    } else if (state == PlayerState.completed) {
      playbackService.playAgain();
      showHotkeyToast(text: '重播', icon: Icons.replay);
    } else {
      playbackService.start();
      showHotkeyToast(text: '播放', icon: Icons.play_arrow);
    }
  }

  static void _skipPrevious() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    playbackService.lastAudio();
    hotkeyUiFeedback.emit(HotkeyUiAction.prev);
    showHotkeyToast(text: '上一曲', icon: Icons.skip_previous);
  }

  static void _skipNext() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    playbackService.nextAudio();
    hotkeyUiFeedback.emit(HotkeyUiAction.next);
    showHotkeyToast(text: '下一曲', icon: Icons.skip_next);
  }

  static void _changeVolume(double delta) {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    final next = (playbackService.volumeDsp + delta).clamp(0.0, 1.0);
    playbackService.setVolumeDsp(next);
    hotkeyUiFeedback.emit(HotkeyUiAction.volumeStep);
    showHotkeyToast(
      text: '应用音量：${(next * 100).round()}%',
      icon: delta > 0 ? Icons.volume_up : Icons.volume_down,
    );
  }

  static Future<void> _toggleDesktopLyric() async {
    final desktopLyric = PlayService.instance.desktopLyricService;
    if (desktopLyric.isKilling) return;
    if (desktopLyric.isRunning) {
      await desktopLyric.killDesktopLyric();
      showHotkeyToast(text: '关闭桌面歌词', icon: Icons.desktop_windows);
    } else {
      await desktopLyric.startDesktopLyric();
      showHotkeyToast(text: '打开桌面歌词', icon: Icons.desktop_windows);
    }
  }

  static Future<void> _toggleImmersive() async {
    await ImmersiveModeController.instance.toggle();
    showHotkeyToast(
      text: "沉浸：${ImmersiveModeController.instance.enabled ? "开" : "关"}",
      icon: Icons.fullscreen,
    );
  }

  static Future<void> _toggleFullscreen() async {
    if (_windowToggleInProgress) return;
    _windowToggleInProgress = true;
    try {
      final isFullScreen = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFullScreen);
      showHotkeyToast(
        text: isFullScreen ? '退出全屏' : '全屏',
        icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
      );
    } catch (err, trace) {
      logger.e('全屏切换失败', error: err, stackTrace: trace);
    } finally {
      _windowToggleInProgress = false;
    }
  }

  static Future<void> _handleEscape() async {
    final routerContext = routerKey.currentContext;
    if (routerContext == null) return;

    final router = GoRouter.of(routerContext);
    if (ImmersiveModeController.instance.enabled) {
      await ImmersiveModeController.instance.exit();
      final startIndex = AppPreference.instance.startPage.clamp(
        0,
        app_paths.START_PAGES.length - 1,
      );
      router.go(app_paths.START_PAGES[startIndex]);
      return;
    }

    final navigator = Navigator.maybeOf(routerContext);
    if (navigator?.canPop() == true) {
      navigator?.pop();
    } else if (routerKey.currentContext?.canPop() == true) {
      routerKey.currentContext?.pop();
    }
  }
}
