import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// One scroll area, a persistent title and an explicit exit on every platform.
Future<void> showDetailSurface(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  Widget content(BuildContext surface) => Directionality(
    textDirection: TextDirection.rtl,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(surface).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const Key('detail-close'),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(surface).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              24 + MediaQuery.viewInsetsOf(surface).bottom,
            ),
            child: builder(surface),
          ),
        ),
      ],
    ),
  );

  if (MediaQuery.sizeOf(context).width >= AppTokens.wideBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (surface) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: AppTokens.contentMaxWidth,
          height: MediaQuery.sizeOf(surface).height * .84,
          child: content(surface),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (surface) => SizedBox(
      height: MediaQuery.sizeOf(surface).height * .88,
      child: content(surface),
    ),
  );
}
