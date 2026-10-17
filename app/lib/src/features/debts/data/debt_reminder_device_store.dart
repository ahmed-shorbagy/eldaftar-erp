import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../application/debt_reminder_device.dart';

final class SecureDeviceReminderStore implements DeviceReminderStore {
  const SecureDeviceReminderStore({
    this.storage = const FlutterSecureStorage(),
  });
  final FlutterSecureStorage storage;
  static const key = 'eldafttar.debt_native.installation.v1';
  @override
  Future<DeviceReminderManifest> load() async {
    final raw = await storage.read(key: key);
    if (raw == null) {
      final m = DeviceReminderManifest(installation: newIdempotencyKey());
      await save(m);
      return m;
    }
    final j = jsonDecode(raw);
    if (j is! Map ||
        j['version'] != 1 ||
        j['installation'] is! String ||
        !isUuid(j['installation'] as String) ||
        j['enabled'] is! bool ||
        j['requests'] is! List ||
        [
          j['user'],
          j['shop'],
          j['tap'],
        ].any((v) => v != null && (v is! String || !isUuid(v)))) {
      throw const FormatException('native_manifest');
    }
    List<DeviceReminderRequest> decode(Object? raw, {bool pending = true}) {
      if (raw is! List) throw const FormatException('native_manifest');
      final requests = <DeviceReminderRequest>[],
          ids = <int>{},
          tokens = <String>{};
      for (final e in raw) {
        if (e is! Map ||
            e['id'] is! int ||
            (e['id'] as int) < 0x40000000 ||
            (e['id'] as int) > 0x7fffffff ||
            (pending && !ids.add(e['id'] as int)) ||
            e['token'] is! String ||
            !isUuid(e['token'] as String) ||
            !tokens.add(e['token'] as String) ||
            !const {
              'standalone',
              'purchase_cash_payable',
              'gold_obligation',
            }.contains(e['source_kind']) ||
            e['source_id'] is! String ||
            !isUuid(e['source_id'] as String) ||
            e['fingerprint'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(e['fingerprint'] as String) ||
            e['at'] is! String ||
            DateTime.tryParse(e['at'] as String)?.isUtc != true ||
            e['applied'] is! bool) {
          throw const FormatException('native_manifest');
        }
        requests.add(
          DeviceReminderRequest(
            id: e['id'] as int,
            token: e['token'] as String,
            sourceKind: e['source_kind'] as String,
            sourceId: e['source_id'] as String,
            fingerprint: e['fingerprint'] as String,
            at: DateTime.parse(e['at'] as String),
            applied: e['applied'] as bool,
          ),
        );
      }
      return requests;
    }

    final requests = decode(j['requests']),
        routes = decode(j['routes'] ?? [], pending: false);
    if (routes.length > 64) throw const FormatException('native_manifest');
    if ((requests.isNotEmpty || routes.isNotEmpty) &&
        (j['user'] == null || j['shop'] == null)) {
      throw const FormatException('native_manifest');
    }
    return DeviceReminderManifest(
      installation: j['installation'] as String,
      userId: j['user'] as String?,
      shopId: j['shop'] as String?,
      enabled: j['enabled'] as bool,
      requests: requests,
      routes: routes,
      tapToken: j['tap'] as String?,
    );
  }

  @override
  Future<void> save(DeviceReminderManifest manifest) => storage.write(
    key: key,
    value: jsonEncode({
      'version': 1,
      'installation': manifest.installation,
      'user': manifest.userId,
      'shop': manifest.shopId,
      'enabled': manifest.enabled,
      'tap': manifest.tapToken,
      'requests': [
        for (final r in manifest.requests)
          {
            'id': r.id,
            'token': r.token,
            'source_kind': r.sourceKind,
            'source_id': r.sourceId,
            'fingerprint': r.fingerprint,
            'at': r.at.toUtc().toIso8601String(),
            'applied': r.applied,
          },
      ],
      'routes': [
        for (final r in manifest.routes)
          {
            'id': r.id,
            'token': r.token,
            'source_kind': r.sourceKind,
            'source_id': r.sourceId,
            'fingerprint': r.fingerprint,
            'at': r.at.toUtc().toIso8601String(),
            'applied': r.applied,
          },
      ],
    }),
  );
}
