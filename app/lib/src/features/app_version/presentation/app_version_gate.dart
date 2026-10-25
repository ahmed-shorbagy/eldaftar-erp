import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_version_evaluator.dart';
import '../domain/app_version_gateway.dart';
import '../domain/app_version_policy.dart';
import 'forced_update_screen.dart';

class AppVersionGate extends StatefulWidget {
  const AppVersionGate({
    super.key,
    required this.child,
    required this.currentVersion,
    this.gateway,
    this.platform,
    this.onToggleTheme,
  });

  final Widget child;
  final String currentVersion;
  final AppVersionGateway? gateway;
  final AppVersionPlatform? platform;
  final Future<void> Function(Brightness)? onToggleTheme;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate> {
  AppVersionBlock? _block;
  bool _hadSuccessfulBlock = false;
  bool _loading = false;
  bool _fetchFailed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant AppVersionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.currentVersion != widget.currentVersion ||
        oldWidget.platform != widget.platform) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final gateway = widget.gateway;
    if (gateway == null) {
      setState(() {
        _block = null;
        _hadSuccessfulBlock = false;
        _fetchFailed = false;
        _loading = false;
      });
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _fetchFailed = false;
    });
    try {
      final snapshot = await gateway.getPolicy();
      if (!mounted || generation != _generation) return;
      final block = evaluateAppVersionBlock(
        snapshot: snapshot,
        currentVersion: widget.currentVersion,
        platform: widget.platform,
      );
      setState(() {
        _block = block;
        _hadSuccessfulBlock = block != null;
        _fetchFailed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _fetchFailed = true;
        _loading = false;
        if (!_hadSuccessfulBlock) {
          _block = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final block = _block;
    if (block != null) {
      return ForcedUpdateScreen(
        block: block,
        onRetry: _refresh,
        onToggleTheme: widget.onToggleTheme,
      );
    }
    if (_fetchFailed && !_hadSuccessfulBlock) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'تعذر التحقق من تحديث التطبيق. يمكنك المتابعة مؤقتًا.',
                          key: const Key('app-version-fetch-banner'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        key: const Key('app-version-fetch-retry'),
                        onPressed: _loading ? null : _refresh,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return widget.child;
  }
}
