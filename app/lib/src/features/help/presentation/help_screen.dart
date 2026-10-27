import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../domain/help_models.dart';

abstract final class HelpCopy {
  static const title = 'المساعدة';
  static const searchHint = 'ابحث في المواضيع والمقالات';
  static const empty = 'لا توجد مقالات مساعدة منشورة حاليًا.';
  static const loadError = 'تعذر تحميل المساعدة. حاول مجددًا.';
  static const retry = 'إعادة المحاولة';
  static const noMatch = 'لا نتائج مطابقة للبحث.';
  static const contactSupport = 'تواصل مع الدعم';
  static const contactSupportHint =
      'لم تجد ما تبحث عنه؟ أرسل استفسارك إلى فريق الدعم.';
}

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, required this.gateway, this.supportBuilder});

  final HelpGateway gateway;

  /// Builds the owner support screen; null when support is unavailable for
  /// this account.
  final WidgetBuilder? supportBuilder;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  List<HelpTopic>? _topics;
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await widget.gateway.listCatalog();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = HelpCopy.loadError;
        _loading = false;
      });
    }
  }

  List<HelpTopic> get _filtered {
    final topics = _topics ?? const <HelpTopic>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return topics;
    return topics
        .map((topic) {
          final articles = topic.articles
              .where(
                (a) =>
                    a.titleAr.toLowerCase().contains(q) ||
                    a.bodyAr.toLowerCase().contains(q),
              )
              .toList(growable: false);
          final topicMatch = topic.titleAr.toLowerCase().contains(q);
          if (!topicMatch && articles.isEmpty) return null;
          return HelpTopic(
            id: topic.id,
            titleAr: topic.titleAr,
            sortOrder: topic.sortOrder,
            articles: topicMatch ? topic.articles : articles,
          );
        })
        .whereType<HelpTopic>()
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(HelpCopy.title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('help-search'),
                  decoration: const InputDecoration(
                    labelText: HelpCopy.searchHint,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 12),
                if (widget.supportBuilder != null) ...[
                  _SupportEntry(
                    key: const Key('help-support-entry'),
                    emphasized:
                        !_loading && _error == null && _filtered.isEmpty,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: widget.supportBuilder!),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text(HelpCopy.retry),
                        ),
                      ],
                    ),
                  )
                else if ((_topics ?? const []).isEmpty)
                  const Expanded(child: Center(child: Text(HelpCopy.empty)))
                else if (_filtered.isEmpty)
                  const Expanded(child: Center(child: Text(HelpCopy.noMatch)))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final topic = _filtered[index];
                        return Card(
                          key: Key('help-topic-${topic.id}'),
                          child: ExpansionTile(
                            title: Text(
                              topic.titleAr,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            children: [
                              for (final article in topic.articles)
                                ListTile(
                                  key: Key('help-article-${article.id}'),
                                  title: Text(article.titleAr),
                                  trailing: const Icon(Icons.chevron_left),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            HelpArticleScreen(article: article),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportEntry extends StatelessWidget {
  const _SupportEntry({
    super.key,
    required this.emphasized,
    required this.onTap,
  });

  final bool emphasized;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        side: emphasized
            ? BorderSide(color: AppTokens.tableBorderFor(theme.brightness))
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(
          Icons.support_agent_outlined,
          color: emphasized ? theme.colorScheme.primary : null,
        ),
        title: Text(
          HelpCopy.contactSupport,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: emphasized ? theme.colorScheme.primary : null,
          ),
        ),
        subtitle: emphasized ? const Text(HelpCopy.contactSupportHint) : null,
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}

class HelpArticleScreen extends StatelessWidget {
  const HelpArticleScreen({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(article.titleAr)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              article.bodyAr,
              key: const Key('help-article-body'),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}
