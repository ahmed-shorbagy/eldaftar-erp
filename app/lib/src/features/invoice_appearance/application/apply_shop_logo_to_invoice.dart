import 'dart:convert';
import 'dart:typed_data';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../data/logo_upload_store.dart';
import '../domain/logo_bytes.dart';
import 'invoice_appearance_contract.dart';
import 'invoice_appearance_flow.dart';
import 'invoice_appearance_gateway.dart';
import 'logo_codec.dart';

/// Result of putting the shop logo on the saved invoice appearance.
enum ApplyLogoOutcome { applied, alreadyApplied, notAllowed, failed }

/// Upload result shared by the appearance screen and [ApplyShopLogoToInvoice].
sealed class ShopLogoUploadOutcome {
  const ShopLogoUploadOutcome();
}

final class ShopLogoLinked extends ShopLogoUploadOutcome {
  const ShopLogoLinked({required this.assetId, required this.sha256});

  final String assetId;
  final String sha256;
}

final class ShopLogoUnconfirmed extends ShopLogoUploadOutcome {
  const ShopLogoUnconfirmed();
}

final class ShopLogoRejected extends ShopLogoUploadOutcome {
  const ShopLogoRejected();
}

final class ShopLogoMismatch extends ShopLogoUploadOutcome {
  const ShopLogoMismatch();
}

final class ShopLogoCancelled extends ShopLogoUploadOutcome {
  const ShopLogoCancelled();
}

/// Uploads and confirms a logo the same way the appearance screen does.
Future<ShopLogoUploadOutcome> uploadShopLogoForInvoice({
  required InvoiceAppearanceGateway gateway,
  required LogoUploadStore logoStore,
  required String userId,
  required String shopId,
  required Uint8List selected,
  bool Function()? cancelled,
}) async {
  bool stopped() => cancelled?.call() == true;
  final prior = await logoStore.read(userId, shopId);
  if (stopped()) return const ShopLogoCancelled();
  final prepared = await prepareLogo(selected);
  if (stopped()) return const ShopLogoCancelled();
  final fromRegistration = prior?.fromRegistration == true;
  final record = LogoUploadRecord(
    phase: LogoUploadPhase.uploadPending,
    sha256: prepared.sha256,
    mime: prepared.facts.mime,
    objectName: prepared.objectName(shopId),
    fromRegistration: fromRegistration,
  );
  await logoStore.save(userId, shopId, record, prepared.bytes);
  if (stopped()) return const ShopLogoCancelled();
  final upload = await gateway.uploadInvoiceLogo(
    userId: userId,
    shopId: shopId,
    objectName: record.objectName,
    mimeType: prepared.facts.mime,
    bytes: prepared.bytes,
  );
  if (stopped()) return const ShopLogoCancelled();
  if (upload.disposition == LogoUploadDisposition.unknown) {
    return const ShopLogoUnconfirmed();
  }
  if (upload.disposition == LogoUploadDisposition.rejected) {
    await logoStore.save(
      userId,
      shopId,
      LogoUploadRecord(
        phase: LogoUploadPhase.failed,
        sha256: prepared.sha256,
        mime: prepared.facts.mime,
        objectName: record.objectName,
        message: 'تعذر حفظ الشعار.',
        fromRegistration: fromRegistration,
      ),
      prepared.bytes,
    );
    return const ShopLogoRejected();
  }
  await logoStore.save(
    userId,
    shopId,
    LogoUploadRecord(
      phase: LogoUploadPhase.confirmPending,
      sha256: prepared.sha256,
      mime: prepared.facts.mime,
      objectName: record.objectName,
      fromRegistration: fromRegistration,
    ),
    prepared.bytes,
  );
  if (stopped()) return const ShopLogoCancelled();
  final confirmed = await gateway.confirmInvoiceLogo(
    userId: userId,
    shopId: shopId,
    base64Bytes: base64Encode(prepared.bytes),
    sha256: prepared.sha256,
  );
  if (stopped()) return const ShopLogoCancelled();
  if (confirmed.shopId != shopId || confirmed.sha256 != prepared.sha256) {
    return const ShopLogoMismatch();
  }
  await logoStore.save(
    userId,
    shopId,
    LogoUploadRecord(
      phase: LogoUploadPhase.confirmed,
      sha256: confirmed.sha256,
      mime: confirmed.mime,
      objectName: record.objectName,
      assetId: confirmed.assetId,
      fromRegistration: fromRegistration,
    ),
    prepared.bytes,
  );
  return ShopLogoLinked(assetId: confirmed.assetId, sha256: confirmed.sha256);
}

