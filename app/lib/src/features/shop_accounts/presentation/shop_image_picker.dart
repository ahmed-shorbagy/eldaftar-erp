import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../invoice_appearance/application/logo_codec.dart';
import '../../invoice_appearance/domain/logo_bytes.dart';
import 'shop_image_copy.dart';

/// Arabic camera / gallery sheet using the standard [ImagePicker] package.
Future<Uint8List?> pickShopImageBytes(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                ShopImageCopy.pickSheetTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              key: const Key('shop-image-source-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text(ShopImageCopy.pickCamera),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              key: const Key('shop-image-source-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(ShopImageCopy.pickGallery),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (source == null || !context.mounted) return null;

  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    maxWidth: logoMaxDimension.toDouble(),
    maxHeight: logoMaxDimension.toDouble(),
    imageQuality: 88,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final raw = await file.readAsBytes();
  if (raw.isEmpty) {
    throw const LogoByteRejection('logo_rejected');
  }
  final prepared = await prepareLogo(raw);
  return prepared.bytes;
}
