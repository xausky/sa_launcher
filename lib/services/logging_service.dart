import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  static LoggingService get instance => _instance;
  
  final Logger _logger = Logger('SALauncher');
  late File _logFile;
  late IOSink _logSink;
  StreamSubscription<String>? _logSubscription;
  
  LoggingService._internal();
  
  Future<void> initialize() async {
    // 设置日志级别
    Logger.root.level = Level.ALL;
    
    // 获取临时目录
    final tempDir = await getTemporaryDirectory();
    final logFilePath = path.join(tempDir.path, 'sa_launcher-${DateTime.now().microsecondsSinceEpoch}.log');
    _logFile = File(logFilePath);
    
    // 创建日志文件（如果不存在）
    if (!await _logFile.exists()) {
      await _logFile.create(recursive: true);
    }
    
    // 打开日志文件用于写入
    _logSink = _logFile.openWrite(mode: FileMode.append);
    
    // 添加控制台日志处理器
    Logger.root.onRecord.listen((record) {
      // 输出到控制台
      debugPrint('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
      if (record.error != null) {
        debugPrint('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        debugPrint('StackTrace: ${record.stackTrace}');
      }
      
      // 输出到文件
      final logMessage = '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}\n';
      _logSink.write(logMessage);
      
      if (record.error != null) {
        _logSink.write('Error: ${record.error}\n');
      }
      if (record.stackTrace != null) {
        _logSink.write('StackTrace: ${record.stackTrace}\n');
      }
    });
    info('logging file at $logFilePath');
  }
  
  void info(String message) {
    _logger.info(message);
  }
  
  void warning(String message) {
    _logger.warning(message);
  }
  
  void severe(String message) {
    _logger.severe(message);
  }
  
  void fine(String message) {
    _logger.fine(message);
  }
  
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
  
  Future<void> dispose() async {
    await _logSink.close();
    await _logSubscription?.cancel();
  }
}