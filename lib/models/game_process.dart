class GameProcessInfo {
  final String gameId;
  final String executableName;
  final int processId;
  final DateTime startTime;

  GameProcessInfo({
    required this.gameId,
    required this.executableName,
    required this.processId,
    required this.startTime,
  });

  GameProcessInfo copyWith({
    String? gameId,
    String? executableName,
    int? processId,
    DateTime? startTime,
  }) {
    return GameProcessInfo(
      gameId: gameId ?? this.gameId,
      executableName: executableName ?? this.executableName,
      processId: processId ?? this.processId,
      startTime: startTime ?? this.startTime,
    );
  }

  bool get isRunning => processId > 0;
}
