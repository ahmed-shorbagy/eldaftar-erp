// The owner's rejected terms do not come back.
//
// Every term here has a row in docs/owner-glossary.md, with its source. This
// file is the one place the lists live:
//
//  * [_banned]: the replacement is in place, so the term may not appear in
//    `app/lib` or `admin/src`. A failure names the file and the line.
//  * [_allowed]: the only lines that may keep a banned term, each one exact.
//  * [_waiting]: rejected, but still on a screen until its replacement is
//    agreed or built. Such a term is not banned yet; when its last line goes,
//    the test asks for it to be moved to [_banned].
//
// Add a term to [_banned] only once it is gone from the screens.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _glossary = '../docs/owner-glossary.md';

/// An Arabic letter.
const _letter = r'[ء-ي]';

/// A whole Arabic word, with the particles Arabic writes in front of it
/// (و، ف، ب، ك، ل and the article). «والأمانة» is found; «بأمان» is not.
RegExp _word(String forms) =>
    RegExp('(?<!$_letter)[وف]?(?:[بكل]?(?:ال)?|لل)(?:$forms)(?!$_letter)');

/// As [_word], for a word that is rejected only with the article: «الديون»
/// the page, not «ديون» the noun.
RegExp _definite(String forms) =>
    RegExp('(?<!$_letter)[وف]?(?:[بك]?ال|لل)(?:$forms)(?!$_letter)');

class _Banned {
  const _Banned(
    this.term,
    this.pattern,
    this.reason, {
    this.dartOnly = false,
    this.under = '',
  });

  /// The term as the glossary writes it.
  final String term;
  final Pattern pattern;
  final String reason;

  /// A Dart call, looked for in `app/lib` only.
  final bool dartOnly;

  /// A term banned in one folder only, as a path from the repository root.
  /// Empty: everywhere.
  final String under;
}

class _Allowed {
  const _Allowed(this.term, this.file, this.line, this.why);

  final String term;

  /// Path from the repository root.
  final String file;

  /// The whole line, as it is in the file.
  final String line;
  final String why;
}

class _Waiting {
  const _Waiting(this.term, this.pattern, this.waitsOn);

  final String term;
  final Pattern pattern;
  final String waitsOn;
}

final _banned = <_Banned>[
  _Banned(
    'مشغولات',
    'مشغول',
    'FB-003: he works by item names; the category word is shown nowhere.',
  ),
  _Banned(
    'الصيانة',
    'صيانة',
    'ADR 0044 C-D7: the page and its records are «المرمات» / «مرمة».',
  ),
  _Banned(
    'ملليجرام',
    RegExp('مل+ي ?[جغ]رام|ميلي ?[جغ]رام|ملجم'),
    'FB-002, ADR 0050: a weight is grams with two decimals, never milligrams.',
  ),
  _Banned(
    'منازل',
    RegExp('منازل|منزلة|منزلت|عشري(?!ن)|ثلاث خانات'),
    'FB-002, ADR 0050: no hint about decimal places beside a weight.',
  ),
  _Banned(
    'toStringAsFixed(3)',
    RegExp(
      r"toStringAsFixed\(3\)|decimalPlaces: 3|padLeft\(3, '0'\)\}.{0,40}(جرام|جم)",
    ),
    'FB-002, ADR 0050: a formatter that prints a third decimal of a weight.',
    dartOnly: true,
  ),
  _Banned(
    'توقيت الخادم',
    RegExp(
      'توقيت الخادم|توقيت المتجر|التوقيت العالمي|الوقت العالمي|'
      'توقيت (?:شرق )?أوروبا',
    ),
    'FB-001: the time is shown as an ordinary clock with no zone name.',
  ),
  _Banned(
    'UTC',
    // «UTC» or «GMT» on a line of Arabic text. A zone id on its own in code
    // ('UTC', tz.UTC) and comments are not screen text.
    RegExp(
      r'^(?!\s*(?://|/\*|\*)).*'
      '(?:$_letter.*\\b(?:UTC|GMT)\\b|\\b(?:UTC|GMT)\\b.*$_letter)',
    ),
    'FB-001: no «UTC» beside a time.',
  ),
  _Banned(
    'timeZoneName',
    RegExp(r'timeZoneName|hourCycle|hour12:\s*false'),
    'FB-001: these formatter options print «توقيت شرق أوروبا» and a '
        '24-hour clock.',
  ),
  _Banned(
    'التجار والأمانات',
    'التجار والأمانات',
    'Handoff step 4: the page is «الحسابات», as in the old app.',
  ),
  _Banned(
    'الديون',
    _definite('ديون'),
    'Handoff step 4: the page is «النوتة», as in the old app. «ديون» the '
        'plain noun is not matched.',
  ),
  _Banned(
    'العطل',
    _definite('عطل'),
    'Handoff step 4: the repair field is «متطلبات التصليح», as on the old '
        'repair card.',
  ),
  _Banned(
    'وصف القطعة',
    'وصف القطعة',
    'Handoff step 4: the repair field is «المنتج», as on the old repair card '
        "(the developer's choice of 2026-11-18).",
  ),
  _Banned(
    'باقي أرقام الدفتر',
    'باقي أرقام الدفتر',
    'Handoff step 4: «المزيد» lists pages and settings only.',
  ),
  _Banned(
    'الحيازة',
    _word('حيازة'),
    'Handoff step 4: repairs have nothing to do with the shop stock; the '
        'old page says so and shows no custody wording.',
    under: 'app/lib/src/features/repairs/',
  ),
];