/// Applies a shop logo to the saved invoice appearance.
///
/// The appearance screen uses [uploadShopLogoForInvoice] for the upload step.
/// This class continues with review and a single idempotent save.
final class ApplyShopLogoToInvoice {
  ApplyShopLogoToInvoice({
    required this.gateway,
    required this.store,
    required this.logoStore,
    this.newKey,
  });

  final InvoiceAppearanceGateway gateway;
  final FinancialCommandLocker store;
  final LogoUploadStore logoStore;
  final String Function()? newKey;

  String? _key;
  PendingFinancialCommand? _pending;

  /// Never throws: any transport or parsing error is reported as `failed`.
  Future<ApplyLogoOutcome> call({
    required String userId,
    required String shopId,
    required Uint8List logoBytes,
  }) async {
    try {
      return await _run(userId, shopId, logoBytes);
    } catch (_) {
      return ApplyLogoOutcome.failed;
    }
  }

  Future<ApplyLogoOutcome> _run(
    String userId,
    String shopId,
    Uint8List logoBytes,
  ) async {
    if (_pending != null) {
      return _finish(
        userId,
        shopId,
        await _flow.reconcile(
          userId,
          shopId,
          _pending!,
          retry: true,
          canWrite: true,
        ),
      );
    }
    final snapshot = await gateway.readAppearance(
      userId: userId,
      shopId: shopId,
    );
    if (!snapshot.canWrite) return ApplyLogoOutcome.notAllowed;
    final PreparedLogo prepared;
    try {
      prepared = await prepareLogo(logoBytes);
    } on LogoByteRejection {
      return ApplyLogoOutcome.failed;
    }
    if (snapshot.value.logoSha256 == prepared.sha256) {
      return ApplyLogoOutcome.alreadyApplied;
    }
    final ShopLogoUploadOutcome uploaded;
    try {
      uploaded = await uploadShopLogoForInvoice(
        gateway: gateway,
        logoStore: logoStore,
        userId: userId,
        shopId: shopId,
        selected: logoBytes,
      );
    } catch (_) {
      return ApplyLogoOutcome.failed;
    }
    if (uploaded is! ShopLogoLinked) return ApplyLogoOutcome.failed;
    final value = snapshot.value;
    final payload = appearanceCommandPayload(
      expectedRevision: value.revision,
      template: value.template,
      accent: value.accent,
      slogan: value.slogan,
      address: value.address,
      logoAssetId: uploaded.assetId,
    );
    try {
      final review = await gateway.reviewAppearance(
        userId: userId,
        shopId: shopId,
        payload: payload,
      );
      if (review.status == 'expired' || !review.canWrite) {
        return ApplyLogoOutcome.notAllowed;
      }
      if (review.status != 'ready') return ApplyLogoOutcome.failed;
    } on InvoiceAppearanceException {
      return ApplyLogoOutcome.failed;
    } catch (_) {
      return ApplyLogoOutcome.failed;
    }
    _key ??= (newKey ?? newIdempotencyKey)();
    return _finish(
      userId,
      shopId,
      await _flow.submitAppearance(
        userId,
        shopId,
        _key!,
        payload,
        canWrite: true,
      ),
    );
  }

  InvoiceAppearanceFlow get _flow => InvoiceAppearanceFlow(gateway, store);

  Future<ApplyLogoOutcome> _finish(
    String userId,
    String shopId,
    InvoiceCommandOutcome outcome,
  ) async {
    if (outcome.receipt != null && outcome.error == null) {
      try {
        await logoStore.clear(userId, shopId);
      } catch (_) {
        // The server receipt remains authoritative if local cleanup fails.
      }
      _pending = null;
      _key = null;
      return ApplyLogoOutcome.applied;
    }
    if (outcome.error == 'shop_not_active') {
      _pending = null;
      return ApplyLogoOutcome.notAllowed;
    }
    if (outcome.pending != null) _pending = outcome.pending;
    return ApplyLogoOutcome.failed;
  }
}
