import 'dart:async';

import 'package:pure_music/core/global_hotkey_binding.dart';
import 'package:pure_music/core/paths.dart' as app_paths;
import 'package:pure_music/core/preference.dart';
import 'package:pure_music/core/settings.dart';
import 'package:pure_music/component/hotkey_ui_feedback.dart';
import 'package:pure_music/core/hotkey_focus_state.dart';
import 'package:pure_music/core/immersive.dart';
import 'package:pure_music/play_service/play_service.dart';
import 'package:pure_music/native/bass/bass_player.dart';
import 'package:pure_music/core/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static bool _inAppRegistered = false;
  static bool _recordingSuspended = false;
  static bool _restoreInAppAfterRecording = false;
  static bool _windowToggleInProgress = false;
  static final Map<GlobalHotkeyAction, HotKey> _globalHotkeys = {};

  static bool _canHandlePlaybackHotkey() => canHandleInAppPlaybackHotkey(
    textInputFocused: isTextInputFocusedForHotkeys(),
  );

  static final Map<HotKey, void Function(HotKey)> _inAppHotkeys = {
    HotKey(key: PhysicalKeyboardKey.space, scope: HotKeyScope.inapp): (_) {
      if (!_canHandlePlaybackHotkey()) return;

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
    },
    HotKey(
      key: PhysicalKeyboardKey.escape,
      scope: HotKeyScope.inapp,
    ): (_) async {
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

      // 先关闭弹窗，再返回上一级页面
      final navigator = Navigator.maybeOf(routerContext);
      if (navigator?.canPop() == true) {
        navigator?.pop();
      } else if (routerKey.currentContext?.canPop() == true) {
        routerKey.currentContext?.pop();
      }
    },
    HotKey(
      key: PhysicalKeyboardKey.arrowLeft,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.inapp,
    ): (_) {
      if (!_canHandlePlaybackHotkey()) return;
      final playbackService = PlayService.existingPlaybackService;
      if (playbackService == null) return;
      playbackService.lastAudio();
      hotkeyUiFeedback.emit(HotkeyUiAction.prev);
      showHotkeyToast(text: '上一曲', icon: Icons.skip_previous);
    },
    HotKey(
      key: PhysicalKeyboardKey.arrowRight,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.inapp,
    ): (_) {
      if (!_canHandlePlaybackHotkey()) return;
      final playbackService = PlayService.existingPlaybackService;
      if (playbackService == null) return;
      playbackService.nextAudio();
      hotkeyUiFeedback.emit(HotkeyUiAction.next);
      showHotkeyToast(text: '下一曲', icon: Icons.skip_next);
    },
    HotKey(
      key: PhysicalKeyboardKey.arrowUp,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.inapp,
    ): (_) {
      if (!_canHandlePlaybackHotkey()) return;
      final playbackService = PlayService.existingPlaybackService;
      if (playbackService == null) return;
      final next = (playbackService.volumeDsp + 0.05).clamp(0.0, 1.0);
      playbackService.setVolumeDsp(next);
      hotkeyUiFeedback.emit(HotkeyUiAction.volumeStep);
      showHotkeyToast(
        text: '应用音量：${(next * 100).round()}%',
        icon: Icons.volume_up,
      );
    },
    HotKey(
      key: PhysicalKeyboardKey.arrowDown,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.inapp,
    ): (_) {
      if (!_canHandlePlaybackHotkey()) return;
      final playbackService = PlayService.existingPlaybackService;
      if (playbackService == null) return;
      final next = (playbackService.volumeDsp - 0.05).clamp(0.0, 1.0);
      playbackService.setVolumeDsp(next);
      hotkeyUiFeedback.emit(HotkeyUiAction.volumeStep);
      showHotkeyToast(
        text: '应用音量：${(next * 100).round()}%',
        icon: Icons.volume_down,
      );
    },
    HotKey(key: PhysicalKeyboardKey.f1, scope: HotKeyScope.inapp): (_) async {
      if (!_canHandlePlaybackHotkey()) return;
      await ImmersiveModeController.instance.toggle();
      showHotkeyToast(
        text: "沉浸：${ImmersiveModeController.instance.enabled ? "开" : "关"}",
        icon: Icons.fullscreen,
      );
    },
    HotKey(key: PhysicalKeyboardKey.f11, scope: HotKeyScope.inapp): (_) async {
      if (_windowToggleInProgress) return;
      _windowToggleInProgress = true;
      try {
        // 全屏铺满整块显示器，覆盖任务栏
        final isFullScreen = await windowManager.isFullScreen();
        await windowManager.setFullScreen(!isFullScreen);
        showHotkeyToast(
          text: isFullScreen ? '退出全屏' : '全屏',
          icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
        );
      } catch (err, trace) {
        logger.e('F11 窗口切换失败', error: err, stackTrace: trace);
      } finally {
        _windowToggleInProgress = false;
      }
    },
  };

  static Future<void> registerHotKeys() async {
    if (_inAppRegistered) return;
    for (final item in _inAppHotkeys.entries) {
      await hotKeyManager.register(item.key, keyDownHandler: item.value);
    }
    _inAppRegistered = true;
  }

  static Future<void> unregisterAll() async {
    await hotKeyManager.unregisterAll();
    _inAppRegistered = false;
    _globalHotkeys.clear();
    _recordingSuspended = false;
    _restoreInAppAfterRecording = false;
  }

  static Future<void> _unregisterInAppHotkeys() async {
    if (!_inAppRegistered) return;
    for (final hotkey in _inAppHotkeys.keys) {
      await hotKeyManager.unregister(hotkey);
    }
    _inAppRegistered = false;
  }

  static Future<void> unregisterGlobalHotkeys() async {
    final hotkeys = _globalHotkeys.values.toList();
    _globalHotkeys.clear();
    for (final hotkey in hotkeys) {
      await hotKeyManager.unregister(hotkey);
    }
  }

  static Future<void> onFocusChanges(bool focus) async {
    if (focus) {
      await _unregisterInAppHotkeys();
    } else {
      await registerHotKeys();
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
    _restoreInAppAfterRecording = _inAppRegistered;
    await _unregisterInAppHotkeys();
    await unregisterGlobalHotkeys();
  }

  static Future<void> resumeAfterHotkeyRecording() async {
    if (!_recordingSuspended) return;
    _recordingSuspended = false;
    await registerGlobalHotkeys();
    if (_restoreInAppAfterRecording) {
      await registerHotKeys();
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
    await _restoreGlobalHotkey(
      action,
      previousBindings[action],
      previousHotkey,
    );
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
        _handlePreviousTrack();
        return;
      case GlobalHotkeyAction.nextTrack:
        _handleNextTrack();
        return;
      case GlobalHotkeyAction.togglePlayback:
        _handleTogglePlayback();
        return;
      case GlobalHotkeyAction.toggleDesktopLyric:
        unawaited(_handleToggleDesktopLyric());
        return;
      case GlobalHotkeyAction.volumeUp:
        _handleIncreaseVolume();
        return;
      case GlobalHotkeyAction.volumeDown:
        _handleDecreaseVolume();
        return;
    }
  }

  static void _handlePreviousTrack() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    playbackService.lastAudio();
    hotkeyUiFeedback.emit(HotkeyUiAction.prev);
    showHotkeyToast(text: '上一曲', icon: Icons.skip_previous);
  }

  static void _handleNextTrack() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    playbackService.nextAudio();
    hotkeyUiFeedback.emit(HotkeyUiAction.next);
    showHotkeyToast(text: '下一曲', icon: Icons.skip_next);
  }

  static void _handleTogglePlayback() {
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

  static Future<void> _handleToggleDesktopLyric() async {
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

  static void _handleIncreaseVolume() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    final next = (playbackService.volumeDsp + 0.05).clamp(0.0, 1.0);
    playbackService.setVolumeDsp(next);
    hotkeyUiFeedback.emit(HotkeyUiAction.volumeStep);
    showHotkeyToast(
      text: '应用音量：${(next * 100).round()}%',
      icon: Icons.volume_up,
    );
  }

  static void _handleDecreaseVolume() {
    final playbackService = PlayService.existingPlaybackService;
    if (playbackService == null) return;
    final next = (playbackService.volumeDsp - 0.05).clamp(0.0, 1.0);
    playbackService.setVolumeDsp(next);
    hotkeyUiFeedback.emit(HotkeyUiAction.volumeStep);
    showHotkeyToast(
      text: '应用音量：${(next * 100).round()}%',
      icon: Icons.volume_down,
    );
  }
}
