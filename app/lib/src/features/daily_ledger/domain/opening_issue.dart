/// Stable opening-validation codes. Arabic copy stays in the UI task.
enum OpeningIssueCode {
  invalidInput('invalid_input'),
  negativeAmount('negative_amount'),
  overflow('overflow'),
  unsupportedCategoryKarat('unsupported_category_karat'),
  duplicateBucket('duplicate_bucket');

  const OpeningIssueCode(this.wire);
  final String wire;
}

sealed class DomainResult<T> {
  const DomainResult();
}

final class Accepted<T> extends DomainResult<T> {
  const Accepted(this.value);
  final T value;
}

final class Rejected<T> extends DomainResult<T> {
  const Rejected(this.code);
  final OpeningIssueCode code;
}