const _allowed = <_Allowed>[
  _Allowed(
    'مشغولات',
    'app/lib/src/features/daily_ledger/data/daily_ledger_codec.dart',
    "  'worked_jewelry': 'مشغولات',",
    'The server sends this label for jewelry stock rows and older builds '
        'expect it. The parser checks the read against it; no screen prints '
        'it.',
  ),
  _Allowed(
    'توقيت الخادم',
    'admin/src/subscribers/SubscriberDirectory.test.tsx',
    "  expect(screen.queryByText('التوقيت العالمي')).not.toBeInTheDocument()",
    'A test that the label is absent.',
  ),
];

final _waiting = <_Waiting>[
  _Waiting(
    'حيازة',
    _word('حيازة'),
    'the «الجرد الفوري» and «الحسابات» page reviews (banned in repairs since '
        'handoff step 4)',
  ),
  _Waiting(
    'أمانة',
    _word('أمانة|أمانات'),
    'the «الجرد الفوري», «الحسابات» and «النوتة» page reviews',
  ),
  _Waiting(
    'كشف أمانة',
    RegExp('كشف (?:ال)?أمانة'),
    'the «الحسابات» page review',
  ),
  _Waiting(
    'بانتظار الاعتراف',
    _word('اعتراف'),
    'the «الجرد الفوري» page review',
  ),
  _Waiting('متاح للبيع', 'متاح للبيع', 'the «الجرد الفوري» page review'),
  _Waiting('دفعات', _word('دفعة|دفعات'), 'the «الجرد الفوري» page review'),
  _Waiting(
    'عملات',
    _word('عملة|عملات'),
    'the «الجرد الفوري» page review, for the coin catalog lines',
  ),
  _Waiting(
    'فئة سبيكة اسمية',
    _word('اسمي|اسمية'),
    'the «الجرد الفوري» page review',
  ),
  _Waiting(
    'توقيت',
    'توقيت',
    'the «النوتة» page review for the reminder messages; the developer for '
        'the admin hint',
  ),
];

class _Line {
  const _Line(this.file, this.number, this.raw, this.text);

  final String file;
  final int number;
  final String raw;

  /// [raw] without vowel marks and the tatweel, so a marked spelling of a
  /// term is still found.
  final String text;

  @override
  String toString() => '$file:$number: ${raw.trim()}';
}

final _marks = RegExp(r'[ً-ْـ]');

