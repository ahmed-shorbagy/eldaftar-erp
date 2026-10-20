import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../invoice_appearance/domain/logo_bytes.dart';
import '../domain/shop_account.dart';
import '../domain/shop_image.dart';
import 'shop_image_copy.dart';
import 'shop_image_picker.dart';

class ShopImageScreen extends StatefulWidget {
  const ShopImageScreen({
    super.key,
    required this.shop,
    required this.gateway,
    this.initialBytes,
    this.onChanged,
  });

  final ShopAccount shop;
  final ShopImageGateway gateway;
  final Uint8List? initialBytes;
  final ValueChanged<Uint8List?>? onChanged;

  @override
  State<ShopImageScreen> createState() => _ShopImageScreenState();
}

class _ShopImageScreenState extends State<ShopImageScreen> {
  Uint8List? _bytes;
  String? _sha;
  bool _loading = true;
  bool _busy = false;
  String? _status;
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    _sha = widget.shop.imageSha256;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final current = await widget.gateway.readCurrent();
      if (!mounted) return;
      setState(() {
        _bytes = current?.bytes;
        _sha = current?.sha256;
        _loading = false;
      });
      widget.onChanged?.call(_bytes);
    } on ShopImageException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusError = true;
        _status = ShopImageCopy.messageFor(error.failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusError = true;
        _status = ShopImageCopy.unavailable;
      });
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final picked = await pickShopImageBytes(context);
      if (!mounted) return;
      if (picked == null) {
        setState(() => _busy = false);
        return;
      }
      final saved = await widget.gateway.setImage(picked);
      if (!mounted) return;
      setState(() {
        _bytes = saved.bytes;
        _sha = saved.sha256;
        _busy = false;
        _statusError = false;
        _status = ShopImageCopy.success;
      });
      widget.onChanged?.call(_bytes);
    } on LogoByteRejection {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusError = true;
        _status = ShopImageCopy.rejected;
      });
    } on ShopImageException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusError = true;
        _status = ShopImageCopy.messageFor(error.failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusError = true;
        _status = ShopImageCopy.unavailable;
      });
    }
  }

  Future<void> _clear() async {
    if (_busy || _bytes == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await widget.gateway.clearImage();
      if (!mounted) return;
      setState(() {
        _bytes = null;
        _sha = null;
        _busy = false;
        _statusError = false;
        _status = ShopImageCopy.cleared;
      });
      widget.onChanged?.call(null);
    } on ShopImageException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusError = true;
        _status = ShopImageCopy.messageFor(error.failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusError = true;
        _status = ShopImageCopy.unavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text(ShopImageCopy.title)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(ShopImageCopy.body, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 8),
                Text(
                  widget.shop.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: SizedBox(
                      width: 128,
                      height: 128,
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _bytes == null
                          ? Icon(
                              Icons.storefront_outlined,
                              size: 48,
                              color: scheme.onSurfaceVariant,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.memory(
                                _bytes!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                    ),
                  ),
                ),
                if (_bytes == null && !_loading) ...[
                  const SizedBox(height: 12),
                  Text(
                    ShopImageCopy.empty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _status!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: _statusError ? scheme.error : scheme.tertiary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('shop-image-pick'),
                  onPressed: _busy || _loading ? null : _pick,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _busy
                        ? ShopImageCopy.saving
                        : (_bytes == null
                              ? ShopImageCopy.pick
                              : ShopImageCopy.change),
                  ),
                ),
                if (_bytes != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('shop-image-clear'),
                    onPressed: _busy || _loading ? null : _clear,
                    child: Text(
                      _busy ? ShopImageCopy.clearing : ShopImageCopy.clear,
                    ),
                  ),
                ],
                if (_sha != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _sha!,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
