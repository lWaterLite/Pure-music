import 'package:pure_music/component/responsive_builder.dart';
import 'package:pure_music/core/design_tokens.dart';
import 'package:flutter/material.dart';

/// title, actions, body
///
/// 提供基本的响应式布局：
///
/// 小屏幕时，标题在上、操作按钮在下，互不挤压；
/// 中大屏幕时，标题和操作按钮在同一行排列。
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.actions,
    this.actionRows,
    required this.body,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<List<Widget>>? actionRows;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveBuilder(
            builder: (context, screenType) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: switch (screenType) {
                  ScreenType.small => _buildSmallLayout(scheme),
                  ScreenType.medium ||
                  ScreenType.large => _buildWideLayout(scheme),
                },
              );
            },
          ),
          Container(
            height: 10,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surfaceContainer.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildSmallLayout(ColorScheme scheme) {
    if (_hasNoActions) {
      return _titleWidget(scheme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _titleWidget(scheme),
        const SizedBox(height: 16.0),
        _buildSmallActions(),
      ],
    );
  }

  Widget _buildWideLayout(ColorScheme scheme) {
    if (_hasNoActions) {
      return _titleWidget(scheme);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _titleWidget(scheme)),
        const SizedBox(width: 16.0),
        _buildWideActions(),
      ],
    );
  }

  bool get _hasNoActions =>
      actionRows?.every((row) => row.isEmpty) ?? actions.isEmpty;

  Widget _buildSmallActions() {
    final rows = actionRows;
    if (rows == null) {
      return Wrap(spacing: 8.0, runSpacing: 8.0, children: actions);
    }
    final nonEmptyRows = rows.where((row) => row.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < nonEmptyRows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8.0),
          Wrap(spacing: 8.0, runSpacing: 8.0, children: nonEmptyRows[i]),
        ],
      ],
    );
  }

  Widget _buildWideActions() {
    final rows = actionRows;
    if (rows == null) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8.0,
        runSpacing: 8.0,
        children: actions,
      );
    }
    final nonEmptyRows = rows.where((row) => row.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < nonEmptyRows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8.0),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _withSpacing(nonEmptyRows[i]),
          ),
        ],
      ],
    );
  }

  List<Widget> _withSpacing(List<Widget> row) {
    final result = <Widget>[];
    for (var i = 0; i < row.length; i++) {
      if (i > 0) result.add(const SizedBox(width: 8.0));
      result.add(row[i]);
    }
    return result;
  }

  Widget _titleWidget(ColorScheme scheme) {
    if (subtitle == null) {
      return Text(
        title,
        style: TextStyle(
          fontSize: AppType.display,
          fontWeight: AppType.weightSemibold,
          color: scheme.onSurface,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: AppType.display,
            fontWeight: AppType.weightSemibold,
            color: scheme.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6.0),
        Text(
          subtitle!,
          style: TextStyle(
            fontSize: AppType.body,
            color: scheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
