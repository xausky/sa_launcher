class Game {
  final String id;
  final String title;
  final String executablePath;
  final String? coverImageFileName;
  final String? saveDataPath;
  final DateTime createdAt;

  Game({
    required this.id,
    required this.title,
    required this.executablePath,
    this.coverImageFileName,
    this.saveDataPath,
    required this.createdAt,
  });

  // 用于云同步的JSON（不包含路径信息）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'coverImageFileName': coverImageFileName,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  // 用于本地存储的完整JSON（包含路径信息）
  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'title': title,
      'executablePath': executablePath,
      'coverImageFileName': coverImageFileName,
      'saveDataPath': saveDataPath,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  // 从完整JSON创建（包含路径信息）
  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'],
      title: json['title'],
      executablePath: json['executablePath'] ?? '',
      coverImageFileName: json['coverImageFileName'],
      saveDataPath: json['saveDataPath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
    );
  }

  // 从云端JSON和本地路径数据合并创建
  factory Game.fromCloudJsonWithLocalPaths(
    Map<String, dynamic> cloudJson,
    Map<String, String> localPaths,
  ) {
    final gameId = cloudJson['id'] as String;
    return Game(
      id: gameId,
      title: cloudJson['title'],
      executablePath: localPaths['${gameId}_executablePath'] ?? '',
      coverImageFileName: cloudJson['coverImageFileName'],
      saveDataPath: localPaths['${gameId}_saveDataPath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(cloudJson['createdAt']),
    );
  }

  Game copyWith({
    String? id,
    String? title,
    String? executablePath,
    String? coverImageFileName,
    String? saveDataPath,
    DateTime? createdAt,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      executablePath: executablePath ?? this.executablePath,
      coverImageFileName: coverImageFileName ?? this.coverImageFileName,
      saveDataPath: saveDataPath ?? this.saveDataPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
