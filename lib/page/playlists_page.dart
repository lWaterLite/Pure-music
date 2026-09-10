import 'dart:async';

import 'package:pure_music/core/design_tokens.dart';
import 'package:pure_music/core/preference.dart';

import 'package:pure_music/component/danger_confirm_dialog.dart';
import 'package:pure_music/component/motion.dart';
import 'package:pure_music/core/list_action_state.dart';
import 'package:pure_music/core/settings.dart';
import 'package:pure_music/core/utils.dart';
import 'package:pure_music/core/hotkeys.dart';
import 'package:pure_music/page/uni_page.dart';
import 'package:pure_music/page/uni_page_components.dart';
import 'package:pure_music/library/playlist.dart';
import 'package:pure_music/library/audio_library.dart';
import 'package:pure_music/page/playlist_cover_picker.dart';
import 'package:pure_music/core/paths.dart' as app_paths;
import 'package:pure_music/native/folder_picker_windows.dart';
import 'package:pure_music/core/enums.dart';
import 'package:pure_music/core/menu_styles.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  final multiSelectController = MultiSelectController<Playlist>();
  final Set<Playlist> _deletingPlaylists = <Playlist>{};
  final Set<Playlist> _exportingPlaylists = <Playlist>{};
  bool _isImportingPlaylist = false;
  bool _isImportingFolder = false;
  bool _isDeletingSelected = false;
  bool _isCreatingPlaylist = false;
  bool _isCreatingPlaylistGroup = false;
  bool _isAssigningPlaylists = false;
  bool _isReorderingPlaylists = false;
  bool _isReorderingGroups = false;

  Future<void> newPlaylist(BuildContext context) async {
    if (_isCreatingPlaylist) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NewPlaylistDialog(
        existingNames: playlists.map((p) => p.name).toSet(),
      ),
    );
    if (name == null) return;
    if (!mounted) return;
    setState(() => _isCreatingPlaylist = true);
    try {
      final playlist = await createPlaylist(name);
      playlists.add(playlist);
      if (!mounted) return;
      setState(() {});
      showTextOnSnackBar('已创建歌单', variant: ToastVariant.success);
    } on PlaylistAlreadyExistsException {
      if (!mounted) return;
      showTextOnSnackBar('该名称已存在', variant: ToastVariant.error);
    } catch (err, trace) {
      logger.e('创建歌单失败', error: err, stackTrace: trace);
      if (!mounted) return;
      showTextOnSnackBar('保存歌单失败', variant: ToastVariant.error);
    } finally {
      if (mounted) {
        setState(() => _isCreatingPlaylist = false);
      }
    }
  }

  void editPlaylist(BuildContext context, Playlist playlist) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _EditPlaylistDialog(
        currentName: playlist.name,
        existingNames: playlists
            .map((p) => p.name)
            .where((n) => n != playlist.name)
            .toSet(),
      ),
    );
    if (name == null) return;
    if (!mounted) return;
    final oldName = playlist.name;
    setState(() {
      playlist.name = name;
    });
    final saved = await savePlaylists();
    if (!saved) {
      playlist.name = oldName;
      if (!mounted) return;
      setState(() {});
      showTextOnSnackBar('保存歌单失败', variant: ToastVariant.error);
    } else if (mounted) {
      showTextOnSnackBar('已重命名歌单', variant: ToastVariant.success);
    }
  }

  Future<void> importPlaylist() async {
    if (_isImportingPlaylist) return;
    setState(() => _isImportingPlaylist = true);
    try {
      final pl = await importPlaylistFromFile();
      if (pl == null) return;
      if (!mounted) return;
      if (hasEquivalentPlaylistName(
        existingNames: playlists.map((p) => p.name),
        targetName: pl.name,
      )) {
        showTextOnSnackBar('歌单已存在');
        return;
      }
      setState(() {
        pl.sortOrder = nextPlaylistSortOrder(null);
        playlists.add(pl);
      });
      final saved = await savePlaylists();
      if (!saved) {
        playlists.remove(pl);
        if (!mounted) return;
        setState(() {});
        showTextOnSnackBar('保存歌单失败', variant: ToastVariant.error);
        return;
      }
      if (!mounted) return;
      showTextOnSnackBar('已导入歌单', variant: ToastVariant.success);
    } catch (err) {
      if (!mounted) return;
      showTextOnSnackBar('导入歌单失败', variant: ToastVariant.error);
    } finally {
      if (mounted) {
        setState(() => _isImportingPlaylist = false);
      }
    }
  }

  Future<void> importFolderAsPlaylist() async {
    if (_isImportingFolder) return;
    setState(() => _isImportingFolder = true);
    try {
      final paths = pickMultipleDirectories(title: '选择歌单文件夹');
      if (paths.isEmpty) return;
      if (!mounted) return;

      final folderPath = paths.first;
      final dir = Directory(folderPath);
      if (!dir.existsSync()) {
        showTextOnSnackBar('文件夹不存在', variant: ToastVariant.error);
        return;
      }

      final audioFiles = <String>[];
      final audioExtensions = <String>{
        'mp3',
        'flac',
        'wav',
        'ogg',
        'ape',
        'm4a',
        'wma',
        'opus',
        'aiff',
        'aac',
      };

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final ext = p
              .extension(entity.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (audioExtensions.contains(ext)) {
            audioFiles.add(entity.path);
          }
        }
      }

      if (audioFiles.isEmpty) {
        showTextOnSnackBar('文件夹中没有找到音乐文件');
        return;
      }

      final resolved = <String>[];
      final collection = AudioLibrary.instance.audioCollection;
      for (final raw in audioFiles) {
        if (collection.any((a) => a.path == raw)) {
          resolved.add(raw);
          continue;
        }
        final matchedPath = findImportedPlaylistLibraryPath(
          rawPath: raw,
          libraryPaths: collection.map((a) => a.path),
        );
        if (matchedPath != null) resolved.add(matchedPath);
      }

      if (resolved.isEmpty) {
        showTextOnSnackBar('文件夹中的音乐不在曲库中');
        return;
      }

      final folderName = p.basename(folderPath);
      final pl = Playlist(folderName, resolved);
      if (hasEquivalentPlaylistName(
        existingNames: playlists.map((p) => p.name),
        targetName: pl.name,
      )) {
        showTextOnSnackBar('歌单已存在');
        return;
      }

      setState(() {
        pl.sortOrder = nextPlaylistSortOrder(null);
        playlists.add(pl);
      });
      final saved = await savePlaylists();
      if (!saved) {
        playlists.remove(pl);
        if (!mounted) return;
        setState(() {});
        showTextOnSnackBar('保存歌单失败', variant: ToastVariant.error);
        return;
      }
      if (!mounted) return;
      showTextOnSnackBar('已导入歌单', variant: ToastVariant.success);
    } catch (err) {
      if (!mounted) return;
      showTextOnSnackBar('导入文件夹歌单失败', variant: ToastVariant.error);
    } finally {
      if (mounted) {
        setState(() => _isImportingFolder = false);
      }
    }
  }

  bool _isExportingPlaylist(Playlist playlist) {
    return _exportingPlaylists.contains(playlist);
  }

  Future<void> _exportPlaylist(Playlist playlist) async {
    if (_isExportingPlaylist(playlist) || _isDeletingPlaylist(playlist)) return;
    setState(() => _exportingPlaylists.add(playlist));
    try {
      final exported = await exportPlaylistToFile(playlist);
      if (!mounted || !exported) return;
      showTextOnSnackBar('已导出歌单', variant: ToastVariant.success);
    } catch (err) {
      if (!mounted) return;
      showTextOnSnackBar('导出歌单失败', variant: ToastVariant.error);
    } finally {
      if (mounted) {
        setState(() => _exportingPlaylists.remove(playlist));
      }
    }
  }

  Future<bool> _confirmDeletePlaylist(Playlist playlist) {
    return _confirmDeletePlaylists([playlist]);
  }

  Future<bool> _confirmDeletePlaylists(List<Playlist> playlists) async {
    final count = playlists.length;
    final songCount = playlists.fold<int>(
      0,
      (total, playlist) => total + playlist.paths.length,
    );
    final title = count == 1 ? '删除歌单？' : '删除选中歌单？';
    final message = count == 1
        ? '将删除歌单“${playlists.first.name}”，不会删除本地音乐文件。'
        : '将删除 $count 个歌单，共涉及 $songCount 首歌曲，不会删除本地音乐文件。';

    return showDangerConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: '删除',
    );
  }

  bool _isDeletingPlaylist(Playlist playlist) {
    return _deletingPlaylists.contains(playlist);
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    if (_isDeletingPlaylist(playlist)) return;
    final confirmed = await _confirmDeletePlaylist(playlist);
    if (!confirmed || !mounted) return;

    setState(() {
      _deletingPlaylists.add(playlist);
      playlists.remove(playlist);
    });
    try {
      final saved = await savePlaylists();
      if (!saved) {
        playlists.add(playlist);
        if (!mounted) return;
        setState(() {});
        showTextOnSnackBar('删除歌单失败', variant: ToastVariant.error);
      } else if (mounted) {
        showTextOnSnackBar('已删除歌单', variant: ToastVariant.success);
      }
    } finally {
      if (mounted) {
        setState(() => _deletingPlaylists.remove(playlist));
      }
    }
  }

  Future<void> _deleteSelectedPlaylists() async {
    if (_isDeletingSelected || multiSelectController.selected.isEmpty) return;
    final selected = List<Playlist>.from(multiSelectController.selected);
    final indexed = selected
        .map((playlist) => MapEntry(playlists.indexOf(playlist), playlist))
        .where((entry) => entry.key >= 0)
        .toList();
    final confirmed = await _confirmDeletePlaylists(selected);
    if (!confirmed || !mounted) return;

    setState(() {
      _isDeletingSelected = true;
      _deletingPlaylists.addAll(selected);
      playlists.removeWhere(selected.contains);
    });
    try {
      final saved = await savePlaylists();
      if (!mounted) return;
      if (saved) {
        multiSelectController.useMultiSelectView(false);
        multiSelectController.clear();
        showTextOnSnackBar('已删除', variant: ToastVariant.success);
      } else {
        for (final entry in indexed.reversed) {
          final index = entry.key.clamp(0, playlists.length).toInt();
          playlists.insert(index, entry.value);
        }
        setState(() {});
        showTextOnSnackBar('删除歌单失败', variant: ToastVariant.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingSelected = false;
          _deletingPlaylists.removeAll(selected);
        });
      }
    }
  }

  bool get _isCustomPlaylistSort =>
      AppPreference.instance.playlistsPagePref.sortMethod == 2;

  bool get _isCustomGroupSort =>
      AppPreference.instance.playlistGroupsPagePref.sortMethod == 2;

  Future<void> _savePreference() async {
    final saved = await AppPreference.instance.save();
    if (!saved) logger.w('[Playlists] 保存分组页面偏好失败');
  }

  bool _isGroupCollapsed(PlaylistGroup? group) {
    if (group == null) return AppPreference.instance.playlistUngroupedCollapsed;
    final id = group.id;
    return id != null &&
        AppPreference.instance.collapsedPlaylistGroupIds.contains(id);
  }

  void _toggleGroupCollapsed(PlaylistGroup? group) {
    final pref = AppPreference.instance;
    setState(() {
      if (group == null) {
        pref.playlistUngroupedCollapsed = !pref.playlistUngroupedCollapsed;
      } else if (group.id case final id?) {
        if (!pref.collapsedPlaylistGroupIds.add(id)) {
          pref.collapsedPlaylistGroupIds.remove(id);
        }
      }
    });
    unawaited(_savePreference());
  }

  List<PlaylistGroup> _orderedGroups() {
    final result = List<PlaylistGroup>.from(playlistGroups);
    final pref = AppPreference.instance.playlistGroupsPagePref;
    final descending = pref.sortOrder == SortOrder.decending;
    switch (pref.sortMethod.clamp(0, 2)) {
      case 0:
        result.sort(
          (a, b) => descending
              ? b.name.naturalCompareTo(a.name)
              : a.name.naturalCompareTo(b.name),
        );
      case 1:
        int count(PlaylistGroup group) =>
            playlists.where((playlist) => playlist.groupId == group.id).length;
        result.sort(
          (a, b) => descending
              ? count(b).compareTo(count(a))
              : count(a).compareTo(count(b)),
        );
      case 2:
        result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return result;
  }

  List<PlaylistGroup?> _orderedGroupSections(List<Playlist> contentList) {
    final groups = _orderedGroups();
    final hasUngroupedPlaylists = contentList.any(
      (playlist) => playlist.groupId == null,
    );
    if (!hasUngroupedPlaylists) return List<PlaylistGroup?>.of(groups);
    if (!_isCustomGroupSort) return <PlaylistGroup?>[null, ...groups];

    final sections = <PlaylistGroup?>[null, ...groups];
    sections.sort((a, b) {
      final aOrder =
          a?.sortOrder ?? AppPreference.instance.playlistUngroupedSortOrder;
      final bOrder =
          b?.sortOrder ?? AppPreference.instance.playlistUngroupedSortOrder;
      final orderComparison = aOrder.compareTo(bOrder);
      if (orderComparison != 0) return orderComparison;
      if (a == null) return -1;
      if (b == null) return 1;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
    return sections;
  }

  Future<void> _createPlaylistGroup(BuildContext context) async {
    if (_isCreatingPlaylistGroup) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _PlaylistGroupNameDialog(
        title: '新建分组',
        label: '分组名称',
        existingNames: playlistGroups.map((group) => group.name).toSet(),
      ),
    );
    if (name == null || !mounted) return;
    logger.i('[Playlists] 创建分组 requested');
    setState(() => _isCreatingPlaylistGroup = true);
    try {
      final group = await createPlaylistGroup(name);
      playlistGroups.add(group);
      if (group.id case final id?) {
        AppPreference.instance.collapsedPlaylistGroupIds.remove(id);
      }
      if (!mounted) return;
      setState(() {});
      unawaited(_savePreference());
      logger.i('[Playlists] 创建分组 succeeded groupId=${group.id}');
      showTextOnSnackBar('已创建分组', variant: ToastVariant.success);
    } on PlaylistGroupAlreadyExistsException {
      if (!mounted) return;
      logger.w('[Playlists] 创建分组 rejected: duplicate');
      showTextOnSnackBar('该分组名称已存在', variant: ToastVariant.error);
    } catch (error, trace) {
      logger.e('[Playlists] 创建分组失败', error: error, stackTrace: trace);
      if (!mounted) return;
      showTextOnSnackBar('创建分组失败', variant: ToastVariant.error);
    } finally {
      if (mounted) setState(() => _isCreatingPlaylistGroup = false);
    }
  }

  Future<void> _renamePlaylistGroup(
    BuildContext context,
    PlaylistGroup group,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _PlaylistGroupNameDialog(
        title: '重命名分组',
        label: '分组名称',
        initialName: group.name,
        existingNames: playlistGroups
            .where((item) => !identical(item, group))
            .map((item) => item.name)
            .toSet(),
      ),
    );
    if (name == null || !mounted) return;
    final oldName = group.name;
    logger.i('[Playlists] 重命名分组 requested groupId=${group.id}');
    setState(() => group.name = name);
    final saved = await savePlaylists();
    if (saved) {
      logger.i('[Playlists] 重命名分组 succeeded groupId=${group.id}');
      if (mounted) showTextOnSnackBar('已重命名分组', variant: ToastVariant.success);
      return;
    }
    group.name = oldName;
    logger.w('[Playlists] 重命名分组 failed groupId=${group.id}');
    if (!mounted) return;
    setState(() {});
    showTextOnSnackBar('保存分组失败', variant: ToastVariant.error);
  }

  Future<void> _deletePlaylistGroup(PlaylistGroup group) async {
    final members = playlists
        .where((playlist) => playlist.groupId == group.id)
        .toList();
    final confirmed = await showDangerConfirmDialog(
      context: context,
      title: '删除分组？',
      message: members.isEmpty
          ? '将删除分组“${group.name}”。'
          : '将删除分组“${group.name}”，其中 ${members.length} 个歌单会移动到“未分组”。',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    final index = playlistGroups.indexOf(group);
    final oldValues = <Playlist, (int?, int)>{
      for (final playlist in members)
        playlist: (playlist.groupId, playlist.sortOrder),
    };
    logger.i(
      '[Playlists] 删除分组 requested groupId=${group.id} playlists=${members.length}',
    );
    var nextOrder = nextPlaylistSortOrder(null);
    setState(() {
      playlistGroups.remove(group);
      for (final playlist in members) {
        playlist
          ..groupId = null
          ..sortOrder = nextOrder++;
      }
    });
    final saved = await savePlaylists();
    if (saved) {
      if (group.id case final id?) {
        AppPreference.instance.collapsedPlaylistGroupIds.remove(id);
        unawaited(_savePreference());
      }
      logger.i('[Playlists] 删除分组 succeeded groupId=${group.id}');
      if (mounted) showTextOnSnackBar('已删除分组', variant: ToastVariant.success);
      return;
    }
    playlistGroups.insert(index, group);
    for (final entry in oldValues.entries) {
      entry.key
        ..groupId = entry.value.$1
        ..sortOrder = entry.value.$2;
    }
    logger.w('[Playlists] 删除分组 failed groupId=${group.id}');
    if (!mounted) return;
    setState(() {});
    showTextOnSnackBar('删除分组失败', variant: ToastVariant.error);
  }

  Future<void> _assignPlaylistsToGroup(
    Iterable<Playlist> items,
    PlaylistGroup? group, {
    bool exitMultiSelect = false,
  }) async {
    if (_isAssigningPlaylists) return;
    final selected = items.toSet().toList();
    if (selected.isEmpty) return;
    if (selected.every((playlist) => playlist.groupId == group?.id)) return;
    final oldValues = <Playlist, (int?, int)>{
      for (final playlist in selected)
        playlist: (playlist.groupId, playlist.sortOrder),
    };
    logger.i(
      '[Playlists] 分组歌单 requested count=${selected.length} target=${group?.id ?? 'ungrouped'}',
    );
    var nextOrder = nextPlaylistSortOrder(group?.id);
    setState(() {
      _isAssigningPlaylists = true;
      for (final playlist in selected) {
        playlist
          ..groupId = group?.id
          ..sortOrder = nextOrder++;
      }
    });
    final saved = await savePlaylists();
    if (saved) {
      logger.i(
        '[Playlists] 分组歌单 succeeded count=${selected.length} target=${group?.id ?? 'ungrouped'}',
      );
      if (exitMultiSelect) {
        multiSelectController
          ..useMultiSelectView(false)
          ..clear();
      }
      if (mounted) showTextOnSnackBar('已更新歌单分组', variant: ToastVariant.success);
    } else {
      for (final entry in oldValues.entries) {
        entry.key
          ..groupId = entry.value.$1
          ..sortOrder = entry.value.$2;
      }
      logger.w('[Playlists] 分组歌单 failed count=${selected.length}');
      if (mounted) {
        setState(() {});
        showTextOnSnackBar('保存歌单分组失败', variant: ToastVariant.error);
      }
    }
    if (mounted) setState(() => _isAssigningPlaylists = false);
  }

  void _setGroupSortMethod(int method) {
    setState(() {
      AppPreference.instance.playlistGroupsPagePref.sortMethod = method;
      _isReorderingGroups = false;
      _isReorderingPlaylists = false;
    });
    unawaited(_savePreference());
  }

  void _setGroupSortOrder(SortOrder order) {
    setState(
      () => AppPreference.instance.playlistGroupsPagePref.sortOrder = order,
    );
    unawaited(_savePreference());
  }

  Future<void> _reorderGroups(
    List<PlaylistGroup?> sections,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex == oldIndex) return;
    final oldOrders = <PlaylistGroup, int>{
      for (final group in sections.whereType<PlaylistGroup>())
        group: group.sortOrder,
    };
    final oldUngroupedSortOrder =
        AppPreference.instance.playlistUngroupedSortOrder;
    final reordered = List<PlaylistGroup?>.of(sections);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() {
      for (var i = 0; i < reordered.length; i++) {
        final group = reordered[i];
        if (group == null) {
          AppPreference.instance.playlistUngroupedSortOrder = i;
        } else {
          group.sortOrder = i;
        }
      }
    });
    final saved = await savePlaylists();
    if (saved) {
      unawaited(_savePreference());
      logger.i('[Playlists] 自定义分组排序 succeeded count=${reordered.length}');
      return;
    }
    for (final entry in oldOrders.entries) {
      entry.key.sortOrder = entry.value;
    }
    AppPreference.instance.playlistUngroupedSortOrder = oldUngroupedSortOrder;
    logger.w('[Playlists] 自定义分组排序 failed');
    if (!mounted) return;
    setState(() {});
    showTextOnSnackBar('保存分组排序失败', variant: ToastVariant.error);
  }

  Future<void> _reorderPlaylists(
    List<Playlist> groupPlaylists,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex == oldIndex) return;
    final oldOrders = <Playlist, int>{
      for (final playlist in groupPlaylists) playlist: playlist.sortOrder,
    };
    final reordered = List<Playlist>.from(groupPlaylists);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() {
      for (var i = 0; i < reordered.length; i++) {
        reordered[i].sortOrder = i;
      }
    });
    final saved = await savePlaylists();
    if (saved) {
      logger.i('[Playlists] 自定义歌单排序 succeeded count=${reordered.length}');
      return;
    }
    for (final entry in oldOrders.entries) {
      entry.key.sortOrder = entry.value;
    }
    logger.w('[Playlists] 自定义歌单排序 failed');
    if (!mounted) return;
    setState(() {});
    showTextOnSnackBar('保存歌单排序失败', variant: ToastVariant.error);
  }

  Widget _buildCustomReorderAction({
    required bool isReordering,
    required bool isDisabled,
    required VoidCallback onPressed,
    required String idleLabel,
    required String completeLabel,
    required ColorScheme colorScheme,
  }) {
    return FilledButton.tonalIcon(
      onPressed: isDisabled ? null : onPressed,
      icon: Icon(isReordering ? Symbols.check : Symbols.reorder, size: 20),
      label: Text(isReordering ? completeLabel : idleLabel),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.smCircular),
        ),
        backgroundColor: WidgetStatePropertyAll(
          isReordering
              ? colorScheme.tertiaryContainer
              : colorScheme.secondaryContainer,
        ),
        foregroundColor: WidgetStatePropertyAll(
          isReordering
              ? colorScheme.onTertiaryContainer
              : colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  Widget _buildNewGroupAction(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _isCreatingPlaylistGroup
          ? null
          : () => _createPlaylistGroup(context),
      icon: _isCreatingPlaylistGroup
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Symbols.add, size: 20),
      label: Text(_isCreatingPlaylistGroup ? '创建中' : '新建分组'),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.smCircular),
        ),
      ),
    );
  }

  Widget _buildGroupSortAction() {
    final sortMethods = <SortMethodDesc<PlaylistGroup>>[
      SortMethodDesc(icon: Symbols.title, name: '名称', method: (_, _) {}),
      SortMethodDesc(icon: Symbols.music_note, name: '歌单数量', method: (_, _) {}),
      SortMethodDesc(
        icon: Symbols.drag_indicator,
        name: '自定义',
        method: (_, _) {},
      ),
    ];
    final pref = AppPreference.instance.playlistGroupsPagePref;
    final method = pref.sortMethod.clamp(0, sortMethods.length - 1).toInt();
    return SortMethodComboBox<PlaylistGroup>(
      sortMethods: sortMethods,
      contentList: playlistGroups,
      currSortMethod: sortMethods[method],
      setSortMethod: (sortMethod) =>
          _setGroupSortMethod(sortMethods.indexOf(sortMethod)),
    );
  }

  Widget _buildGroupSortOrderAction() {
    final pref = AppPreference.instance.playlistGroupsPagePref;
    return SortOrderSwitch<PlaylistGroup>(
      sortOrder: pref.sortOrder,
      setSortOrder: _setGroupSortOrder,
    );
  }

  Widget _buildScrollableGroupMenu({
    required int? currentGroupId,
    required void Function(PlaylistGroup? group) onSelected,
    bool disableCurrent = true,
    bool markCurrent = true,
  }) {
    final items = <Widget>[
      MenuItemButton(
        style: appMenuItemStyle,
        leadingIcon: Icon(
          markCurrent && currentGroupId == null
              ? Symbols.check
              : Symbols.folder_off,
        ),
        onPressed: disableCurrent && currentGroupId == null
            ? null
            : () => onSelected(null),
        child: const Text(ungroupedPlaylistGroupName),
      ),
      ..._orderedGroups().map(
        (group) => MenuItemButton(
          style: appMenuItemStyle,
          leadingIcon: Icon(
            markCurrent && currentGroupId == group.id
                ? Symbols.check
                : Symbols.folder,
          ),
          onPressed: disableCurrent && currentGroupId == group.id
              ? null
              : () => onSelected(group),
          child: Text(group.name, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    return SizedBox(
      width: 260,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Scrollbar(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: items),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistGroupSubmenu(Playlist playlist) {
    return SubmenuButton(
      style: appMenuItemStyle,
      leadingIcon: const Icon(Symbols.folder),
      menuChildren: [
        _buildScrollableGroupMenu(
          currentGroupId: playlist.groupId,
          onSelected: (group) => _assignPlaylistsToGroup([playlist], group),
        ),
      ],
      child: const Text('分组'),
    );
  }

  Widget _buildMultiSelectGroupAction() {
    return ListenableBuilder(
      listenable: multiSelectController,
      builder: (context, _) => MenuAnchor(
        style: appMenuStyle,
        menuChildren: [
          _buildScrollableGroupMenu(
            currentGroupId: null,
            disableCurrent: false,
            markCurrent: false,
            onSelected: (group) => _assignPlaylistsToGroup(
              multiSelectController.selected,
              group,
              exitMultiSelect: true,
            ),
          ),
        ],
        builder: (context, controller, _) => IconButton.filled(
          tooltip: '为选中歌单分组',
          iconSize: 20,
          onPressed:
              multiSelectController.selected.isEmpty || _isAssigningPlaylists
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          style: IconButton.styleFrom(
            fixedSize: const Size(40, 40),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.smCircular),
          ),
          icon: _isAssigningPlaylists
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Symbols.folder),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    PlaylistGroup? group,
    int count, {
    required bool allowToggle,
    bool showDragHandle = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = _isGroupCollapsed(group);
    final isUngrouped = group == null;
    return MenuTheme(
      data: MenuThemeData(style: appMenuStyle),
      child: MenuAnchor(
        consumeOutsideTap: true,
        style: appMenuStyle,
        menuChildren: isUngrouped
            ? const <Widget>[]
            : [
                MenuItemButton(
                  style: appMenuItemStyle,
                  leadingIcon: const Icon(Symbols.edit),
                  onPressed: () => _renamePlaylistGroup(context, group),
                  child: const Text('重命名'),
                ),
                MenuItemButton(
                  style: appMenuItemStyle,
                  leadingIcon: Icon(Symbols.delete, color: scheme.error),
                  onPressed: () => _deletePlaylistGroup(group),
                  child: const Text('删除'),
                ),
              ],
        builder: (context, controller, _) => Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.smCircular,
            onTap: allowToggle ? () => _toggleGroupCollapsed(group) : null,
            onSecondaryTapDown: isUngrouped
                ? null
                : (details) => controller.open(
                    position: details.localPosition.translate(0, -96),
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  showDragHandle
                      ? Icon(
                          Symbols.drag_indicator,
                          color: scheme.onSurfaceVariant,
                        )
                      : AnimatedRotation(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : MotionDuration.fast,
                          curve: MotionCurve.standard,
                          turns: collapsed ? -0.25 : 0,
                          child: Icon(
                            Symbols.expand_more,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                  const SizedBox(width: 8),
                  Icon(
                    isUngrouped ? Symbols.folder_off : Symbols.folder,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group?.name ?? ungroupedPlaylistGroupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: AppType.subtitle,
                        fontWeight: AppType.weightSemibold,
                      ),
                    ),
                  ),
                  Text(
                    '$count 个歌单',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedGroupContent(
    BuildContext context,
    PlaylistGroup? group,
    List<Playlist> groupPlaylists,
    Map<Playlist, int> playlistIndexes,
    ContentView view,
    MultiSelectController<Playlist>? controller, {
    required bool collapsed,
  }) {
    final content = collapsed
        ? const SizedBox.shrink()
        : switch (view) {
            ContentView.list => Column(
              children: [
                for (final playlist in groupPlaylists)
                  SizedBox(
                    height: 64,
                    child: _buildGroupedPlaylistTile(
                      context,
                      playlist,
                      playlistIndexes[playlist]!,
                      controller,
                      ContentView.list,
                    ),
                  ),
              ],
            ),
            ContentView.table => Padding(
              padding: const EdgeInsets.only(right: 20),
              child: GridView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: gridDelegate,
                itemCount: groupPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = groupPlaylists[index];
                  return _buildGroupedPlaylistTile(
                    context,
                    playlist,
                    playlistIndexes[playlist]!,
                    controller,
                    ContentView.table,
                  );
                },
              ),
            ),
          };
    return SliverToBoxAdapter(
      key: ValueKey('playlist-group-content-${group?.id ?? 'ungrouped'}'),
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : MotionDuration.base,
        curve: MotionCurve.standard,
        alignment: Alignment.topCenter,
        child: content,
      ),
    );
  }

  Widget _buildGroupedContent(
    BuildContext context,
    List<Playlist> contentList,
    ContentView view,
    MultiSelectController<Playlist>? controller,
    ScrollController scrollController,
  ) {
    final sections = _orderedGroupSections(contentList);
    final playlistIndexes = <Playlist, int>{
      for (var i = 0; i < contentList.length; i++) contentList[i]: i,
    };
    if (_isReorderingGroups) {
      return _buildGroupReorderContent(
        context,
        sections,
        contentList,
        scrollController,
      );
    }
    final slivers = <Widget>[];
    for (final group in sections) {
      final groupPlaylists = contentList
          .where((playlist) => playlist.groupId == group?.id)
          .toList();
      final collapsed = _isGroupCollapsed(group);
      slivers.add(
        SliverToBoxAdapter(
          child: _buildGroupHeader(
            context,
            group,
            groupPlaylists.length,
            allowToggle: !_isReorderingPlaylists,
          ),
        ),
      );
      if (groupPlaylists.isEmpty) continue;
      if (_isReorderingPlaylists) {
        slivers.add(
          SliverReorderableList(
            itemCount: groupPlaylists.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorderPlaylists(groupPlaylists, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final playlist = groupPlaylists[index];
              return SizedBox(
                key: ValueKey('playlist-${playlist.id ?? playlist.name}'),
                height: 64,
                child: _buildGroupedPlaylistTile(
                  context,
                  playlist,
                  playlistIndexes[playlist]!,
                  controller,
                  ContentView.list,
                  reorderIndex: index,
                ),
              );
            },
          ),
        );
      } else {
        slivers.add(
          _buildAnimatedGroupContent(
            context,
            group,
            groupPlaylists,
            playlistIndexes,
            view,
            controller,
            collapsed: collapsed,
          ),
        );
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));
    return CustomScrollView(controller: scrollController, slivers: slivers);
  }

  Widget _buildGroupReorderContent(
    BuildContext context,
    List<PlaylistGroup?> sections,
    List<Playlist> contentList,
    ScrollController scrollController,
  ) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverReorderableList(
          itemCount: sections.length,
          onReorderItem: (oldIndex, newIndex) =>
              _reorderGroups(sections, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final group = sections[index];
            final count = contentList
                .where((playlist) => playlist.groupId == group?.id)
                .length;
            return ReorderableDragStartListener(
              key: ValueKey(
                group == null
                    ? 'playlist-group-ungrouped'
                    : 'playlist-group-${group.id ?? group.name}',
              ),
              index: index,
              child: _buildGroupHeader(
                context,
                group,
                count,
                allowToggle: false,
                showDragHandle: true,
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _buildGroupedPlaylistTile(
    BuildContext context,
    Playlist playlist,
    int index,
    MultiSelectController<Playlist>? controller,
    ContentView view, {
    int? reorderIndex,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = controller?.selected.contains(playlist) == true;
    final multiSelect = controller?.enableMultiSelectView == true;
    final deleting = _isDeletingPlaylist(playlist);
    final exporting = _isExportingPlaylist(playlist);
    final busy = deleting || exporting || _isAssigningPlaylists;
    return MenuTheme(
      key: ValueKey('playlist-tile-${playlist.id ?? playlist.name}-$index'),
      data: MenuThemeData(style: appMenuStyle),
      child: MenuAnchor(
        consumeOutsideTap: true,
        style: appMenuStyle,
        menuChildren: [
          MenuItemButton(
            style: appMenuItemStyle,
            onPressed: busy
                ? null
                : () => context.push(
                    app_paths.PLAYLIST_DETAIL_PAGE,
                    extra: playlist,
                  ),
            leadingIcon: const Icon(Symbols.open_in_new),
            child: const Text('打开'),
          ),
          _buildPlaylistGroupSubmenu(playlist),
          MenuItemButton(
            style: appMenuItemStyle,
            onPressed: busy ? null : () => editPlaylist(context, playlist),
            leadingIcon: const Icon(Symbols.edit),
            child: const Text('编辑'),
          ),
          MenuItemButton(
            style: appMenuItemStyle,
            onPressed: busy
                ? null
                : () async {
                    await showCoverPicker(context, playlist);
                    if (mounted) setState(() {});
                  },
            leadingIcon: const Icon(Symbols.brush),
            child: const Text('更换封面'),
          ),
          MenuItemButton(
            style: appMenuItemStyle,
            onPressed: busy ? null : () => _exportPlaylist(playlist),
            leadingIcon: exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.file_export),
            child: Text(exporting ? '导出中' : '导出'),
          ),
          MenuItemButton(
            style: appMenuItemStyle,
            onPressed: busy ? null : () => _deletePlaylist(playlist),
            leadingIcon: deleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Symbols.delete, color: scheme.error),
            child: Text(deleting ? '删除中' : '删除'),
          ),
          if (controller != null)
            MenuItemButton(
              style: appMenuItemStyle,
              onPressed: busy
                  ? null
                  : () {
                      controller.useMultiSelectView(true);
                      controller.select(playlist);
                    },
              leadingIcon: const Icon(Symbols.select),
              child: const Text('多选'),
            ),
        ],
        builder: (context, menuController, _) => InteractiveSurfaceMotion(
          enabled:
              view == ContentView.table &&
              AppSettings.instance.enableInteractiveSurfaceMotion,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: AppRadius.smCircular,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: AppRadius.smCircular,
                onTap: busy
                    ? null
                    : () {
                        if (menuController.isOpen) {
                          menuController.close();
                          return;
                        }
                        if (!multiSelect) {
                          context.push(
                            app_paths.PLAYLIST_DETAIL_PAGE,
                            extra: playlist,
                          );
                          return;
                        }
                        if (selected) {
                          controller?.unselect(playlist);
                        } else {
                          controller?.select(playlist);
                        }
                      },
                onLongPress: busy || multiSelect
                    ? null
                    : () {
                        if (controller == null) return;
                        controller
                          ..useMultiSelectView(true)
                          ..select(playlist);
                      },
                onSecondaryTapDown: (details) {
                  if (busy || multiSelect) return;
                  menuController.open(
                    position: details.localPosition.translate(0, -240),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      if (reorderIndex case final index?)
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Symbols.drag_indicator,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        _PlaylistCover(playlist: playlist),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppType.subtitle,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${playlist.paths.length}首乐曲',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurface.withAlpha(153),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (multiSelect)
                        Checkbox(
                          value: selected,
                          onChanged: busy
                              ? null
                              : (value) => value == true
                                    ? controller?.select(playlist)
                                    : controller?.unselect(playlist),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final menuStyle = appMenuStyle;
    final menuItemStyle = appMenuItemStyle;
    final canSortPlaylists = hasEnoughItemsToSort(playlists.length);
    final canSwitchContentView = canShowContentViewSwitch(playlists.length);

    return UniPage<Playlist>(
      pref: AppPreference.instance.playlistsPagePref,
      title: '歌单',
      subtitle: '${playlists.length} 个歌单',
      contentList: playlists,
      contentBuilder: (context, item, i, multiSelectController, view) {
        final playlist = playlists[i];
        final isSelected =
            multiSelectController?.selected.contains(playlist) == true;
        final isMultiSelectView =
            multiSelectController?.enableMultiSelectView == true;
        final isDeleting = _isDeletingPlaylist(playlist);
        final isExporting = _isExportingPlaylist(playlist);
        final isBusy = isDeleting || isExporting;
        return MenuTheme(
          data: MenuThemeData(style: menuStyle),
          child: MenuAnchor(
            consumeOutsideTap: true,
            style: menuStyle,
            menuChildren: [
              MenuItemButton(
                style: menuItemStyle,
                onPressed: isBusy
                    ? null
                    : () => context.push(
                        app_paths.PLAYLIST_DETAIL_PAGE,
                        extra: playlist,
                      ),
                leadingIcon: const Icon(Symbols.open_in_new),
                child: const Text('打开'),
              ),
              _buildPlaylistGroupSubmenu(playlist),
              MenuItemButton(
                style: menuItemStyle,
                onPressed: isBusy
                    ? null
                    : () => editPlaylist(context, playlist),
                leadingIcon: const Icon(Symbols.edit),
                child: const Text('编辑'),
              ),
              MenuItemButton(
                style: menuItemStyle,
                onPressed: isBusy
                    ? null
                    : () async {
                        await showCoverPicker(context, playlist);
                        if (mounted) setState(() {});
                      },
                leadingIcon: const Icon(Symbols.brush),
                child: const Text('更换封面'),
              ),
              MenuItemButton(
                style: menuItemStyle,
                onPressed: isBusy ? null : () => _deletePlaylist(playlist),
                leadingIcon: isDeleting
                    ? const SizedBox(
                        width: 18.0,
                        height: 18.0,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      )
                    : Icon(Symbols.delete, color: scheme.error),
                child: Text(isDeleting ? '删除中' : '删除'),
              ),
              MenuItemButton(
                style: menuItemStyle,
                onPressed: isBusy ? null : () => _exportPlaylist(playlist),
                leadingIcon: isExporting
                    ? const SizedBox(
                        width: 18.0,
                        height: 18.0,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      )
                    : const Icon(Symbols.file_export),
                child: Text(isExporting ? '导出中' : '导出'),
              ),
              if (multiSelectController != null)
                MenuItemButton(
                  style: menuItemStyle,
                  onPressed: isBusy
                      ? null
                      : () {
                          multiSelectController.useMultiSelectView(true);
                          multiSelectController.select(playlist);
                        },
                  leadingIcon: const Icon(Symbols.select),
                  child: const Text('多选'),
                ),
            ],
            builder: (context, controller, _) => InteractiveSurfaceMotion(
              enabled:
                  view == ContentView.table &&
                  AppSettings.instance.enableInteractiveSurfaceMotion,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: AppRadius.smCircular,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: AppRadius.smCircular,
                    onTap: isBusy
                        ? null
                        : () {
                            if (controller.isOpen) {
                              controller.close();
                              return;
                            }
                            if (!isMultiSelectView) {
                              context.push(
                                app_paths.PLAYLIST_DETAIL_PAGE,
                                extra: playlist,
                              );
                              return;
                            }
                            if (isSelected) {
                              multiSelectController?.unselect(playlist);
                            } else {
                              multiSelectController?.select(playlist);
                            }
                          },
                    onLongPress: isBusy
                        ? null
                        : () {
                            if (multiSelectController == null) return;
                            if (isMultiSelectView) return;
                            multiSelectController.useMultiSelectView(true);
                            multiSelectController.select(playlist);
                          },
                    onSecondaryTapDown: (details) {
                      if (isBusy || isMultiSelectView) return;
                      controller.open(
                        position: details.localPosition.translate(0, -240),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          _PlaylistCover(playlist: playlist),
                          const SizedBox(width: 16.0),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist.name,
                                  softWrap: false,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: AppType.subtitle,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  '${playlist.paths.length}首乐曲',
                                  softWrap: false,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: scheme.onSurface.withAlpha(153),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isMultiSelectView)
                            Checkbox(
                              value: isSelected,
                              onChanged: isBusy
                                  ? null
                                  : (v) {
                                      if (v == true) {
                                        multiSelectController?.select(playlist);
                                      } else {
                                        multiSelectController?.unselect(
                                          playlist,
                                        );
                                      }
                                    },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      primaryAction: MenuAnchor(
        style: appMenuStyle,
        menuChildren: [
          MenuItemButton(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(12)),
            ),
            leadingIcon: _isCreatingPlaylist
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Symbols.add),
            onPressed: _isCreatingPlaylist ? null : () => newPlaylist(context),
            child: Text(_isCreatingPlaylist ? '创建中' : '新建歌单'),
          ),
          MenuItemButton(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(12)),
            ),
            leadingIcon: _isImportingFolder
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Symbols.folder_open),
            onPressed: _isImportingFolder
                ? null
                : () => importFolderAsPlaylist(),
            child: Text(_isImportingFolder ? '导入中' : '导入文件夹歌单'),
          ),
          MenuItemButton(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(12)),
            ),
            leadingIcon: _isImportingPlaylist
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Symbols.file_open),
            onPressed: _isImportingPlaylist ? null : () => importPlaylist(),
            child: Text(_isImportingPlaylist ? '导入中' : '导入歌单列表'),
          ),
        ],
        builder: (context, menuController, _) {
          return FilledButton.tonal(
            onPressed: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
            style: ButtonStyle(
              fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: AppRadius.smCircular),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Symbols.queue_music, size: 20),
                const SizedBox(width: 4.0),
                const Text('管理歌单'),
                const SizedBox(width: 4.0),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: menuController.isOpen ? 0.5 : 0.0,
                  child: const Icon(Symbols.arrow_drop_down, size: 20),
                ),
              ],
            ),
          );
        },
      ),
      extraActions: [
        _buildNewGroupAction(context),
        _buildGroupSortAction(),
        _buildGroupSortOrderAction(),
        if (_isCustomGroupSort)
          _buildCustomReorderAction(
            isReordering: _isReorderingGroups,
            isDisabled: _isReorderingPlaylists,
            onPressed: () =>
                setState(() => _isReorderingGroups = !_isReorderingGroups),
            idleLabel: '排序分组',
            completeLabel: '完成分组排序',
            colorScheme: scheme,
          ),
      ],
      trailingActions: [
        if (_isCustomPlaylistSort)
          _buildCustomReorderAction(
            isReordering: _isReorderingPlaylists,
            isDisabled: _isReorderingGroups,
            onPressed: () => setState(
              () => _isReorderingPlaylists = !_isReorderingPlaylists,
            ),
            idleLabel: '排序歌单',
            completeLabel: '完成歌单排序',
            colorScheme: scheme,
          ),
      ],
      actionRowsBuilder: (groupActions, playlistActions) => [
        groupActions,
        playlistActions,
      ],
      enableShufflePlay: false,
      enableSortMethod: canSortPlaylists,
      enableSortOrder: canSortPlaylists,
      enableContentViewSwitch: canSwitchContentView,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        _buildMultiSelectGroupAction(),
        ListenableBuilder(
          listenable: multiSelectController,
          builder: (context, _) => IconButton.filled(
            tooltip: '删除选中歌单',
            iconSize: 20,
            onPressed:
                multiSelectController.selected.isEmpty || _isDeletingSelected
                ? null
                : _deleteSelectedPlaylists,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              padding: EdgeInsets.zero,
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.smCircular),
            ),
            icon: _isDeletingSelected
                ? const SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Symbols.delete),
          ),
        ),
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: playlists,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: '名称',
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.name.naturalCompareTo(b.name));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.name.naturalCompareTo(a.name));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.music_note,
          name: '歌曲数量',
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.paths.length.compareTo(b.paths.length));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.paths.length.compareTo(a.paths.length));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.drag_indicator,
          name: '自定义',
          method: (list, order) {
            list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          },
        ),
      ],
      contentAreaBuilder: _buildGroupedContent,
      onSortMethodChanged: () {
        if (_isReorderingPlaylists) {
          setState(() => _isReorderingPlaylists = false);
        }
      },
    );
  }
}

class _PlaylistGroupNameDialog extends StatefulWidget {
  const _PlaylistGroupNameDialog({
    required this.title,
    required this.label,
    required this.existingNames,
    this.initialName,
  });

  final String title;
  final String label;
  final Set<String> existingNames;
  final String? initialName;

  @override
  State<_PlaylistGroupNameDialog> createState() =>
      _PlaylistGroupNameDialogState();
}

class _PlaylistGroupNameDialogState extends State<_PlaylistGroupNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _errorText;

  String get _name => _controller.text.trim();

  bool get _canSubmit =>
      _name.isNotEmpty &&
      _name != widget.initialName &&
      _name != ungroupedPlaylistGroupName &&
      !hasEquivalentPlaylistName(
        existingNames: widget.existingNames,
        targetName: _name,
      );

  void _submit() {
    if (_name.isEmpty) {
      setState(() => _errorText = '请输入分组名称');
      return;
    }
    if (_name == ungroupedPlaylistGroupName) {
      setState(() => _errorText = '“未分组”是保留名称');
      return;
    }
    if (hasEquivalentPlaylistName(
      existingNames: widget.existingNames,
      targetName: _name,
    )) {
      setState(() => _errorText = '该分组名称已存在');
      return;
    }
    if (_name == widget.initialName) return;
    Navigator.pop(context, _name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Focus(
        onFocusChange: HotkeysHelper.onFocusChanges,
        child: TextField(
          autofocus: true,
          controller: _controller,
          onChanged: (_) => setState(() => _errorText = null),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            errorText: _errorText,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.initialName == null ? '创建' : '确认'),
        ),
      ],
    );
  }
}

