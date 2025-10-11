import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'logging_service.dart';

/// Git 操作状态
enum GitOperationStatus {
  idle,
  running,
  success,
  error,
}

/// Git 操作信息
class GitOperation {
  final String id;
  final String command;
  final List<String> args;
  final String workingDirectory;
  final DateTime startTime;
  final GitOperationStatus status;
  final String? output;
  final String? error;
  final DateTime? endTime;

  GitOperation({
    required this.id,
    required this.command,
    required this.args,
    required this.workingDirectory,
    required this.startTime,
    required this.status,
    this.output,
    this.error,
    this.endTime,
  });

  GitOperation copyWith({
    String? id,
    String? command,
    List<String>? args,
    String? workingDirectory,
    DateTime? startTime,
    GitOperationStatus? status,
    String? output,
    String? error,
    DateTime? endTime,
  }) {
    return GitOperation(
      id: id ?? this.id,
      command: command ?? this.command,
      args: args ?? this.args,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      startTime: startTime ?? this.startTime,
      status: status ?? this.status,
      output: output ?? this.output,
      error: error ?? this.error,
      endTime: endTime ?? this.endTime,
    );
  }

  String get fullCommand => '$command ${args.join(' ')}';
}

/// Git 操作日志服务
class GitOperationService extends ChangeNotifier {
  static final GitOperationService _instance = GitOperationService._internal();
  factory GitOperationService() => _instance;
  GitOperationService._internal();

  final List<GitOperation> _operations = [];
  GitOperation? _currentOperation;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  List<GitOperation> get operations => List.unmodifiable(_operations);
  GitOperation? get currentOperation => _currentOperation;
  GitOperationStatus get currentStatus => _currentOperation?.status ?? GitOperationStatus.idle;
  bool get isRunning => currentStatus == GitOperationStatus.running;

  /// 执行 Git 命令并记录日志
  Future<ProcessResult> runGitCommand({
    required String command,
    required List<String> args,
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    final operationId = DateTime.now().millisecondsSinceEpoch.toString();
    final operation = GitOperation(
      id: operationId,
      command: command,
      args: args,
      workingDirectory: workingDirectory,
      startTime: DateTime.now(),
      status: GitOperationStatus.running,
    );

    _currentOperation = operation;
    _operations.insert(0, operation);
    notifyListeners();

    LoggingService.instance.info('开始执行 Git 命令: ${operation.fullCommand}');

    try {
      final process = await Process.start(
        command,
        args,
        workingDirectory: workingDirectory,
        environment: environment,
      );

      final stdout = <String>[];
      final stderr = <String>[];

      // 监听标准输出
      _stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdout.add(line);
        _updateOperationOutput(operationId, stdout.join('\n'));
        LoggingService.instance.info('Git stdout: $line');
      });

      // 监听标准错误
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderr.add(line);
        _updateOperationError(operationId, stderr.join('\n'));
        LoggingService.instance.warning('Git stderr: $line');
      });

      // 等待进程完成
      final exitCode = await process.exitCode;
      final result = ProcessResult(
        process.pid,
        exitCode,
        stdout.join('\n'),
        stderr.join('\n'),
      );

      // 更新操作状态
      final finalStatus = exitCode == 0 ? GitOperationStatus.success : GitOperationStatus.error;
      _updateOperationStatus(operationId, finalStatus, DateTime.now());

      LoggingService.instance.info(
          'Git 命令完成: ${operation.fullCommand}, 退出码: $exitCode');

      return result;
    } catch (e) {
      LoggingService.instance.logError('Git 命令执行失败', e);
      _updateOperationStatus(operationId, GitOperationStatus.error, DateTime.now());
      rethrow;
    } finally {
      await _stdoutSubscription?.cancel();
      await _stderrSubscription?.cancel();
      _stdoutSubscription = null;
      _stderrSubscription = null;
    }
  }

  /// 更新操作输出
  void _updateOperationOutput(String operationId, String output) {
    final index = _operations.indexWhere((op) => op.id == operationId);
    if (index != -1) {
      _operations[index] = _operations[index].copyWith(output: output);
      if (_currentOperation?.id == operationId) {
        _currentOperation = _operations[index];
      }
      notifyListeners();
    }
  }

  /// 更新操作错误
  void _updateOperationError(String operationId, String error) {
    final index = _operations.indexWhere((op) => op.id == operationId);
    if (index != -1) {
      _operations[index] = _operations[index].copyWith(error: error);
      if (_currentOperation?.id == operationId) {
        _currentOperation = _operations[index];
      }
      notifyListeners();
    }
  }

  /// 更新操作状态
  void _updateOperationStatus(String operationId, GitOperationStatus status, DateTime? endTime) {
    final index = _operations.indexWhere((op) => op.id == operationId);
    if (index != -1) {
      _operations[index] = _operations[index].copyWith(
        status: status,
        endTime: endTime,
      );
      if (_currentOperation?.id == operationId) {
        _currentOperation = _operations[index];
        if (status != GitOperationStatus.running) {
          _currentOperation = null;
        }
      }
      notifyListeners();
    }
  }

  /// 清除操作历史
  void clearHistory() {
    _operations.clear();
    _currentOperation = null;
    notifyListeners();
  }

  /// 获取操作历史（限制数量）
  List<GitOperation> getOperationHistory({int limit = 50}) {
    return _operations.take(limit).toList();
  }
}

/// Provider for GitOperationService
final gitOperationServiceProvider = Provider((ref) => GitOperationService());

/// Provider for current Git operation status
final gitOperationStatusProvider = Provider((ref) {
  final service = ref.watch(gitOperationServiceProvider);
  return service.currentStatus;
});

/// Provider for Git operations list
final gitOperationsProvider = Provider((ref) {
  final service = ref.watch(gitOperationServiceProvider);
  return service.operations;
});