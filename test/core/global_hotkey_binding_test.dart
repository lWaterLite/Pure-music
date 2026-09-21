import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:pure_music/core/global_hotkey_binding.dart';

void main() {
  test('默认全局快捷键合法且互不重复', () {
    final bindings = defaultGlobalHotkeyBindings();

    expect(bindings.length, GlobalHotkeyAction.values.length);
    expect(bindings.values.every((binding) => binding.isValid), isTrue);
    expect(
      bindings.values.map((binding) => binding.signature).toSet().length,
      bindings.length,
    );
    expect(
      bindings[GlobalHotkeyAction.volumeUp]!.displayName,
      'Ctrl + Alt + ↑',
    );
    expect(
      bindings[GlobalHotkeyAction.volumeDown]!.displayName,
      'Ctrl + Alt + ↓',
    );
  });

  test('不接受缺少修饰键或包含 Windows 键的组合', () {
    expect(
      const GlobalHotkeyBinding(
        key: PhysicalKeyboardKey.keyP,
        modifiers: [],
      ).isValid,
      isFalse,
    );
    expect(
      const GlobalHotkeyBinding(
        key: PhysicalKeyboardKey.keyP,
        modifiers: [HotKeyModifier.meta],
      ).isValid,
      isFalse,
    );
  });

  test('读取重复配置时恢复为互不冲突的默认组合', () {
    final defaults = defaultGlobalHotkeyBindings();
    final previous = defaults[GlobalHotkeyAction.previousTrack]!;
    final normalized = normalizedGlobalHotkeyBindings({
      GlobalHotkeyAction.previousTrack.storageKey: previous.toJson(),
      GlobalHotkeyAction.nextTrack.storageKey: previous.toJson(),
    });

    expect(normalized.values.every((binding) => binding.isValid), isTrue);
    expect(
      normalized.values.map((binding) => binding.signature).toSet().length,
      GlobalHotkeyAction.values.length,
    );
  });
}
