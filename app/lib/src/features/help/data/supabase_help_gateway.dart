import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/help_models.dart';

class SupabaseHelpGateway implements HelpGateway {
  const SupabaseHelpGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<HelpTopic>> listCatalog() async {
    try {
      final raw = await _client.rpc('list_help_catalog_v1');
      if (raw is! List) throw const HelpException(HelpFailure.unavailable);
      return raw.map(_parseTopic).toList(growable: false);
    } on HelpException {
      rethrow;
    } catch (_) {
      throw const HelpException(HelpFailure.unavailable);
    }
  }

  @override
  Future<PlatformAnnouncement?> getAnnouncement() async {
    try {
      final raw = await _client.rpc('get_platform_announcement_v1');
      if (raw == null) return null;
      if (raw is! Map) throw const HelpException(HelpFailure.unavailable);
      final map = Map<String, dynamic>.from(raw);
      final title = map['title_ar'];
      final body = map['body_ar'];
      if (title is! String || body is! String) {
        throw const HelpException(HelpFailure.unavailable);
      }
      final link = map['link_url'];
      return PlatformAnnouncement(
        titleAr: title,
        bodyAr: body,
        linkUrl: link is String ? link : null,
      );
    } on HelpException {
      rethrow;
    } catch (_) {
      throw const HelpException(HelpFailure.unavailable);
    }
  }

  HelpTopic _parseTopic(Object? value) {
    if (value is! Map) throw const HelpException(HelpFailure.unavailable);
    final map = Map<String, dynamic>.from(value);
    final id = map['id'];
    final title = map['title_ar'];
    final sort = map['sort_order'];
    final articlesRaw = map['articles'];
    if (id is! String || title is! String || sort is! num || articlesRaw is! List) {
      throw const HelpException(HelpFailure.unavailable);
    }
    return HelpTopic(
      id: id,
      titleAr: title,
      sortOrder: sort.toInt(),
      articles: articlesRaw.map(_parseArticle).toList(growable: false),
    );
  }

  HelpArticle _parseArticle(Object? value) {
    if (value is! Map) throw const HelpException(HelpFailure.unavailable);
    final map = Map<String, dynamic>.from(value);
    final id = map['id'];
    final title = map['title_ar'];
    final body = map['body_ar'];
    final sort = map['sort_order'];
    if (id is! String ||
        title is! String ||
        body is! String ||
        sort is! num) {
      throw const HelpException(HelpFailure.unavailable);
    }
    return HelpArticle(
      id: id,
      titleAr: title,
      bodyAr: body,
      sortOrder: sort.toInt(),
    );
  }
}
