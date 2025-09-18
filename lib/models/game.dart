class Game {
  final String id;
  final String title;
  final String executablePath;
  final String? coverImagePath;
  final DateTime createdAt;

  Game({
    required this.id,
    required this.title,
    required this.executablePath,
    this.coverImagePath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'executablePath': executablePath,
      'coverImagePath': coverImagePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'],
      title: json['title'],
      executablePath: json['executablePath'],
      coverImagePath: json['coverImagePath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
    );
  }

  Game copyWith({
    String? id,
    String? title,
    String? executablePath,
    String? coverImagePath,
    DateTime? createdAt,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      executablePath: executablePath ?? this.executablePath,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
