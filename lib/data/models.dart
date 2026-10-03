class Category {
  Category({
    required this.id,
    required this.libraryId,
    required this.name,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final String id;
  final String libraryId;
  final String name;
  final DateTime updatedAt;
  final bool deleted;

  Category copyWith({String? name, bool? deleted, DateTime? updatedAt}) => Category(
        id: id,
        libraryId: libraryId,
        name: name ?? this.name,
        deleted: deleted ?? this.deleted,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, Object?> toLocal({required bool dirty}) => {
        'id': id,
        'library_id': libraryId,
        'name': name,
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory Category.fromLocal(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        libraryId: m['library_id'] as String,
        name: m['name'] as String,
        updatedAt: DateTime.parse(m['updated_at'] as String),
        deleted: (m['deleted'] as int) == 1,
      );

  Map<String, Object?> toRemote() => {
        'id': id,
        'library_id': libraryId,
        'name': name,
        'deleted_at': deleted ? DateTime.now().toUtc().toIso8601String() : null,
        'client_updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Category.fromRemote(Map<String, dynamic> m) => Category(
        id: m['id'] as String,
        libraryId: m['library_id'] as String,
        name: m['name'] as String,
        updatedAt: DateTime.parse(m['updated_at'] as String),
        deleted: m['deleted_at'] != null,
      );
}

class Article {
  Article({
    required this.id,
    required this.libraryId,
    this.categoryId,
    this.imagePath,
    required this.originalText,
    required this.originalLang,
    this.englishText,
    this.englishDeclined = false,
    required DateTime scannedAt,
    this.createdBy,
    DateTime? updatedAt,
    this.deleted = false,
  })  : scannedAt = scannedAt.toUtc(),
        updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final String id;
  final String libraryId;
  final String? categoryId;
  final String? imagePath; // local file path, null until downloaded
  final String originalText;
  final String originalLang; // mr | hi | en
  final String? englishText;
  // True when englishText is null because the user deliberately declined
  // translation (turned off the translate toggle), as opposed to a genuine
  // translation attempt that is still pending/failed. Synced to the server
  // so every device/family member agrees on which case it is - a daughter
  // viewing an article her mom declined to translate shouldn't see a
  // "translate now" prompt either.
  final bool englishDeclined;
  final DateTime scannedAt;
  final String? createdBy;
  final DateTime updatedAt;
  final bool deleted;

  String get remoteImagePath => '$libraryId/$id.jpg';

  // Whether ArticleScreen should offer a "Translate now" retry: only when
  // English is genuinely missing because a translation attempt is
  // pending/failed, never when the user deliberately declined translation
  // (see englishDeclined) and never for an article that's already English.
  bool get needsTranslatePrompt =>
      originalLang != 'en' && englishText == null && !englishDeclined;

  Article copyWith({
    String? categoryId,
    String? imagePath,
    String? originalText,
    String? originalLang,
    String? englishText,
    bool clearEnglish = false,
    bool? englishDeclined,
    bool? deleted,
    DateTime? updatedAt,
  }) =>
      Article(
        id: id,
        libraryId: libraryId,
        categoryId: categoryId ?? this.categoryId,
        imagePath: imagePath ?? this.imagePath,
        originalText: originalText ?? this.originalText,
        originalLang: originalLang ?? this.originalLang,
        englishText: clearEnglish ? null : (englishText ?? this.englishText),
        englishDeclined: englishDeclined ?? this.englishDeclined,
        scannedAt: scannedAt,
        createdBy: createdBy,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, Object?> toLocal({required bool dirty}) => {
        'id': id,
        'library_id': libraryId,
        'category_id': categoryId,
        'image_path': imagePath,
        'original_text': originalText,
        'original_lang': originalLang,
        'english_text': englishText,
        'english_declined': englishDeclined ? 1 : 0,
        'scanned_at': scannedAt.toIso8601String(),
        'created_by': createdBy,
        'updated_at': updatedAt.toIso8601String(),
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory Article.fromLocal(Map<String, Object?> m) => Article(
        id: m['id'] as String,
        libraryId: m['library_id'] as String,
        categoryId: m['category_id'] as String?,
        imagePath: m['image_path'] as String?,
        originalText: m['original_text'] as String,
        originalLang: m['original_lang'] as String,
        englishText: m['english_text'] as String?,
        englishDeclined: (m['english_declined'] as int?) == 1,
        scannedAt: DateTime.parse(m['scanned_at'] as String),
        createdBy: m['created_by'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String),
        deleted: (m['deleted'] as int) == 1,
      );

  Map<String, Object?> toRemote() => {
        'id': id,
        'library_id': libraryId,
        'category_id': categoryId,
        'image_path': remoteImagePath,
        'original_text': originalText,
        'original_lang': originalLang,
        'english_text': englishText,
        'english_declined': englishDeclined,
        'scanned_at': scannedAt.toIso8601String(),
        'created_by': createdBy,
        'deleted_at': deleted ? DateTime.now().toUtc().toIso8601String() : null,
        'client_updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Article.fromRemote(Map<String, dynamic> m) => Article(
        id: m['id'] as String,
        libraryId: m['library_id'] as String,
        categoryId: m['category_id'] as String?,
        originalText: (m['original_text'] as String?) ?? '',
        originalLang: m['original_lang'] as String,
        englishText: m['english_text'] as String?,
        englishDeclined: m['english_declined'] as bool? ?? false,
        scannedAt: DateTime.parse(m['scanned_at'] as String),
        createdBy: m['created_by'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String),
        deleted: m['deleted_at'] != null,
      );
}