class _NewPlaylistDialog extends StatefulWidget {
  final Set<String> existingNames;
  const _NewPlaylistDialog({required this.existingNames});

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  late final _editingController = TextEditingController();
  String? _errorText;

  String get _trimmedName => _editingController.text.trim();

  bool get _canSubmit {
    final name = _trimmedName;
    return name.isNotEmpty &&
        !hasEquivalentPlaylistName(
          existingNames: widget.existingNames,
          targetName: name,
        );
  }

  void _onNameChanged(String value) {
    final name = value.trim();
    setState(() {
      _errorText =
          name.isNotEmpty &&
              hasEquivalentPlaylistName(
                existingNames: widget.existingNames,
                targetName: name,
              )
          ? '该名称已存在'
          : null;
    });
  }

  void _submit() {
    final name = _trimmedName;
    if (name.isEmpty) {
      setState(() => _errorText = '请输入歌单名称');
      return;
    }
    if (hasEquivalentPlaylistName(
      existingNames: widget.existingNames,
      targetName: name,
    )) {
      setState(() => _errorText = '该名称已存在');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.sizeOf(context).width - 48.0)
        .clamp(280.0, 360.0)
        .toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 24.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdCircular),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  '新建歌单',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: AppType.sectionTitle,
                    fontWeight: AppType.weightBold,
                  ),
                ),
              ),
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  autofocus: true,
                  controller: _editingController,
                  onChanged: _onNameChanged,
                  onSubmitted: (value) => _submit(),
                  decoration: InputDecoration(
                    labelText: '歌单名称',
                    border: const OutlineInputBorder(),
                    errorText: _errorText,
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8.0,
                overflowSpacing: 8.0,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text('创建'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPlaylistDialog extends StatefulWidget {
  final String currentName;
  final Set<String> existingNames;
  const _EditPlaylistDialog({
    required this.currentName,
    required this.existingNames,
  });

  @override
  State<_EditPlaylistDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<_EditPlaylistDialog> {
  late final _editingController = TextEditingController(
    text: widget.currentName,
  );
  String? _errorText;

  String get _trimmedName => _editingController.text.trim();

  bool get _canSubmit {
    final name = _trimmedName;
    return name.isNotEmpty &&
        name != widget.currentName &&
        !hasEquivalentPlaylistName(
          existingNames: widget.existingNames,
          targetName: name,
        );
  }

  void _onNameChanged(String value) {
    final name = value.trim();
    setState(() {
      _errorText =
          name.isNotEmpty &&
              hasEquivalentPlaylistName(
                existingNames: widget.existingNames,
                targetName: name,
              )
          ? '该名称已存在'
          : null;
    });
  }

  void _submit() {
    final name = _trimmedName;
    if (name.isEmpty) {
      setState(() => _errorText = '请输入歌单名称');
      return;
    }
    if (hasEquivalentPlaylistName(
      existingNames: widget.existingNames,
      targetName: name,
    )) {
      setState(() => _errorText = '该名称已存在');
      return;
    }
    if (name == widget.currentName) return;
    Navigator.pop(context, name);
  }

  @override
  void dispose() {
    _editingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = (MediaQuery.sizeOf(context).width - 48.0)
        .clamp(280.0, 360.0)
        .toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 24.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdCircular),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  '修改歌单',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: AppType.sectionTitle,
                    fontWeight: AppType.weightBold,
                  ),
                ),
              ),
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  autofocus: true,
                  controller: _editingController,
                  onChanged: _onNameChanged,
                  onSubmitted: (value) => _submit(),
                  decoration: InputDecoration(
                    labelText: '新歌单名称',
                    border: const OutlineInputBorder(),
                    errorText: _errorText,
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8.0,
                overflowSpacing: 8.0,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text('确认'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCover extends StatefulWidget {
  final Playlist playlist;
  const _PlaylistCover({required this.playlist});

  @override
  State<_PlaylistCover> createState() => _PlaylistCoverState();
}

class _PlaylistCoverState extends State<_PlaylistCover> {
  ImageProvider? _cached;
  bool _isHovered = false;
  bool _isPickingCover = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PlaylistCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist != widget.playlist ||
        oldWidget.playlist.coverSource != widget.playlist.coverSource) {
      _cached = null;
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final custom = await widget.playlist.resolveCoverProvider(size: 48);
    if (!mounted || token != _loadToken) return;
    if (custom != null) {
      setState(() => _cached = custom);
      return;
    }
    final firstAudio = widget.playlist.firstAudio;
    if (firstAudio == null) return;
    final bytes =
        firstAudio.smallCoverBytes ?? await firstAudio.loadSmallCoverBytes();
    if (!mounted || token != _loadToken) return;
    if (bytes != null) {
      setState(() => _cached = MemoryImage(bytes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overlayColor = scheme.onSurface.withValues(alpha: 0.25);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _isPickingCover
            ? null
            : () async {
                setState(() => _isPickingCover = true);
                try {
                  await showCoverPicker(context, widget.playlist);
                  _load();
                } finally {
                  if (mounted) {
                    setState(() => _isPickingCover = false);
                  }
                }
              },
        child: Stack(
          children: [
            _cached != null
                ? ClipRRect(
                    borderRadius: AppRadius.smCircular,
                    child: RepaintBoundary(
                      child: Image(
                        key: ValueKey(_cached),
                        image: _cached!,
                        width: 48.0,
                        height: 48.0,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => _placeholder(context),
                      ),
                    ),
                  )
                : _placeholder(context),
            if (_isHovered || _isPickingCover)
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: overlayColor,
                  borderRadius: AppRadius.smCircular,
                ),
                child: _isPickingCover
                    ? Center(
                        child: SizedBox(
                          width: 20.0,
                          height: 20.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: scheme.onSurface,
                          ),
                        ),
                      )
                    : Icon(Symbols.brush, size: 20, color: scheme.onSurface),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 48.0,
      height: 48.0,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.smCircular,
      ),
      child: Icon(Symbols.queue_music, color: scheme.onSurface.withAlpha(100)),
    );
  }
}
