class SaveBackup {
  final String id; // 对于 git 备份，这里存储 commit hash
  final String gameId;
  final String name; // 对于 git 备份，这里存储 commit message
  final String filePath; // 对于 git 备份，这里存储存档目录路径
  final DateTime createdAt;
  final int fileSize; // 对于 git 备份，这里可能为 0 或目录大小
  final String? commitHash; // git commit hash（新增字段）
  final String? author; // git commit 作者（新增字段）
  final bool isGitBackup; // 标识是否为 git 备份（新增字段）

  SaveBackup({
    required this.id,
    required this.gameId,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.fileSize,
    this.commitHash,
    this.author,
    this.isGitBackup = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gameId': gameId,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'fileSize': fileSize,
      'commitHash': commitHash,
      'author': author,
      'isGitBackup': isGitBackup,
    };
  }

  factory SaveBackup.fromJson(Map<String, dynamic> json) {
    return SaveBackup(
      id: json['id'],
      gameId: json['gameId'],
      name: json['name'],
      filePath: json['filePath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
      fileSize: json['fileSize'],
      commitHash: json['commitHash'],
      author: json['author'],
      isGitBackup: json['isGitBackup'] ?? false,
    );
  }

  SaveBackup copyWith({
    String? id,
    String? gameId,
    String? name,
    String? filePath,
    DateTime? createdAt,
    int? fileSize,
    String? commitHash,
    String? author,
    bool? isGitBackup,
  }) {
    return SaveBackup(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      fileSize: fileSize ?? this.fileSize,
      commitHash: commitHash ?? this.commitHash,
      author: author ?? this.author,
      isGitBackup: isGitBackup ?? this.isGitBackup,
    );
  }

  String get formattedFileSize {
    if (isGitBackup) {
      return 'Git 备份';
    }
    if (fileSize < 1024) {
      return '${fileSize}B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
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
      fileSize: 0, // Git 备份不需要文件大小
      commitHash: commitHash,
      author: author,
      isGitBackup: true,
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
}
