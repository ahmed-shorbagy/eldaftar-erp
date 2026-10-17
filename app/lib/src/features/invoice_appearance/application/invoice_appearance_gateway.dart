import '../domain/appearance_rules.dart';
import 'invoice_appearance_contract.dart';

/// Owner appearance and presentation reads. No signed or public logo URL.
abstract class InvoiceAppearanceGateway {
  Object? appearanceSession(String userId);

  Future<InvoiceAppearanceSnapshot> readAppearance({
    required String userId,
    required String shopId,
  });

  Future<InvoiceAppearanceReview> reviewAppearance({
    required String userId,
    required String shopId,
    required Map<String, Object?> payload,
  });

  Future<AppearanceTransport> sendAppearance({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  });

  Future<AppearanceTransport> appearanceStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  });

  Future<LogoUploadResult> uploadInvoiceLogo({
    required String userId,
    required String shopId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  });

  Future<LogoConfirmation> confirmInvoiceLogo({
    required String userId,
    required String shopId,
    required String base64Bytes,
    required String sha256,
  });

  Future<InvoiceBrandSource> readBrandSource({
    required String userId,
    required String shopId,
    required String operationId,
  });

  Future<AppearanceTransport> sendPresentation({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  });

  Future<AppearanceTransport> presentationStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  });

  Future<InvoicePresentationList> listPresentations({
    required String userId,
    required String shopId,
    required String operationId,
  });

  Future<InvoicePresentationCopy> readPresentation({
    required String userId,
    required String shopId,
    required String operationId,
    required int edition,
  });
}

final class InvoiceAppearanceException implements Exception {
  const InvoiceAppearanceException([this.code]);
  final String? code;
}

enum LogoUploadDisposition { stored, alreadyPresent, rejected, unknown }

final class LogoUploadResult {
  const LogoUploadResult(this.disposition, {this.code});
  final LogoUploadDisposition disposition;
  final String? code;
}

final class InvoiceAppearanceSnapshot {
  const InvoiceAppearanceSnapshot({
    required this.shopId,
    required this.value,
    required this.canWrite,
    required this.timeZone,
  });

  final String shopId;
  final InvoiceAppearanceValue value;
  final bool canWrite;
  final String timeZone;
}

final class InvoiceAppearanceReview {
  const InvoiceAppearanceReview({
    required this.status,
    required this.currentRevision,
    required this.canWrite,
    this.normalized,
  });

  final String status;
  final int currentRevision;
  final bool canWrite;
  final Map<String, Object?>? normalized;
}

final class AppearanceReceipt {
  const AppearanceReceipt({
    required this.shopId,
    required this.key,
    required this.kind,
    required this.payload,
    required this.actorId,
    required this.atUtc,
    required this.replayed,
    this.revision,
    this.edition,
    this.operationId,
    this.contentSha256,
    this.appearanceRevision,
  });

  final String shopId;
  final String key;
  final String kind;
  final Map<String, Object?> payload;
  final String actorId;
  final String atUtc;
  final bool replayed;
  final int? revision;
  final int? edition;
  final String? operationId;
  final String? contentSha256;
  final int? appearanceRevision;
}

final class AppearanceTransport {
  const AppearanceTransport({this.receipt, this.error, this.absent = false});
  final AppearanceReceipt? receipt;
  final String? error;
  final bool absent;
}

final class LogoConfirmation {
  const LogoConfirmation({
    required this.shopId,
    required this.assetId,
    required this.sha256,
    required this.mime,
    required this.width,
    required this.height,
  });

  final String shopId;
  final String assetId;
  final String sha256;
  final String mime;
  final int width;
  final int height;
}

final class InvoiceBrandSource {
  const InvoiceBrandSource({
    required this.shopId,
    required this.operationId,
    required this.kind,
    required this.shopName,
    required this.shopSequence,
    required this.timeZone,
    required this.occurredAtUtc,
    required this.occurredAtShop,
    required this.payload,
    required this.contentSha256,
    required this.appearance,
    required this.latestEdition,
    required this.canWrite,
  });

  final String shopId;
  final String operationId;
  final String kind;
  final String shopName;
  final String shopSequence;
  final String timeZone;
  final String occurredAtUtc;
  final String occurredAtShop;
  final Map<String, Object?> payload;
  final String contentSha256;
  final InvoiceAppearanceValue appearance;
  final int latestEdition;
  final bool canWrite;

  Map<String, Object?> get documentSource => {
    'operation_id': operationId,
    'kind': kind,
    'shop_name': shopName,
    'shop_sequence': shopSequence,
    'time_zone': timeZone,
    'occurred_at': occurredAtUtc,
    'occurred_at_shop': occurredAtShop,
    'payload': payload,
  };
}

final class InvoicePresentationSummary {
  const InvoicePresentationSummary({
    required this.edition,
    required this.contentSha256,
    required this.appearanceRevision,
    required this.template,
    required this.accent,
    required this.renderVersion,
    required this.createdAtUtc,
    required this.createdAtShop,
    required this.hasLogo,
  });

  final int edition;
  final String contentSha256;
  final int appearanceRevision;
  final String template;
  final String accent;
  final int renderVersion;
  final String createdAtUtc;
  final String createdAtShop;
  final bool hasLogo;
}

final class InvoicePresentationList {
  const InvoicePresentationList({
    required this.shopId,
    required this.operationId,
    required this.canWrite,
    required this.items,
  });

  final String shopId;
  final String operationId;
  final bool canWrite;
  final List<InvoicePresentationSummary> items;
}

final class InvoicePresentationCopy {
  const InvoicePresentationCopy({
    required this.shopId,
    required this.operationId,
    required this.edition,
    required this.contentSha256,
    required this.contentMatches,
    required this.appearance,
    required this.logoState,
    required this.renderVersion,
    required this.actorId,
    required this.createdAtUtc,
    required this.createdAtShop,
    required this.shopName,
    required this.shopSequence,
    required this.kind,
    required this.timeZone,
    required this.occurredAtUtc,
    required this.occurredAtShop,
    required this.payload,
    required this.canWrite,
    this.logoBytes,
  });

  final String shopId;
  final String operationId;
  final int edition;
  final String contentSha256;
  final bool contentMatches;
  final InvoiceAppearanceValue appearance;
  final String logoState;
  final int renderVersion;
  final String actorId;
  final String createdAtUtc;
  final String createdAtShop;
  final String shopName;
  final String shopSequence;
  final String kind;
  final String timeZone;
  final String occurredAtUtc;
  final String occurredAtShop;
  final Map<String, Object?> payload;
  final bool canWrite;
  final List<int>? logoBytes;

  Map<String, Object?> get documentSource => {
    'operation_id': operationId,
    'kind': kind,
    'shop_name': shopName,
    'shop_sequence': shopSequence,
    'time_zone': timeZone,
    'occurred_at': occurredAtUtc,
    'occurred_at_shop': occurredAtShop,
    'payload': payload,
  };
}

/// Keeps the kind constants referenced by the locker without a second definition.
typedef InvoiceCommandKind = String;
const InvoiceCommandKind appearanceCommandKind = invoiceAppearanceKind;
