class FileModification {
  final String filePath;
  final int modificationCount;
  final DateTime firstModified;
  final DateTime lastModified;

  FileModification({
    required this.filePath,
    required this.modificationCount,
    required this.firstModified,
    required this.lastModified,
  });

  FileModification copyWith({
    String? filePath,
    int? modificationCount,
    DateTime? firstModified,
    DateTime? lastModified,
  }) {
    return FileModification(
      filePath: filePath ?? this.filePath,
      modificationCount: modificationCount ?? this.modificationCount,
      firstModified: firstModified ?? this.firstModified,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  // 增加修改次数
  FileModification incrementCount() {
    return copyWith(
      modificationCount: modificationCount + 1,
      lastModified: DateTime.now(),
    );
  }

  // 获取文件名
  String get fileName {
    return filePath.split('\\').last;
  }

  // 获取目录路径
  String get directoryPath {
    final lastSeparator = filePath.lastIndexOf('\\');
    if (lastSeparator == -1) return filePath;
    return filePath.substring(0, lastSeparator);
  }

  @override
  String toString() {
    return 'FileModification(filePath: $filePath, modificationCount: $modificationCount, firstModified: $firstModified, lastModified: $lastModified)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileModification && other.filePath == filePath;
  }

  @override
  int get hashCode => filePath.hashCode;
}

class FileTrackingSession {
  final String gameId;
  final DateTime startTime;
  final DateTime? endTime;
  final Map<String, FileModification> fileModifications;

  FileTrackingSession({
    required this.gameId,
    required this.startTime,
    this.endTime,
    Map<String, FileModification>? fileModifications,
  }) : fileModifications = fileModifications ?? {};

  FileTrackingSession copyWith({
    String? gameId,
    DateTime? startTime,
    DateTime? endTime,
    Map<String, FileModification>? fileModifications,
  }) {
    return FileTrackingSession(
      gameId: gameId ?? this.gameId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      fileModifications: fileModifications ?? this.fileModifications,
    );
  }

  // 添加文件修改记录
  FileTrackingSession addFileModification(String filePath) {
    final now = DateTime.now();
    final newModifications = Map<String, FileModification>.from(
      fileModifications,
    );

    if (newModifications.containsKey(filePath)) {
      // 文件已存在，增加修改次数
      newModifications[filePath] = newModifications[filePath]!.incrementCount();
    } else {
      // 新文件，创建记录
      newModifications[filePath] = FileModification(
        filePath: filePath,
        modificationCount: 1,
        firstModified: now,
        lastModified: now,
      );
    }

    return copyWith(fileModifications: newModifications);
  }

  // 结束追踪会话
  FileTrackingSession endSession() {
    return copyWith(endTime: DateTime.now());
  }

  // 获取修改的文件列表，按修改次数排序
  List<FileModification> get sortedModifications {
    final modifications = fileModifications.values.toList();
    modifications.sort(
      (a, b) => b.modificationCount.compareTo(a.modificationCount),
    );
    return modifications;
  }

  // 获取总修改次数
  int get totalModifications {
    return fileModifications.values.fold(
      0,
      (sum, mod) => sum + mod.modificationCount,
    );
  }

  // 获取修改的文件数量
  int get modifiedFileCount => fileModifications.length;

  // 会话是否已结束
  bool get isEnded => endTime != null;

  // 会话持续时间
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}
