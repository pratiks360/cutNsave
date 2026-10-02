import 'package:flutter/foundation.dart' hide Category;

import '../data/models.dart';
import '../data/repository.dart';

class HomeController extends ChangeNotifier {
  HomeController(this.repo);
  final Repository repo;

  List<Category> categories = [];
  List<Article> articles = [];
  String? categoryId;
  String query = '';

  Future<void> reload() async {
    categories = await repo.categories();
    articles = await repo.articles(categoryId: categoryId, query: query);
    notifyListeners();
  }

  Future<void> setCategory(String? id) {
    categoryId = id;
    return reload();
  }

  Future<void> setQuery(String q) {
    query = q;
    return reload();
  }
}
