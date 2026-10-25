class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.titleAr,
    required this.bodyAr,
    required this.sortOrder,
  });

  final String id;
  final String titleAr;
  final String bodyAr;
  final int sortOrder;
}

class HelpTopic {
  const HelpTopic({
    required this.id,
    required this.titleAr,
    required this.sortOrder,
    required this.articles,
  });

  final String id;
  final String titleAr;
  final int sortOrder;
  final List<HelpArticle> articles;
}

class PlatformAnnouncement {
  const PlatformAnnouncement({
    required this.titleAr,
    required this.bodyAr,
    this.linkUrl,
  });

  final String titleAr;
  final String bodyAr;
  final String? linkUrl;
}

abstract class HelpGateway {
  Future<List<HelpTopic>> listCatalog();
  Future<PlatformAnnouncement?> getAnnouncement();
}

enum HelpFailure { unavailable }

class HelpException implements Exception {
  const HelpException(this.failure);
  final HelpFailure failure;
}
