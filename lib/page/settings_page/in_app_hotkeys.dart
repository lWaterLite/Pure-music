import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:pure_music/component/settings_tile.dart';
import 'package:pure_music/core/design_tokens.dart';
import 'package:pure_music/core/hotkey_binding.dart';
import 'package:pure_music/core/hotkeys.dart';
import 'package:pure_music/core/settings.dart';
import 'package:pure_music/core/utils.dart';

class InAppHotkeysSettingsGroup extends StatefulWidget {
  const InAppHotkeysSettingsGroup({super.key});

  @override
  State<InAppHotkeysSettingsGroup> createState() =>
      _InAppHotkeysSettingsGroupState();
}

class _InAppHotkeysSettingsGroupState
    extends State<InAppHotkeysSettingsGroup> {
  final settings = AppSettings.instance;

  Future<bool> _save() async {
    final saved = await settings.saveSettings();
    if (!saved && mounted) {
      showTextOnSnackBar('快捷键设置保存失败', variant: ToastVariant.error);
    }
    return saved;
  }

  Future<void> _applyBinding(HotkeyAction action, HotkeyBinding binding) async {
    if (binding.isUnbound) return;
    final duplicate = settings.inAppHotkeys.entries.any(
      (entry) => entry.key != action && entry.value.conflictsWith(binding),
    );
    if (duplicate) {
      showTextOnSnackBar('该快捷键已分配给其他应用内操作', variant: ToastVariant.error);
      return;
    }

    final previous = Map<HotkeyAction, HotkeyBinding>.from(
      settings.inAppHotkeys,
    );
    setState(() {
      settings.inAppHotkeys = {...settings.inAppHotkeys, action: binding};
    });
    if (!await _save()) {
      if (mounted) setState(() => settings.inAppHotkeys = previous);
      return;
    }
    await HotkeysHelper.reload();
    if (mounted) setState(() {});
  }

  Future<void> _recordBinding(HotkeyAction action) async {
    await HotkeysHelper.pauseForRecording();
    if (!mounted) {
      await HotkeysHelper.resumeAfterRecording();
      return;
    }
    final current =
        settings.inAppHotkeys[action] ?? defaultInAppBinding(action);
    final recorded = await showDialog<HotkeyBinding>(
      context: context,
      builder: (context) => _InAppHotkeyRecorderDialog(
        title: action.title,
        initial: current,
      ),
    );
    await HotkeysHelper.resumeAfterRecording();
    if (recorded != null) {
      await _applyBinding(action, recorded);
    }
  }

  Future<void> _reset() async {
    final previous = Map<HotkeyAction, HotkeyBinding>.from(
      settings.inAppHotkeys,
    );
    setState(() => settings.inAppHotkeys = defaultInAppHotkeys());
    if (!await _save()) {
      if (mounted) setState(() => settings.inAppHotkeys = previous);
      return;
    }
    await HotkeysHelper.reload();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(right: 20, bottom: 96),
      children: [
        Text(
          '应用内快捷键仅在本窗口前台时生效，可按自己的习惯修改。',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        for (final action in inAppHotkeyActions) ...[
          SettingsTile(
            description: action.title,
            subtitle:
                (settings.inAppHotkeys[action] ?? defaultInAppBinding(action))
                    .label,
            action: OutlinedButton(
              onPressed: () => _recordBinding(action),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.smCircular,
                ),
              ),
              child: const Text('更改'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _reset, child: const Text('恢复默认')),
        ),
      ],
    );
  }
}

class _InAppHotkeyRecorderDialog extends StatefulWidget {
  const _InAppHotkeyRecorderDialog({
    required this.title,
    required this.initial,
  });

  final String title;
  final HotkeyBinding initial;

  @override
  State<_InAppHotkeyRecorderDialog> createState() =>
      _InAppHotkeyRecorderDialogState();
}

class _InAppHotkeyRecorderDialogState
    extends State<_InAppHotkeyRecorderDialog> {
  late HotkeyBinding _binding = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('设置「${widget.title}」'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _binding.label,
            style: const TextStyle(fontSize: AppType.subtitle),
          ),
          const SizedBox(height: 16),
          HotKeyRecorder(
            initalHotKey: widget.initial.toHotKey(
              scope: HotKeyScope.inapp,
              identifier: 'in_app_record',
            ),
            onHotKeyRecorded: (hotkey) {
              setState(() => _binding = HotkeyBinding.fromHotKey(hotkey));
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _binding.isUnbound
              ? null
              : () => Navigator.of(context).pop(_binding),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
