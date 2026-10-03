import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/home_controller.dart';
import '../services/services.dart';
import '../state/app_state.dart';
import '../widgets/article_tile.dart';
import '../widgets/new_category_dialog.dart';
import '../widgets/quota_card.dart';
import 'article_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Services _s = context.read<Services>();
  late final HomeController _c = HomeController(_s.repo);
  late final Listenable _listenable = Listenable.merge([_c, _s.sync]);
  int _quotaTick = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _c.reload();
    await _s.sync.trySync();
    await _c.reload();
    if (mounted) setState(() => _quotaTick++);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('cutNsave'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: context.t('settings'),
            onPressed: () => _open(const SettingsScreen()),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.document_scanner, size: 28),
        label: Text(context.t('scan'), style: const TextStyle(fontSize: 20)),
        onPressed: () => _open(const ScanScreen()),
      ),
      body: ListenableBuilder(
        listenable: _listenable,
        builder: (context, _) {
          final names = {for (final c in _c.categories) c.id: c.name};
          return Column(
            children: [
              if (_s.sync.hasPendingFailure) _syncFailedBanner(context),
              QuotaCard(key: ValueKey(_quotaTick)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: context.t('search_hint'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _c.setQuery,
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _chip(
                      ChoiceChip(
                        label: Text(context.t('all')),
                        selected: _c.categoryId == null,
                        onSelected: (_) => _c.setCategory(null),
                      ),
                    ),
                    for (final cat in _c.categories)
                      _chip(
                        ChoiceChip(
                          label: Text(cat.name),
                          selected: _c.categoryId == cat.id,
                          onSelected: (_) => _c.setCategory(cat.id),
                        ),
                      ),
                    _chip(
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(context.t('new_category')),
                        onPressed: () async {
                          final created = await showNewCategoryDialog(context);
                          if (created != null) await _c.reload();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: _c.articles.isEmpty
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(context.t('no_articles'), textAlign: TextAlign.center),
                          ),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: _c.articles.length,
                          itemBuilder: (context, i) {
                            final a = _c.articles[i];
                            return ArticleTile(
                              article: a,
                              categoryName: names[a.categoryId],
                              onTap: () => _open(ArticleScreen(articleId: a.id)),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _syncFailedBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(context.t('sync_failed'), style: TextStyle(color: colors.onErrorContainer)),
          ),
          TextButton(onPressed: _refresh, child: Text(context.t('retry'))),
        ],
      ),
    );
  }

  Widget _chip(Widget chip) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: chip);
}