List<_Line> _read(String root, String shownAs) {
  final directory = Directory(root);
  expect(directory.existsSync(), isTrue, reason: '$root is missing');
  final lines = <_Line>[];
  for (final file in directory.listSync(recursive: true)) {
    if (file is! File) continue;
    if (!RegExp(r'\.(dart|ts|tsx)$').hasMatch(file.path)) continue;
    final path = file.path.replaceAll('\\', '/');
    final shown = '$shownAs${path.substring(root.length)}';
    final raw = file.readAsLinesSync();
    for (var index = 0; index < raw.length; index++) {
      lines.add(
        _Line(shown, index + 1, raw[index], raw[index].replaceAll(_marks, '')),
      );
    }
  }
  return lines;
}

final List<_Line> _app = _read('lib', 'app/lib');
final List<_Line> _admin = _read('../admin/src', 'admin/src');

bool _has(Pattern pattern, String text) => text.contains(pattern);

bool _isAllowed(_Banned term, _Line line) => _allowed.any(
  (allowed) =>
      allowed.term == term.term &&
      allowed.file == line.file &&
      allowed.line == line.raw,
);

List<String> _offenders(_Banned term) => [
  for (final line in term.dartOnly ? _app : [..._app, ..._admin])
    if (line.file.startsWith(term.under) &&
        _has(term.pattern, line.text) &&
        !_isAllowed(term, line))
      '$line',
];

_Banned _rule(String term) => _banned.singleWhere((rule) => rule.term == term);

_Waiting _open(String term) =>
    _waiting.singleWhere((rule) => rule.term == term);

