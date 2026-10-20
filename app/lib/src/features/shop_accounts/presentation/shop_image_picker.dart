import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/shop_image_codec.dart';
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

  // Do not pass maxWidth, maxHeight, or imageQuality. Those ask the picker to
  // transcode during selection and fail for some gallery files (HEIC, WebP,
  // and large camera originals). The chosen file is compressed afterwards.
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  // Camera apps sometimes return the path before the file is fully written.
  var raw = await file.readAsBytes();
  if (raw.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    raw = await file.readAsBytes();
  }
  return compressShopPhoto(raw);
}
