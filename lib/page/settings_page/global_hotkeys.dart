import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pure_music/component/settings_tile.dart';
import 'package:pure_music/core/global_hotkey_binding.dart';
import 'package:pure_music/core/hotkeys.dart';
import 'package:pure_music/core/settings.dart';
import 'package:pure_music/core/utils.dart';

class GlobalHotkeysSettingsGroup extends StatefulWidget {
  const GlobalHotkeysSettingsGroup({super.key});

  @override
  State<GlobalHotkeysSettingsGroup> createState() =>
      _GlobalHotkeysSettingsGroupState();
}

class _GlobalHotkeysSettingsGroupState
    extends State<GlobalHotkeysSettingsGroup> {
  bool _editing = false;

  Future<void> _edit(GlobalHotkeyAction action) async {
    if (_editing) return;
    setState(() => _editing = true);
    final current =
        AppSettings.instance.globalHotkeys[action] ??
        defaultGlobalHotkeyBindings()[action]!;
    final usedSignatures = AppSettings.instance.globalHotkeys.entries
        .where((entry) => entry.key != action)
        .map((entry) => entry.value.signature)
        .toSet();

    GlobalHotkeyBinding? next;
    try {
      await HotkeysHelper.suspendForHotkeyRecording();
      if (!mounted) return;
      next = await showDialog<GlobalHotkeyBinding>(
        context: context,
        builder: (context) => _GlobalHotkeyRecorderDialog(
          action: action,
          current: current,
          usedSignatures: usedSignatures,
        ),
      );
    } finally {
      await HotkeysHelper.resumeAfterHotkeyRecording();
    }

    if (!mounted || next == null) {
      if (mounted) setState(() => _editing = false);
      return;
    }
    final result = await HotkeysHelper.updateGlobalHotkey(action, next);
    if (!mounted) return;
    setState(() => _editing = false);
    showTextOnSnackBar(
      result.isSuccess ? '${action.label}快捷键已更新' : result.error!,
      variant: result.isSuccess ? ToastVariant.success : ToastVariant.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bindings = AppSettings.instance.globalHotkeys;
    return ListView(
      padding: const EdgeInsets.only(right: 20, bottom: 96),
      children: [
        Text(
          '全局快捷键在应用失焦、隐藏或最小化时仍可使用。每个组合必须包含 Ctrl、Alt 或 Shift，且只能有一个主键。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (final action in GlobalHotkeyAction.values) ...[
          SettingsTile(
            description: action.label,
            subtitle: '点击后直接按下新的组合键',
            action: OutlinedButton.icon(
              onPressed: _editing ? null : () => _edit(action),
              icon: const Icon(Symbols.keyboard, size: 18),
              label: Text(
                (bindings[action] ?? defaultGlobalHotkeyBindings()[action]!)
                    .displayName,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _GlobalHotkeyRecorderDialog extends StatefulWidget {
  const _GlobalHotkeyRecorderDialog({
    required this.action,
    required this.current,
    required this.usedSignatures,
  });

  final GlobalHotkeyAction action;
  final GlobalHotkeyBinding current;
  final Set<String> usedSignatures;

  @override
  State<_GlobalHotkeyRecorderDialog> createState() =>
      _GlobalHotkeyRecorderDialogState();
}

class _GlobalHotkeyRecorderDialogState
    extends State<_GlobalHotkeyRecorderDialog> {
  String? _error;

  void _record(HotKey hotkey) {
    final binding = GlobalHotkeyBinding.fromHotKey(hotkey);
    if (binding == null) {
      setState(() => _error = '请按住 Ctrl、Alt 或 Shift，再按一个常规按键');
      return;
    }
    if (widget.usedSignatures.contains(binding.signature)) {
      setState(() => _error = '该快捷键已分配给其他操作');
      return;
    }
    Navigator.of(context).pop(binding);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('设置${widget.action.label}快捷键'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '请直接按下新的组合键。只有包含 Ctrl、Alt 或 Shift 的组合会被保存。',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Center(
              child: HotKeyRecorder(
                initalHotKey: widget.current.toHotKey(widget.action),
                onHotKeyRecorded: _record,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
