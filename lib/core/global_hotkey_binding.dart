import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

enum GlobalHotkeyAction {
  previousTrack('previousTrack', '上一首'),
  nextTrack('nextTrack', '下一首'),
  togglePlayback('togglePlayback', '播放 / 暂停'),
  toggleDesktopLyric('toggleDesktopLyric', '打开 / 关闭桌面歌词'),
  volumeUp('volumeUp', '增加应用音量'),
  volumeDown('volumeDown', '减小应用音量');

  const GlobalHotkeyAction(this.storageKey, this.label);

  final String storageKey;
  final String label;
}

class GlobalHotkeyBinding {
  const GlobalHotkeyBinding({required this.key, required this.modifiers});

  final PhysicalKeyboardKey key;
  final List<HotKeyModifier> modifiers;

  static const _allowedModifiers = <HotKeyModifier>{
    HotKeyModifier.control,
    HotKeyModifier.alt,
    HotKeyModifier.shift,
  };

  bool get isValid {
    if (modifiers.isEmpty ||
        modifiers.toSet().length != modifiers.length ||
        modifiers.any((item) => !_allowedModifiers.contains(item))) {
      return false;
    }
    if (HotKeyModifier.values.any((item) => item.physicalKeys.contains(key))) {
      return false;
    }
    final usage = key.usbHidUsage;
    return usage >= 0x00070004 && usage <= 0x00070073;
  }

  String get signature {
    final modifierNames = modifiers.map((item) => item.name).toList()..sort();
    return '${key.usbHidUsage}:${modifierNames.join(',')}';
  }

  String get displayName {
    final labels = <String>[
      if (modifiers.contains(HotKeyModifier.control)) 'Ctrl',
      if (modifiers.contains(HotKeyModifier.alt)) 'Alt',
      if (modifiers.contains(HotKeyModifier.shift)) 'Shift',
      _keyLabel(key),
    ];
    return labels.join(' + ');
  }

  HotKey toHotKey(GlobalHotkeyAction action) => HotKey(
    identifier: 'pure_music_global_${action.storageKey}',
    key: key,
    modifiers: modifiers,
    scope: HotKeyScope.system,
  );

  Map<String, dynamic> toJson() => {
    'usageCode': key.usbHidUsage,
    'modifiers': modifiers.map((item) => item.name).toList(),
  };

  static GlobalHotkeyBinding? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final usageCode = raw['usageCode'];
    final modifiers = raw['modifiers'];
    if (usageCode is! num || modifiers is! List) return null;

    final key = PhysicalKeyboardKey.findKeyByCode(usageCode.toInt());
    if (key == null) return null;
    final parsedModifiers = <HotKeyModifier>[];
    for (final value in modifiers) {
      if (value is! String) return null;
      final modifier = HotKeyModifier.values.where(
        (item) => item.name == value,
      );
      if (modifier.isEmpty) return null;
      parsedModifiers.add(modifier.first);
    }
    final binding = GlobalHotkeyBinding(key: key, modifiers: parsedModifiers);
    return binding.isValid ? binding : null;
  }

  static GlobalHotkeyBinding? fromHotKey(HotKey hotKey) {
    final key = hotKey.key;
    if (key is! PhysicalKeyboardKey) return null;
    final binding = GlobalHotkeyBinding(
      key: key,
      modifiers: List<HotKeyModifier>.from(hotKey.modifiers ?? const []),
    );
    return binding.isValid ? binding : null;
  }

  static String _keyLabel(PhysicalKeyboardKey key) {
    final usage = key.usbHidUsage;
    if (usage >= 0x00070004 && usage <= 0x0007001d) {
      return String.fromCharCode('A'.codeUnitAt(0) + usage - 0x00070004);
    }
    if (usage >= 0x0007001e && usage <= 0x00070027) {
      return '${(usage - 0x0007001d) % 10}';
    }
    if (usage >= 0x0007003a && usage <= 0x00070045) {
      return 'F${usage - 0x00070039}';
    }
    const labels = <int, String>{
      0x00070028: 'Enter',
      0x00070029: 'Esc',
      0x0007002a: 'Backspace',
      0x0007002b: 'Tab',
      0x0007002c: 'Space',
      0x0007004a: 'Home',
      0x0007004b: 'Page Down',
      0x0007004c: 'Delete',
      0x0007004d: 'End',
      0x0007004e: 'Page Up',
      0x0007004f: '→',
      0x00070050: '←',
      0x00070051: '↓',
      0x00070052: '↑',
    };
    return labels[usage] ?? 'Key 0x${usage.toRadixString(16)}';
  }
}

Map<GlobalHotkeyAction, GlobalHotkeyBinding> defaultGlobalHotkeyBindings() => {
  GlobalHotkeyAction.previousTrack: const GlobalHotkeyBinding(
    key: PhysicalKeyboardKey.arrowLeft,
    modifiers: [
      HotKeyModifier.control,
      HotKeyModifier.alt,
      HotKeyModifier.shift,
    ],
  ),
  GlobalHotkeyAction.nextTrack: const GlobalHotkeyBinding(
    key: PhysicalKeyboardKey.arrowRight,
    modifiers: [
      HotKeyModifier.control,
      HotKeyModifier.alt,
      HotKeyModifier.shift,
    ],
  ),
  GlobalHotkeyAction.togglePlayback: const GlobalHotkeyBinding(
    key: PhysicalKeyboardKey.keyP,
    modifiers: [
      HotKeyModifier.control,
      HotKeyModifier.alt,
      HotKeyModifier.shift,
    ],
  ),
  GlobalHotkeyAction.toggleDesktopLyric: const GlobalHotkeyBinding(
    key: PhysicalKeyboardKey.keyL,
    modifiers: [
      HotKeyModifier.control,
      HotKeyModifier.alt,
      HotKeyModifier.shift,
    ],
  ),
  GlobalHotkeyAction.volumeUp: const GlobalHotkeyBinding(
    key: PhysicalKeyboardKey.arrowUp,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
  ),
  GlobalHotkeyAction.volumeDown: const GlobalHotkeyBinding(
    key: PhysicalKeyboardKey.arrowDown,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
  ),
};

Map<GlobalHotkeyAction, GlobalHotkeyBinding> normalizedGlobalHotkeyBindings(
  Object? raw,
) {
  final defaults = defaultGlobalHotkeyBindings();
  if (raw is! Map) return defaults;

  final candidates = <GlobalHotkeyAction, GlobalHotkeyBinding>{
    for (final action in GlobalHotkeyAction.values)
      action:
          GlobalHotkeyBinding.tryParse(raw[action.storageKey]) ??
          defaults[action]!,
  };
  final signatures = <String, List<GlobalHotkeyAction>>{};
  for (final entry in candidates.entries) {
    signatures.putIfAbsent(entry.value.signature, () => []).add(entry.key);
  }
  for (final actions in signatures.values) {
    if (actions.length < 2) continue;
    for (final action in actions) {
      candidates[action] = defaults[action]!;
    }
  }
  return candidates;
}

Map<String, dynamic> globalHotkeyBindingsToJson(
  Map<GlobalHotkeyAction, GlobalHotkeyBinding> bindings,
) => {
  for (final action in GlobalHotkeyAction.values)
    action.storageKey:
        (bindings[action] ?? defaultGlobalHotkeyBindings()[action]!).toJson(),
};
