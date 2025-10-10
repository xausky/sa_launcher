class SaveBackup {
  final String id; // commit hash
  final String gameId;
  final String name; // commit message
  final String filePath; // 存档目录路径
  final DateTime createdAt;
  final String commitHash; // git commit hash
  final String? author; // git commit 作者

  SaveBackup({
    required this.id,
    required this.gameId,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.commitHash,
    this.author,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gameId': gameId,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'commitHash': commitHash,
      'author': author,
    };
  }

  factory SaveBackup.fromJson(Map<String, dynamic> json) {
    return SaveBackup(
      id: json['id'],
      gameId: json['gameId'],
      name: json['name'],
      filePath: json['filePath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      commitHash: json['commitHash'],
      author: json['author'],
    );
  }

  SaveBackup copyWith({
    String? id,
    String? gameId,
    String? name,
    String? filePath,
    DateTime? createdAt,
    String? commitHash,
    String? author,
  }) {
    return SaveBackup(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      commitHash: commitHash ?? this.commitHash,
      author: author ?? this.author,
    );
  }

  String get formattedFileSize {
    return 'Git 备份';
  }

  /// 创建 Git 备份实例
  factory SaveBackup.fromGitCommit({
    required String gameId,
    required String saveDataPath,
    required String commitHash,
    required String message,
    required DateTime createdAt,
    String? author,
  }) {
    return SaveBackup(
      id: commitHash,
      gameId: gameId,
      name: message,
      filePath: saveDataPath,
      createdAt: createdAt,
      commitHash: commitHash,
      author: author,
    );
  }

  /// 检查是否为自动备份
  bool get isAutoBackup {
    return name == 'auto backup' || name.startsWith('auto backup');
  }

  /// 获取显示名称
  String get displayName {
    if (isAutoBackup) {
      return '自动备份';
    }
    return name;
  }

  /// 检查是否为 Git 备份（现在所有备份都是 Git 备份）
  bool get isGitBackup => true;
}
