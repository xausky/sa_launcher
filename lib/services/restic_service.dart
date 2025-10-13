import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'app_data_service.dart';
import 'cloud_sync_config_service.dart';
import 'logging_service.dart';

// Backup 命令返回的模型类
class ResticBackupResult {
  final int totalFilesProcessed;
  final int totalBytesProcessed;
  final DateTime backupStart;
  final String snapshotId;

  ResticBackupResult({
    required this.totalFilesProcessed,
    required this.totalBytesProcessed,
    required this.backupStart,
    required this.snapshotId,
  });

  factory ResticBackupResult.fromJson(Map<String, dynamic> json) {
    return ResticBackupResult(
      totalFilesProcessed: json['total_files_processed'] as int,
      totalBytesProcessed: json['total_bytes_processed'] as int,
      backupStart: DateTime.parse(json['backup_start'] as String),
      snapshotId: json['snapshot_id'] as String,
    );
  }
}

// Snapshot 摘要信息模型类
class ResticSnapshotSummary {
  final int totalFilesProcessed;
  final int totalBytesProcessed;

  ResticSnapshotSummary({
    required this.totalFilesProcessed,
    required this.totalBytesProcessed,
  });

  factory ResticSnapshotSummary.fromJson(Map<String, dynamic> json) {
    return ResticSnapshotSummary(
      totalFilesProcessed: json['total_files_processed'] as int,
      totalBytesProcessed: json['total_bytes_processed'] as int,
    );
  }
}

// Snapshot 命令返回的模型类
class ResticSnapshot {
  final DateTime time;
  final ResticSnapshotSummary summary;
  final List<String> tags;
  final String id;

  ResticSnapshot({
    required this.time,
    required this.summary,
    required this.tags,
    required this.id,
  });

  factory ResticSnapshot.fromJson(Map<String, dynamic> json) {
    return ResticSnapshot(
      time: DateTime.parse(json['time'] as String),
      summary: ResticSnapshotSummary.fromJson(json['summary'] as Map<String, dynamic>),
      tags: List<String>.from(json['tags'] as List),
      id: json['id'] as String,
    );
  }
}


class ResticService {
  static const String _repoDirName = 'repo';
  static const String _mainDirName = 'main';
  static const String _resticPassword = 'PIBnoJCSHoaQG1'; // 硬编码密码

  // 获取本地 restic 仓库路径
  static Future<Directory> getLocalResticRepository() async {
    final appDataDir = await AppDataService.getAppDataDirectory();
    final repoDir = Directory(path.join(appDataDir.path, _repoDirName));
    if (!await repoDir.exists()) {
      await repoDir.create(recursive: true);
    }
    return repoDir;
  }

  // 获取主数据目录（app.json 和 covers 目录将移动到这里）
  static Future<Directory> getMainDataDirectory() async {
    final appDataDir = await AppDataService.getAppDataDirectory();
    final mainDir = Directory(path.join(appDataDir.path, _mainDirName));
    if (!await mainDir.exists()) {
      await mainDir.create(recursive: true);
    }
    return mainDir;
  }

  // 获取新的 app.json 文件路径
  static Future<File> getNewAppJsonFile() async {
    final mainDir = await getMainDataDirectory();
    return File(path.join(mainDir.path, 'app.json'));
  }

