import 'package:flutter/material.dart';

/// Lets nested shop pages open the shared workspace drawer.
class WorkspaceChrome extends InheritedWidget {
  const WorkspaceChrome({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  final VoidCallback openDrawer;

  static WorkspaceChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceChrome>();

  static Widget? menuButton(BuildContext context) {
    final chrome = maybeOf(context);
    if (chrome == null) return null;
    return IconButton(
      key: const Key('workspace-menu'),
      tooltip: 'القائمة',
      icon: const Icon(Icons.menu),
      onPressed: chrome.openDrawer,
    );
  }

  @override
  bool updateShouldNotify(WorkspaceChrome oldWidget) =>
      openDrawer != oldWidget.openDrawer;
}
