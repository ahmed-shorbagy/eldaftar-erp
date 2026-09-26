/// ISO 3166-2:EG codes for the 27 governorates.
///
/// This set validates a code. It is not a substitute for the server catalog:
/// Arabic names are loaded from `egypt_governorates`.
abstract final class EgyptianGovernorates {
  static const codes = <String>{
    'EG-ALX',
    'EG-ASN',
    'EG-AST',
    'EG-BA',
    'EG-BH',
    'EG-BNS',
    'EG-C',
    'EG-DK',
    'EG-DT',
    'EG-FYM',
    'EG-GH',
    'EG-GZ',
    'EG-IS',
    'EG-JS',
    'EG-KB',
    'EG-KFS',
    'EG-KN',
    'EG-LX',
    'EG-MN',
    'EG-MNF',
    'EG-MT',
    'EG-PTS',
    'EG-SHG',
    'EG-SHR',
    'EG-SIN',
    'EG-SUZ',
    'EG-WAD',
  };

  static bool isValid(String code) => codes.contains(code);
}

class Governorate {
  const Governorate({required this.code, required this.nameAr});

  final String code;
  final String nameAr;
}

enum GovernorateLoadFailure { unavailable, invalidResponse }

class GovernorateLoadException implements Exception {
  const GovernorateLoadException(this.failure);

  final GovernorateLoadFailure failure;

  @override
  String toString() => 'GovernorateLoadException($failure)';
}
