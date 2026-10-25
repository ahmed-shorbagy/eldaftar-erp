import 'app_version_policy.dart';

abstract class AppVersionGateway {
  Future<AppVersionSnapshot> getPolicy();
}
