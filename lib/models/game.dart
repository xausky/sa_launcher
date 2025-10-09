class Game {
  final String id;
  final String title;
  final String executablePath;
  final String? coverImageFileName;
  final String? saveDataPath;
  final DateTime createdAt;

  // 游戏统计字段
  final Duration totalPlaytime;
  final DateTime? lastPlayedAt;
  final int playCount;

  Game({
    required this.id,
    required this.title,
    required this.executablePath,
    this.coverImageFileName,
    this.saveDataPath,
    required this.createdAt,
    this.totalPlaytime = Duration.zero,
    this.lastPlayedAt,
    this.playCount = 0,
  });

  // 用于云同步的JSON（不包含路径信息）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'coverImageFileName': coverImageFileName,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'totalPlaytimeSeconds': totalPlaytime.inSeconds,
      'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
      'playCount': playCount,
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
      'totalPlaytimeSeconds': totalPlaytime.inSeconds,
      'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
      'playCount': playCount,
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
      totalPlaytime: Duration(seconds: json['totalPlaytimeSeconds'] ?? 0),
      lastPlayedAt: json['lastPlayedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastPlayedAt'])
          : null,
      playCount: json['playCount'] ?? 0,
    );
  }

  // 从云端JSON和本地路径数据合并创建
  factory Game.fromCloudJsonWithLocalPaths(
    Map<String, dynamic> cloudJson,
    Map<String, Map<String, String>> localPaths,
  ) {
    final gameId = cloudJson['id'] as String;
    final gamePathData = localPaths[gameId] ?? <String, String>{};
    return Game(
      id: gameId,
      title: cloudJson['title'],
      executablePath: gamePathData['executablePath'] ?? '',
      coverImageFileName: cloudJson['coverImageFileName'],
      saveDataPath: gamePathData['saveDataPath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(cloudJson['createdAt']),
      totalPlaytime: Duration(seconds: cloudJson['totalPlaytimeSeconds'] ?? 0),
      lastPlayedAt: cloudJson['lastPlayedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(cloudJson['lastPlayedAt'])
          : null,
      playCount: cloudJson['playCount'] ?? 0,
    );
  }

  Game copyWith({
    String? id,
    String? title,
    String? executablePath,
    String? coverImageFileName,
    String? saveDataPath,
    DateTime? createdAt,
    Duration? totalPlaytime,
    DateTime? lastPlayedAt,
    int? playCount,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      executablePath: executablePath ?? this.executablePath,
      coverImageFileName: coverImageFileName ?? this.coverImageFileName,
      saveDataPath: saveDataPath ?? this.saveDataPath,
      createdAt: createdAt ?? this.createdAt,
      totalPlaytime: totalPlaytime ?? this.totalPlaytime,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playCount: playCount ?? this.playCount,
    );
  }

  // 获取格式化的总游戏时长
  String get formattedTotalPlaytime {
    final hours = totalPlaytime.inHours;
    final minutes = totalPlaytime.inMinutes % 60;

    if (hours > 0) {
      return '$hours小时$minutes分钟';
    } else {
      return '$minutes分钟';
    }
  }

  // 获取格式化的最后游玩时间
  String get formattedLastPlayedAt {
    if (lastPlayedAt == null) return '从未游玩';

    final now = DateTime.now();
    final difference = now.difference(lastPlayedAt!);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  // 添加游戏会话
  Game addPlaySession(Duration sessionDuration) {
    final now = DateTime.now();
    return copyWith(
      totalPlaytime: totalPlaytime + sessionDuration,
      lastPlayedAt: now,
      playCount: playCount + 1,
    );
  }
}