void main() {
  group('a banned term is on no screen', () {
    for (final term in _banned) {
      test('«${term.term}»', () {
        expect(
          _offenders(term),
          isEmpty,
          reason:
              '${term.reason} See docs/owner-glossary.md for the '
              "owner's word.",
        );
      });
    }
  });

  test('every allowed line is still there and still needed', () {
    final stale = <String>[];
    for (final allowed in _allowed) {
      final term = _rule(allowed.term);
      final found = [..._app, ..._admin].any(
        (line) =>
            line.file == allowed.file &&
            line.raw == allowed.line &&
            _has(term.pattern, line.text),
      );
      if (!found) stale.add('${allowed.file}: ${allowed.line.trim()}');
    }
    expect(stale, isEmpty, reason: 'Remove an exception nothing uses.');
  });

  test('a waiting term that left the screens is moved to the banned list', () {
    // A test that asserts a word is absent does not show it.
    final screens = [
      ..._app,
      ..._admin,
    ].where((line) => !RegExp(r'\.test\.tsx?$').hasMatch(line.file)).toList();
    final gone = <String>[];
    for (final term in _waiting) {
      final shown = screens.any((line) => _has(term.pattern, line.text));
      if (!shown) gone.add('«${term.term}» (was waiting on ${term.waitsOn})');
    }
    expect(
      gone,
      isEmpty,
      reason:
          'No line shows these any more. Move each to _banned and mark its '
          'glossary row replaced.',
    );
  });

  test('the glossary names every term of the guard', () {
    final glossary = File(_glossary).readAsStringSync();
    final missing = [
      for (final term in [
        ..._banned.map((rule) => rule.term),
        ..._waiting.map((rule) => rule.term),
      ])
        if (!glossary.contains(term)) term,
    ];
    expect(missing, isEmpty);
  });

  group('what each rule catches', () {
    bool banned(String term, String line) => _has(_rule(term).pattern, line);
    bool waiting(String term, String line) => _has(_open(term).pattern, line);

    test('the wording the two earlier scans stopped', () {
      expect(banned('مشغولات', "'مشغولات عيار 21'"), isTrue);
      expect(banned('منازل', "'ثلاث خانات، مثل 1.255'"), isTrue);
      expect(banned('منازل', "'ثلاثة أرقام عشرية كحد أقصى'"), isTrue);
      expect(banned('منازل', "'حتى منزلتين عشريتين'"), isTrue);
      expect(banned('منازل', "'حتى ثلاث منازل'"), isTrue);
      expect(banned('ملليجرام', "'(1,255 ملليجرام)'"), isTrue);
      const calls = 'toStringAsFixed(3)';
      expect(banned(calls, 'grams.toStringAsFixed(3)'), isTrue);
      expect(banned(calls, 'decimalPlaces: 3,'), isTrue);
      expect(banned(calls, r"'$whole.${rest.padLeft(3, '0')} جرام'"), isTrue);
    });

    test('a zone name or «UTC» beside a time', () {
      expect(banned('توقيت الخادم', "'2:05 م توقيت شرق أوروبا'"), isTrue);
      expect(banned('توقيت الخادم', "'توقيت الخادم'"), isTrue);
      expect(banned('UTC', "Text('وقت الخادم UTC')"), isTrue);
      expect(banned('timeZoneName', "timeZoneName: 'long',"), isTrue);
      expect(banned('timeZoneName', "hourCycle: 'h23',"), isTrue);
    });

    test('ordinary text that only resembles a banned term is left alone', () {
      expect(banned('منازل', "'خلال عشرين يومًا'"), isFalse);
      expect(banned('منازل', "'اختر ست خانات تظهر في ملخص اليوم.'"), isFalse);
      expect(banned('UTC', "String _timeZone = 'UTC';"), isFalse);
      expect(banned('UTC', '/// ص/م, and never «UTC».'), isFalse);
      expect(banned('توقيت الخادم', "'بسبب التوقيت الصيفي'"), isFalse);
      expect(banned('timeZoneName', 'hour12: true,'), isFalse);
    });

    test('a waiting term is matched in the rejected sense only', () {
      expect(waiting('أمانة', "'النقد والذهب والأمانة'"), isTrue);
      expect(waiting('أمانة', "'لعكس العملية بأمان.'"), isFalse);
      expect(waiting('عملات', "'نوع العملة'"), isTrue);
      expect(waiting('عملات', "'عمليات اليوم'"), isFalse);
      expect(waiting('دفعات', "'بحث في الدفعات'"), isTrue);
      expect(waiting('دفعات', "'طرق الدفع'"), isFalse);
    });

    test('the step 4 page names and repair words, in the rejected sense', () {
      expect(banned('الديون', "'افتح الديون من المزيد'"), isTrue);
      expect(banned('الديون', "'العودة إلى الديون'"), isTrue);
      expect(banned('الديون', "'تذكير اختياري بمواعيد الديون'"), isTrue);
      expect(banned('الديون', "'لا توجد ديون في هذا العرض.'"), isFalse);
      expect(banned('الديون', "'يوجد طلب ديون محفوظ.'"), isFalse);
      expect(banned('العطل', "'العطل: \${item.issue}'"), isTrue);
      expect(banned('العطل', "'تذكيرات هذا الجهاز معطلة.'"), isFalse);
      expect(banned('التجار والأمانات', "title: 'التجار والأمانات',"), isTrue);
      expect(banned('وصف القطعة', "_field(_item, 'وصف القطعة')"), isTrue);
      expect(banned('باقي أرقام الدفتر', "Text('باقي أرقام الدفتر')"), isTrue);
    });

    test('«الحيازة» is banned in repairs only', () {
      final rule = _rule('الحيازة');
      expect(rule.under, 'app/lib/src/features/repairs/');
      expect(banned('الحيازة', "'تزيد الحيازة بهذا الوزن مرة واحدة.'"), isTrue);
      expect(banned('الحيازة', "'تحرير الحيازة: 1.26 جرام'"), isTrue);
      // The folder is real, so the rule is not reading an empty set.
      expect(_app.any((line) => line.file.startsWith(rule.under)), isTrue);
      // Elsewhere the word still waits on its page reviews.
      expect(_open('حيازة').pattern, isNotNull);
    });

    test('a spelling with vowel marks is read without them', () {
      expect('مَشْغُولات'.replaceAll(_marks, ''), 'مشغولات');
      expect('أمـــانة'.replaceAll(_marks, ''), 'أمانة');
    });
  });
}
