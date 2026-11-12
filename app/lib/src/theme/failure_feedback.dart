import 'feedback_copy.dart';
import 'message_tone.dart';

/// What kind of failure the owner is looking at (M1). Every gateway code maps
/// to one kind; the kind decides tone, generic copy and the next action.
enum FailureKind {
  /// Nothing reached the server (no connection, endpoint unavailable).
  offline,

  /// A request was sent but its result is unknown; retry with the same key.
  unknownOutcome,

  /// The server refused the request for a business reason.
  rejected,

  /// Session ended or permission changed.
  accessLost,

  /// The shop's subscription allows reading only.
  readOnly,

  /// The data changed since the screen was opened.
  stale,

  /// Only this device failed to keep something.
  deviceStorage,

  /// Anything else.
  unexpected,
}

/// Maps a gateway error code to its [FailureKind].
FailureKind failureKindFor(String? code) {
  if (code == null || code.isEmpty) return FailureKind.unexpected;
  if (const {
    'session_expired',
    'unauthenticated',
    'forbidden',
  }.contains(code)) {
    return FailureKind.accessLost;
  }
  if (code == 'shop_not_active' ||
      code == 'read_only' ||
      code.startsWith('entitlement')) {
    return FailureKind.readOnly;
  }
  if (code.startsWith('stale_')) return FailureKind.stale;
  if (const {
    'unavailable',
    'rpc_unavailable',
    'network',
    'offline',
    'timeout',
    'rate_limited',
  }.contains(code)) {
    return FailureKind.offline;
  }
  if (const {'unknown', 'status_unknown', 'unconfirmed'}.contains(code)) {
    return FailureKind.unknownOutcome;
  }
  if (const {'storage', 'device_storage'}.contains(code)) {
    return FailureKind.deviceStorage;
  }
  return FailureKind.rejected;
}

/// Tone, generic Arabic copy and next action for a failure. A feature that
/// knows the exact reason passes it as [reason]; it becomes the title.
final class FailureFeedback {
  const FailureFeedback({
    required this.tone,
    required this.title,
    this.body,
    this.actionLabel,
  });

  final MessageTone tone;
  final String title;
  final String? body;
  final String? actionLabel;
}

FailureFeedback failureFeedback(FailureKind kind, {String? reason}) =>
    switch (kind) {
      FailureKind.offline => FailureFeedback(
        tone: MessageTone.warning,
        title: reason ?? 'لا يوجد اتصال بالخادم',
        body: 'لم يُرسل شيء. أعد المحاولة عند عودة الاتصال.',
        actionLabel: FeedbackCopy.retry,
      ),
      FailureKind.unknownOutcome => FailureFeedback(
        tone: MessageTone.warning,
        title: reason ?? FeedbackCopy.unknownOutcome,
        body: FeedbackCopy.unknownOutcomeBody,
        actionLabel: FeedbackCopy.retry,
      ),
      FailureKind.rejected => FailureFeedback(
        tone: MessageTone.error,
        title: reason ?? 'رفض الخادم الطلب',
        body: 'لم يُحفظ شيء.',
      ),
      FailureKind.accessLost => FailureFeedback(
        tone: MessageTone.error,
        title: reason ?? 'انتهت الجلسة أو تغيّرت الصلاحية',
        body: 'سجّل الدخول مجددًا ثم أعد المحاولة.',
      ),
      FailureKind.readOnly => FailureFeedback(
        tone: MessageTone.warning,
        title: reason ?? 'الاشتراك للقراءة فقط',
        body: 'جدّد الاشتراك لتسجيل عمليات جديدة. بياناتك محفوظة.',
      ),
      FailureKind.stale => FailureFeedback(
        tone: MessageTone.warning,
        title: reason ?? 'تغيّرت البيانات منذ فتح الشاشة',
        body: 'حدّث البيانات وراجعها قبل التأكيد.',
      ),
      FailureKind.deviceStorage => FailureFeedback(
        tone: MessageTone.info,
        title: reason ?? FeedbackCopy.devicePreferenceFailed,
        body: FeedbackCopy.devicePreferenceBody,
      ),
      FailureKind.unexpected => FailureFeedback(
        tone: MessageTone.error,
        title: reason ?? FeedbackCopy.unexpected,
        actionLabel: FeedbackCopy.retry,
      ),
    };

/// Tone for a feature's own failure text when only its code is known.
MessageTone failureTone(String? code) =>
    failureFeedback(failureKindFor(code)).tone;
