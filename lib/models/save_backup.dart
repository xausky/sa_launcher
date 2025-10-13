class SaveBackup {
  final String id;
  final String gameId;
  final String name;
  final DateTime createdAt;
  final int fileSize;

  SaveBackup({
    required this.id,
    required this.gameId,
    required this.name,
    required this.createdAt,
    required this.fileSize,
  });

  SaveBackup copyWith({
    String? id,
    String? gameId,
    String? name,
    DateTime? createdAt,
    int? fileSize,
  }) {
    return SaveBackup(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      name: name ?? this.name,
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