  // 获取新的游戏封面目录
  static Future<Directory> getNewGameCoversDirectory() async {
    final mainDir = await getMainDataDirectory();
    final coversDir = Directory(path.join(mainDir.path, 'covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    return coversDir;
  }

  static String _getResticPath() {
    // 获取当前工作目录
    Directory currentDir = Directory.current;

    // 构建 tools/restic.exe 的相对路径
    String resticRelativePath = path.join('tools', 'restic.exe');

    // 组合成绝对路径
    String resticAbsolutePath = path.join(currentDir.path, resticRelativePath);

    return resticAbsolutePath;
  }

  // 执行 restic 命令
  static Future<ProcessResult> _executeResticCommand(
    List<String> args, {
    Map<String, String>? environment,
        String? workingDirectory,
  }) async {
    final env = <String, String>{};
    
    // 设置硬编码的密码
    env['RESTIC_PASSWORD'] = _resticPassword;
    
    if (environment != null) {
      env.addAll(environment);
    }

    args.insert(0, '--retry-lock');
    args.insert(1, '10s');

    LoggingService.instance.info('执行 restic 命令: restic ${args.join(' ')}');

    path.join('tools', 'restic.exe');


    
    final resp = await Process.run(
      _getResticPath(),
      args,
      environment: env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      workingDirectory: workingDirectory,
    );

    if(resp.exitCode != 0) {
      LoggingService.instance.info('restic 命令响应 ${resp.stdout} --- ${resp.stderr}');
    }
    return resp;
  }

  // 初始化本地 restic 仓库
  static Future<bool> initLocalRepository() async {
    try {
      final repoDir = await getLocalResticRepository();
      
      // 初始化仓库
      final result = await _executeResticCommand(
        ['init', '--repo', repoDir.path],
      );
      
      if (result.exitCode == 0) {
        LoggingService.instance.info('本地 restic 仓库初始化成功');
        return true;
      } else {
        LoggingService.instance.info('本地 restic 仓库初始化失败: ${result.stderr}');
        return false;
      }
    } catch (e) {
      LoggingService.instance.info('初始化本地仓库异常: $e');
      return false;
    }
  }

  // 初始化远程 S3 restic 仓库
  static Future<bool> initRemoteRepository({
    required CloudSyncConfig cloudConfig,
  }) async {
    try {
      // 构建 S3 仓库 URL
      final s3Repo = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
      
      // 设置 S3 环境变量
      final env = <String, String>{
        'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
        'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
      };
      
      // 初始化仓库
      final result = await _executeResticCommand(
        ['init', '--repo', s3Repo],
        environment: env,
      );
      
      if (result.exitCode == 0) {
        LoggingService.instance.info('远程 restic 仓库初始化成功');
        return true;
      } else {
        if (result.stderr.toString().contains("already exists")) {
          // 已经存在仓库也算初始化成功
          return true;
        }
        LoggingService.instance.info('远程 restic 仓库初始化失败: ${result.stderr}');
        return false;
      }
    } catch (e) {
      LoggingService.instance.info('初始化远程仓库异常: $e');
      return false;
    }
  }

  // 创建备份
  static Future<ResticBackupResult?> createBackup({
    required String backupPath,
    required List<String> tags,
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
  }) async {
    try {
      String repoPath;
      Map<String, String>? env;
      
      if (useRemote && cloudConfig != null) {
        repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
        env = <String, String>{
          'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
          'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
        };
      } else {
        final repoDir = await getLocalResticRepository();
        repoPath = repoDir.path;
        env = null;
      }
      
      final args = <String>[
        '--repo', repoPath,
        'backup', '.',
        '--json',
        '--no-scan',
      ];
      
      // 添加标签
      for (final tag in tags) {
        args.addAll(['--tag', tag]);
      }
      
      final result = await _executeResticCommand(
        args,
        environment: env,
        workingDirectory: backupPath
      );
      
      if (result.exitCode == 0) {
        // 解析 JSON 输出获取备份结果
        final output = _getLastNonEmptyLine(result.stdout);
        return ResticBackupResult.fromJson(jsonDecode(output!));
      } else {
        LoggingService.instance.info('创建备份失败: ${result.stderr}');
      }
      
      return null;
    } catch (e) {
      LoggingService.instance.info('创建备份异常: $e');
      return null;
    }
  }

  static Future<ResticSnapshot?> getLatestSnapshot({
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
    String? tag,
  }) async {
    final snapshots = await listSnapshots(useRemote: useRemote, cloudConfig: cloudConfig, tag: tag, latest: 1);
    if(snapshots.isEmpty) {
      return null;
    }
    snapshots.sort((a, b) => b.time.compareTo(a.time));
    return snapshots.first;
  }

  // 列出快照
  static Future<List<ResticSnapshot>> listSnapshots({
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
    String? tag,
    int? latest,
  }) async {
    try {
      String repoPath;
      Map<String, String>? env;
      
      if (useRemote && cloudConfig != null) {
        repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
        env = <String, String>{
          'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
          'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
        };
      } else {
        final repoDir = await getLocalResticRepository();
        repoPath = repoDir.path;
        env = null;
      }
      
      final args = <String>[
        '--repo', repoPath,
        'snapshots',
        '--json',
      ];

      if(latest != null) {
        args.addAll(['--latest', latest.toString()]);
      }
      
      if (tag != null) {
        args.addAll(['--tag', tag]);
      }
      
      final result = await _executeResticCommand(
        args,
        environment: env,
      );
      
      if (result.exitCode == 0) {
        return (jsonDecode(result.stdout.toString()) as List<dynamic>).map((e) => ResticSnapshot.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        LoggingService.instance.info('列出快照失败: ${result.stderr}');
        return [];
      }
    } catch (e) {
      LoggingService.instance.info('列出快照异常: $e');
      return [];
    }
  }

  // 恢复备份
  static Future<bool> restoreBackup({
    required String snapshotId,
    required String targetPath,
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
  }) async {
    try {
      String repoPath;
      Map<String, String>? env;
      
      if (useRemote && cloudConfig != null) {
        repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
        env = <String, String>{
          'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
          'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
        };
      } else {
        final repoDir = await getLocalResticRepository();
        repoPath = repoDir.path;
        env = null;
      }
      
      final result = await _executeResticCommand(
        [
          '--repo', repoPath,
          'restore', snapshotId,
          '--delete',
          '--target', targetPath,
        ],
        environment: env,
      );
      
      if (result.exitCode == 0) {
        LoggingService.instance.info('恢复备份成功');
        return true;
      } else {
        LoggingService.instance.info('恢复备份失败: ${result.stderr}');
        return false;
      }
    } catch (e) {
      LoggingService.instance.info('恢复备份异常: $e');
      return false;
    }
  }

  static Future<bool> cleanSnapshot({List<String>? tags, keep = 1, bool useRemote = false, CloudSyncConfig? cloudConfig}) async {
    String repoPath;
    Map<String, String>? env;

    if (useRemote && cloudConfig != null) {
      repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
      env = <String, String>{
        'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
        'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
      };
    } else {
      final repoDir = await getLocalResticRepository();
      repoPath = repoDir.path;
      env = null;
    }
    final List<String> args = [
      '--repo', repoPath,
      'forget',
      '--keep-last', keep.toString()
    ];
    if(tags != null) {
      for (var value in tags) {
        args.add('--tag');
        args.add(value);
      }
    }

    final result = await _executeResticCommand(
      args,
      environment: env,
    );

    if (result.exitCode == 0) {
      await _executeResticCommand(
        ['--repo', repoPath, 'prune'],
        environment: env,
      );
      return true;
    } else {
      LoggingService.instance.info('清理快照失败: ${result.stderr}');
      return false;
    }
}

  static Future<bool> deleteSnapshot({
    required String snapshotId,
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
  }) async {
    return await deleteSnapshots(ids: [snapshotId], useRemote: useRemote, cloudConfig: cloudConfig);
  }


  // 删除快照
  static Future<bool> deleteSnapshots({
    required List<String> ids,
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
  }) async {
    try {
      String repoPath;
      Map<String, String>? env;
      
      if (useRemote && cloudConfig != null) {
        repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
        env = <String, String>{
          'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
          'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
        };
      } else {
        final repoDir = await getLocalResticRepository();
        repoPath = repoDir.path;
        env = null;
      }
      
      final result = await _executeResticCommand(
        [
          '--repo', repoPath,
          'forget', ...ids,
        ],
        environment: env,
      );
      
      if (result.exitCode == 0) {
        return true;
      } else {
        LoggingService.instance.info('删除快照失败: ${result.stderr}');
        return false;
      }
    } catch (e) {
      LoggingService.instance.info('删除快照异常: $e');
      return false;
    }
  }

  // 检查仓库状态
  static Future<bool> checkRepository({
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
  }) async {
    try {
      String repoPath;
      Map<String, String>? env;
      
      if (useRemote && cloudConfig != null) {
        repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
        env = <String, String>{
          'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
          'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
        };
      } else {
        final repoDir = await getLocalResticRepository();
        repoPath = repoDir.path;
        env = null;
      }
      
      final result = await _executeResticCommand(
        [
          '--repo', repoPath,
          'check',
        ],
        environment: env,
      );
      
      return result.exitCode == 0;
    } catch (e) {
      LoggingService.instance.info('检查仓库异常: $e');
      return false;
    }
  }

  // 解锁仓库（如果需要）
  static Future<bool> unlockRepository({
    bool useRemote = false,
    CloudSyncConfig? cloudConfig,
  }) async {
    try {
      String repoPath;
      Map<String, String>? env;
      
      if (useRemote && cloudConfig != null) {
        repoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
        env = <String, String>{
          'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
          'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
        };
      } else {
        final repoDir = await getLocalResticRepository();
        repoPath = repoDir.path;
        env = null;
      }
      
      final result = await _executeResticCommand(
        [
          '--repo', repoPath,
          'unlock',
        ],
        environment: env,
      );
      
      return result.exitCode == 0;
    } catch (e) {
      LoggingService.instance.info('解锁仓库异常: $e');
      return false;
    }
  }

  static Future<bool> uploadRepository(CloudSyncConfig cloudConfig) async {
    final remoteRepoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
    final remoteEnv = <String, String>{
      'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
      'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
    };
    final localRepoPath = (await getLocalResticRepository()).path;
    final result = await _executeResticCommand(['--repo', remoteRepoPath, 'copy', '--from-repo', localRepoPath, '--from-password-command', "cmd /c 'echo $_resticPassword'"], environment: remoteEnv);
    return result.exitCode == 0;
  }

  static Future<bool> downloadRepository(CloudSyncConfig cloudConfig, {bool delete = false}) async {
    final remoteRepoPath = 's3:${cloudConfig.endPoint}/${cloudConfig.bucket}/${cloudConfig.objectPath}';
    final remoteEnv = <String, String>{
      'AWS_ACCESS_KEY_ID': cloudConfig.accessKey,
      'AWS_SECRET_ACCESS_KEY': cloudConfig.secretKey,
    };
    final localRepoPath = (await getLocalResticRepository()).path;

    // 从远程仓库复制快照到本地仓库
    final result = await _executeResticCommand([
      '--repo',
      localRepoPath,
      'copy',
      '--from-repo',
      remoteRepoPath,
      '--from-password-command',
      "cmd /c 'echo $_resticPassword'"
    ], environment: remoteEnv);

    if (result.exitCode != 0) {
      LoggingService.instance.info('从远程仓库复制快照失败: ${result.stderr}');
      return false;
    }

    // 如果不需要删除本地多余的快照，直接返回成功
    if (!delete) {
      return true;
    }

    // 获取本地和远程的快照列表
    final localSnapshots = await listSnapshots();
    final remoteSnapshots = await listSnapshots(useRemote: true, cloudConfig: cloudConfig);

    // 提取远程快照ID集合
    final remoteSnapshotTimes = remoteSnapshots.map((snapshot) => snapshot.time).toSet();

    // 找出远程不存在但本地存在的快照
    final snapshotsToDelete = localSnapshots.where((e) => !remoteSnapshotTimes.contains(e.time)).map((e) => e.id).toList();

    if(snapshotsToDelete.isEmpty) {
      return true;
    }

    await deleteSnapshots(ids: snapshotsToDelete);

    return true;
  }


  static String? _getLastNonEmptyLine(String text) {
    // 1. 将字符串按行分割成列表
    // 使用 \r?\n 来处理不同操作系统的换行符（\n, \r\n）
    // split() 可能会在末尾产生一个空字符串，这通常在后续处理中被忽略或剔除
    List<String> lines = text.split(RegExp(r'\r?\n'));

    // 2. 从后往前遍历列表
    for (int i = lines.length - 1; i >= 0; i--) {
      String line = lines[i];

      // 3. 检查当前行是否为非空行
      // trim() 方法用于移除字符串两端的空白字符（包括空格、制表符、换行符等）。
      // isNotEmpty 检查移除空白后字符串是否还有内容。
      if (line.trim().isNotEmpty) {
        // 找到了，返回该行原始内容
        return line;
      }
    }

    // 如果所有行都是空行或字符串本身为空，则返回 null (或您可以返回空字符串 "")
    return null;
  }

}