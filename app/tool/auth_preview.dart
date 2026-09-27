// Local fake-auth preview for native keyboard review. Never imported by production.
import 'package:flutter/widgets.dart';
import '../integration_test/auth_review_test.dart' show AuthReviewHost;

void main() => runApp(const AuthReviewHost(preview: true));
