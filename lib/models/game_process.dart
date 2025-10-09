class GameProcessInfo {
  final String gameId;
  final String executableName;
  final int processId; // 主进程ID
  final DateTime startTime;
  final Set<int> processIds; // 所有相关进程ID集合，包括主进程

  GameProcessInfo({
    required this.gameId,
    required this.executableName,
    required this.processId,
    required this.startTime,
    Set<int>? processIds,
  }) : processIds = processIds ?? {processId};

  GameProcessInfo copyWith({
    String? gameId,
    String? executableName,
    int? processId,
    DateTime? startTime,
    Set<int>? processIds,
  }) {
    return GameProcessInfo(
      gameId: gameId ?? this.gameId,
      executableName: executableName ?? this.executableName,
      processId: processId ?? this.processId,
      startTime: startTime ?? this.startTime,
      processIds: processIds ?? this.processIds,
    );
  }

  // 添加进程ID
  GameProcessInfo addProcessId(int pid) {
    final newProcessIds = Set<int>.from(processIds)..add(pid);
    return copyWith(processIds: newProcessIds);
  }

  // 移除进程ID
  GameProcessInfo removeProcessId(int pid) {
    final newProcessIds = Set<int>.from(processIds)..remove(pid);
    return copyWith(processIds: newProcessIds);
  }

  bool get isRunning => processIds.isNotEmpty;
  int get processCount => processIds.length;
}
