class Game {
  final String id;
  final String title;
  final String executablePath;
  final String? coverImagePath;
  final String? saveDataPath;
  final DateTime createdAt;

  Game({
    required this.id,
    required this.title,
    required this.executablePath,
    this.coverImagePath,
    this.saveDataPath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'executablePath': executablePath,
      'coverImagePath': coverImagePath,
      'saveDataPath': saveDataPath,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'],
      title: json['title'],
      executablePath: json['executablePath'],
      coverImagePath: json['coverImagePath'],
      saveDataPath: json['saveDataPath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
    );
  }

  Game copyWith({
    String? id,
    String? title,
    String? executablePath,
    String? coverImagePath,
    String? saveDataPath,
    DateTime? createdAt,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      executablePath: executablePath ?? this.executablePath,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      saveDataPath: saveDataPath ?? this.saveDataPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
