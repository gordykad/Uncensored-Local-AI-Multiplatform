/// Represents a downloadable/loadable AI model from the catalog.
class AiModelInfo {
  final String id;
  final String name;
  final String filename;
  final String url;
  final double sizeGb;
  final int minRamGb;
  final String label; // UNCENSORED / STANDARD / CUSTOM
  final String badge; // RECOMMENDED, HERETIC, etc.
  final String systemPrompt;
  final bool recommended;
  // Ticket 25: capability tags from the classifier (chat / code /
  // vision / reasoning / uncensored / base). tagsSource 'manual'
  // means Kai hand-edited them — the classifier never overwrites.
  final List<String> tags;
  final String tagsSource;

  const AiModelInfo({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeGb,
    required this.minRamGb,
    required this.label,
    required this.badge,
    required this.systemPrompt,
    this.recommended = false,
    this.tags = const [],
    this.tagsSource = 'auto',
  });

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    return AiModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      filename: json['filename'] as String,
      url: json['url'] as String,
      sizeGb: (json['sizeGb'] as num).toDouble(),
      minRamGb: (json['minRamGb'] as num).toInt(),
      label: json['label'] as String? ?? 'STANDARD',
      badge: json['badge'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      recommended: json['recommended'] as bool? ?? false,
      tags:
          (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      tagsSource: json['tagsSource'] as String? ?? 'auto',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'filename': filename,
    'url': url,
    'sizeGb': sizeGb,
    'minRamGb': minRamGb,
    'label': label,
    'badge': badge,
    'systemPrompt': systemPrompt,
    'recommended': recommended,
    'tags': tags,
    'tagsSource': tagsSource,
  };

  /// True when this entry carries a real remote source URL it can be
  /// (re)downloaded from. File imports persist the literal 'local' — they
  /// have no source until the user attaches one (ticket 20).
  bool get hasRemoteUrl => url.startsWith('http');

  AiModelInfo copyWith({
    String? url,
    double? sizeGb,
    int? minRamGb,
    String? badge,
    String? name,
    String? label,
    List<String>? tags,
    String? tagsSource,
  }) {
    return AiModelInfo(
      id: id,
      name: name ?? this.name,
      filename: filename,
      url: url ?? this.url,
      sizeGb: sizeGb ?? this.sizeGb,
      minRamGb: minRamGb ?? this.minRamGb,
      label: label ?? this.label,
      badge: badge ?? this.badge,
      systemPrompt: systemPrompt,
      recommended: recommended,
      tags: tags ?? this.tags,
      tagsSource: tagsSource ?? this.tagsSource,
    );
  }

  bool get isUncensored => label == 'UNCENSORED';
  bool get isStandard => label == 'STANDARD';
  bool get isCustom => label == 'CUSTOM';
}
