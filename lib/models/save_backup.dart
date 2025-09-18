class SaveBackup {
  final String id;
  final String gameId;
  final String name;
  final String filePath;
  final DateTime createdAt;
  final int fileSize;

  SaveBackup({
    required this.id,
    required this.gameId,
    required this.name,
    required this.filePath,
    required this.createdAt,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gameId': gameId,
      'name': name,
      'filePath': filePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'fileSize': fileSize,
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
    );
  }

  SaveBackup copyWith({
    String? id,
    String? gameId,
    String? name,
    String? filePath,
    DateTime? createdAt,
    int? fileSize,
  }) {
    return SaveBackup(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  String get formattedFileSize {
    if (fileSize < 1024) {
      return '${fileSize}B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }
}
