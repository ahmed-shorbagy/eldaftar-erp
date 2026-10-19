import 'financial_gateway.dart';
import 'idempotency_key.dart';
import 'pending_financial_command.dart';

const tradeChangeKind = 'ledger_trade_change';
final _hash = RegExp(r'^[a-f0-9]{64}$');

class LedgerTradeChangeReview {
  const LedgerTradeChangeReview({
    required this.shopId,
    required this.operationId,
    required this.action,
    required this.dayId,
    required this.dayVersion,
    required this.sourceHash,
    required this.token,
    required this.source,
    required this.effects,
  });
  final String shopId, operationId, action, dayId, sourceHash, token;
  final int dayVersion;
  final Map<String, Object?> source, effects;
  Map<String, Object?> request(String key, Map<String, Object?>? replacement) =>
      {
        'p_idempotency_key': key,
        'p_operation_id': operationId,
        'p_action': action,
        'p_replacement': replacement,
        'p_expected_day_id': dayId,
        'p_expected_day_version': dayVersion,
        'p_source_sha256': sourceHash,
        'p_review_token': token,
      };
}

abstract class LedgerTradeChangeGateway {
  Future<LedgerTradeChangeReview> reviewTradeChange({
    required String userId,
    required String shopId,
    required String operationId,
    required String action,
    Map<String, Object?>? replacement,
  });
  Future<FinancialCommandResult> postTradeChange({
    required String userId,
    required PendingFinancialCommand command,
  });
}

bool matchesTradeChangeEnvelope(
  String key,
  String kind,
  Map<String, Object?> body,
) {
  const fields = {
    'p_idempotency_key',
    'p_operation_id',
    'p_action',
    'p_replacement',
    'p_expected_day_id',
    'p_expected_day_version',
    'p_source_sha256',
    'p_review_token',
  };
  final replacement = body['p_replacement'];
  return kind == tradeChangeKind &&
      isUuid(key) &&
      body.length == fields.length &&
      body.keys.every(fields.contains) &&
      body['p_idempotency_key'] == key &&
      body['p_operation_id'] is String &&
      isUuid(body['p_operation_id'] as String) &&
      body['p_expected_day_id'] is String &&
      isUuid(body['p_expected_day_id'] as String) &&
      body['p_expected_day_version'] is int &&
      (body['p_expected_day_version'] as int) > 0 &&
      body['p_source_sha256'] is String &&
      _hash.hasMatch(body['p_source_sha256'] as String) &&
      body['p_review_token'] is String &&
      _hash.hasMatch(body['p_review_token'] as String) &&
      ((body['p_action'] == 'delete' && replacement == null) ||
          (body['p_action'] == 'edit' &&
              replacement is Map &&
              const {'sale', 'purchase'}.contains(replacement['kind']) &&
              const {1, 2}.contains(replacement['version'])));
}

String tradeChangeFailure(String? code) => switch (code) {
  'day_closed' ||
  'trade_not_editable' => 'التعديل والمسح متاحان لعمليات اليوم المفتوح فقط.',
  'trade_has_followups' =>
    'لهذه العملية معاملات أو حركات مخزون مرتبطة. لا يمكن تعديلها أو مسحها.',
  'trade_inactive' || 'operation_replaced' =>
    'سُبق تعديل هذه العملية أو مسحها. افتح النسخة الحالية من الدفتر.',
  'stale_trade_review' ||
  'stale_day' => 'تغيّرت البيانات. أعد فتح المراجعة قبل التأكيد.',
  'insufficient_stock' ||
  'negative_owned_balance' ||
  'insufficient_lot' => 'لا تسمح الأرصدة الحالية بتنفيذ هذا التغيير.',
  'not_available' ||
  'unavailable' => 'التعديل والمسح غير متاحين في هذا الاتصال.',
  'forbidden' ||
  'unauthenticated' ||
  'shop_not_active' => 'لا تتوفر صلاحية تنفيذ التغيير الآن.',
  'retired_return' =>
    'أُزيلت إجراءات المرتجع والاستبدال. استخدم التعديل أو المسح بعد التحقق من الطلب السابق.',
  _ => 'تعذر إعداد التغيير أو حفظه. تحقق من البيانات وحاول مجددًا.',
};
