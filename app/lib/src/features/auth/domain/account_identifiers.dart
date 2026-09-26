import 'dart:convert';

/// Canonical account identifiers. Passwords stay in memory for the Auth
/// request only and are omitted from [toString].
enum SignInIdentifier { email, phone }

abstract final class AccountEmail {
  static final _pattern = RegExp(
    r'^[a-z0-9._%+\-]+@[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?)+$',
  );

  static String? tryCanonical(String input) {
    final value = input.trim().toLowerCase();
    if (value.isEmpty || value.length > 320 || !_pattern.hasMatch(value)) {
      return null;
    }
    return value;
  }
}

abstract final class EgyptianPhone {
  static final _local = RegExp(r'^01[0125][0-9]{8}$');
  static final _e164 = RegExp(r'^\+201[0125][0-9]{8}$');
  static final _idd = RegExp(r'^00201[0125][0-9]{8}$');

  /// Trims and removes spaces, hyphens, and parentheses, then accepts only
  /// the local `01[0125]` form, `+201[0125]`, or `00201[0125]`.
  static String? tryCanonical(String input) {
    if (RegExp(r'[^0-9+ \-()]').hasMatch(input)) return null;
    final stripped = input.replaceAll(RegExp(r'[ \-()]'), '');
    if (stripped.isEmpty || !RegExp(r'^\+?[0-9]+$').hasMatch(stripped)) {
      return null;
    }
    if (_local.hasMatch(stripped)) return '+20${stripped.substring(1)}';
    if (_e164.hasMatch(stripped)) return stripped;
    if (_idd.hasMatch(stripped)) return '+${stripped.substring(2)}';
    return null;
  }
}

abstract final class AccountPassword {
  static bool isAcceptable(String password) {
    final size = utf8.encode(password).length;
    return password.trim().isNotEmpty && size >= 8 && size <= 72;
  }
}

abstract final class AccountName {
  static final _controls = RegExp(r'[\u0000-\u001F\u007F]');

  static String? tryCanonical(String input) {
    final value = input.trim();
    final length = value.runes.length;
    if (length < 1 || length > 120 || _controls.hasMatch(value)) return null;
    return value;
  }
}

class SignInRequest {
  const SignInRequest._({
    required this.kind,
    required this.identifier,
    required this.password,
  });

  final SignInIdentifier kind;
  final String identifier;
  final String password;

  static SignInRequest? tryCreate({
    required SignInIdentifier kind,
    required String identifier,
    required String password,
  }) {
    if (!AccountPassword.isAcceptable(password)) return null;
    final canonical = switch (kind) {
      SignInIdentifier.email => AccountEmail.tryCanonical(identifier),
      SignInIdentifier.phone => EgyptianPhone.tryCanonical(identifier),
    };
    if (canonical == null) return null;
    return SignInRequest._(
      kind: kind,
      identifier: canonical,
      password: password,
    );
  }

  @override
  String toString() => 'SignInRequest(kind: $kind)';
}
