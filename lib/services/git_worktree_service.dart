import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'app_data_service.dart';

/// Git Worktree 服务类
/// 用于管理基于 git worktree 的存档和备份系统
class GitWorktreeService {
  /// 初始化启动器数据目录的 git 仓库
  static Future<bool> initMainRepository() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();
      final gitDir = Directory(path.join(appDataDir.path, '.git'));

      // 如果已经是 git 仓库，直接返回成功
      if (await gitDir.exists()) {
        debugPrint('Git 仓库已存在: ${appDataDir.path}');
        return true;
      }

      // 初始化 git 仓库
      final initResult = await Process.run('git', [
        'init',
      ], workingDirectory: appDataDir.path);

      if (initResult.exitCode != 0) {
        debugPrint('Git 初始化失败: ${initResult.stderr}');
        return false;
      }

      // 配置用户信息（如果没有全局配置）
      await _configureGitUser(appDataDir.path);

      // 创建初始提交
      await _createInitialCommit(appDataDir.path);

      debugPrint('Git 仓库初始化成功: ${appDataDir.path}');
      return true;
    } catch (e) {
      debugPrint('初始化 Git 仓库失败: $e');
      return false;
    }
  }

  /// 配置 git 用户信息
  static Future<void> _configureGitUser(String repoPath) async {
    try {
      // 检查是否已有用户配置
      final nameResult = await Process.run('git', [
        'config',
        'user.name',
      ], workingDirectory: repoPath);

      if (nameResult.exitCode != 0) {
        // 设置默认用户信息
        await Process.run('git', [
          'config',
          'user.name',
          'SA Launcher',
        ], workingDirectory: repoPath);

        await Process.run('git', [
          'config',
          'user.email',
          'sa-launcher@local',
        ], workingDirectory: repoPath);
      }
    } catch (e) {
      debugPrint('配置 Git 用户信息失败: $e');
    }
  }

  /// 创建初始提交
  static Future<void> _createInitialCommit(String repoPath) async {
    try {
      // 创建 .gitignore 文件
      final gitignoreFile = File(path.join(repoPath, '.gitignore'));
      await gitignoreFile.writeAsString('''
# 忽略临时文件
*.tmp
*.temp
*.log

# 忽略系统文件
.DS_Store
Thumbs.db
''');

      // 添加文件到暂存区
      await Process.run('git', ['add', '.'], workingDirectory: repoPath);

      // 创建初始提交
      await Process.run('git', [
        'commit',
        '-m',
        'Initial commit',
      ], workingDirectory: repoPath);
    } catch (e) {
      debugPrint('创建初始提交失败: $e');
    }
  }

  /// 检查存档目录是否已被 git worktree 管理
  static Future<bool> isWorktreeManaged(String saveDataPath) async {
    try {
      final gitFile = File(path.join(saveDataPath, '.git'));
      if (!await gitFile.exists()) {
        return false;
      }

      // 检查 .git 文件内容是否指向 worktree
      final gitContent = await gitFile.readAsString();
      return gitContent.trim().startsWith('gitdir:');
    } catch (e) {
      debugPrint('检查 worktree 管理状态失败: $e');
      return false;
    }
  }

  /// 为游戏创建 git worktree
  static Future<bool> createWorktreeForGame(
    String gameId,
    String saveDataPath,
  ) async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      // 确保主仓库已初始化
      if (!await initMainRepository()) {
        return false;
      }

      // 检查是否已经被管理
      if (await isWorktreeManaged(saveDataPath)) {
        debugPrint('存档目录已被 worktree 管理: $saveDataPath');
        return true;
      }

      // 创建 worktree 分支和目录
      // 如果 worktree 已经存在，先删除
      final worktreeDir = Directory(
        path.join(appDataDir.path, '.git', 'worktrees', gameId),
      );
      if (await worktreeDir.exists()) {
        final gitdirFile = File(path.join(worktreeDir.path, 'gitdir'));
        if (await gitdirFile.exists()) {
          String worktreePath = (await gitdirFile.readAsString()).trim();
          // 兼容 gitdir 文件内容可能带有换行和空格
          worktreePath = worktreePath.replaceAll(RegExp(r'[\r\n]'), '').trim();
          // 只会是 /.git 结尾
          if (worktreePath.endsWith('/.git')) {
            worktreePath = worktreePath.substring(0, worktreePath.length - 5);
          }
          final removeResult = await Process.run('git', [
            'worktree',
            'remove',
            '-f',
            worktreePath,
          ], workingDirectory: appDataDir.path);
          if (removeResult.exitCode != 0) {
            debugPrint('删除已存在的 worktree 失败: ${removeResult.stderr}');
            return false;
          }
        }
      }

      final worktreeResult = await Process.run('git', [
        'worktree',
        'add',
        '-B',
        gameId,
        gameId,
      ], workingDirectory: appDataDir.path);

      if (worktreeResult.exitCode != 0) {
        debugPrint('创建 worktree 失败: ${worktreeResult.stderr}');
        return false;
      }

      // 实现 hack 方法重定向 worktree
      if (!await _redirectWorktree(gameId, saveDataPath)) {
        return false;
      }

      debugPrint('为游戏 $gameId 创建 worktree 成功');
      return true;
    } catch (e) {
      debugPrint('创建 worktree 失败: $e');
      return false;
    }
  }

  /// 使用 hack 方法重定向 worktree 到存档目录
  static Future<bool> _redirectWorktree(
    String gameId,
    String saveDataPath,
  ) async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();
      final worktreePath = path.join(appDataDir.path, gameId);
      final worktreeGitDir = path.join(
        appDataDir.path,
        '.git',
        'worktrees',
        gameId,
      );

      // 确保存档目录存在
      final saveDataDir = Directory(saveDataPath);
      if (!await saveDataDir.exists()) {
        await saveDataDir.create(recursive: true);
      }

      // 1. 更新 .git/worktrees/<gameId>/gitdir 文件
      final gitdirFile = File(path.join(worktreeGitDir, 'gitdir'));
      final saveDataGitPath = path
          .join(saveDataPath, '.git')
          .replaceAll('\\', '/');
      await gitdirFile.writeAsString('$saveDataGitPath\n');

      // 2. 在存档目录创建 .git 文件，指向 worktree 目录
      final saveDataGitFile = File(saveDataGitPath);
      await saveDataGitFile.writeAsString(
        'gitdir: $worktreeGitDir\n'.replaceAll('\\', '/'),
      );

      // 3. 删除原orktree 目录
      final originalWorktreeDir = Directory(worktreePath);
      await originalWorktreeDir.delete(recursive: true);
      debugPrint('Worktree 重定向成功: $saveDataPath');
      return true;
    } catch (e) {
      debugPrint('重定向 worktree 失败: $e');
      return false;
    }
  }

  /// 在存档目录创建备份（git commit）
  static Future<String?> createBackup(
    String saveDataPath,
    String message,
  ) async {
    try {
      // 检查是否为 git worktree 管理的目录
      if (!await isWorktreeManaged(saveDataPath)) {
        debugPrint('存档目录未被 git worktree 管理: $saveDataPath');
        return null;
      }

      // 添加所有变更到暂存区
      final addResult = await Process.run('git', [
        'add',
        '.',
      ], workingDirectory: saveDataPath);

      if (addResult.exitCode != 0) {
        debugPrint('Git add 失败: ${addResult.stderr}');
        return null;
      }

      // 检查是否有变更需要提交
      final statusResult = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: saveDataPath);

      if (statusResult.stdout.toString().trim().isEmpty) {
        debugPrint('没有变更需要提交');
        return null;
      }

      // 创建提交
      final commitResult = await Process.run('git', [
        'commit',
        '-m',
        message,
      ], workingDirectory: saveDataPath);

      if (commitResult.exitCode != 0) {
        debugPrint('Git commit 失败: ${commitResult.stderr}');
        return null;
      }

      // 获取最新提交的 hash
      final hashResult = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: saveDataPath);

      if (hashResult.exitCode == 0) {
        final commitHash = hashResult.stdout.toString().trim();
        debugPrint('备份创建成功，提交 hash: $commitHash');
        return commitHash;
      }

      return null;
    } catch (e) {
      debugPrint('创建 Git 备份失败: $e');
      return null;
    }
  }

  /// 获取备份列表（git log）
  static Future<List<Map<String, dynamic>>> getBackupList(
    String saveDataPath,
  ) async {
    try {
      if (!await isWorktreeManaged(saveDataPath)) {
        return [];
      }

      // 使用 git log 获取提交历史，格式化输出
      final logResult = await Process.run('git', [
        'log',
        '--pretty=format:%H|%s|%ai|%an',
        '--date=iso',
      ], workingDirectory: saveDataPath);

      if (logResult.exitCode != 0) {
        debugPrint('Git log 失败: ${logResult.stderr}');
        return [];
      }

      final lines = logResult.stdout.toString().trim().split('\n');
      final backups = <Map<String, dynamic>>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final parts = line.split('|');
        if (parts.length >= 4) {
          final hash = parts[0];
          final message = parts[1];
          final dateStr = parts[2];
          final author = parts[3];

          // 解析日期
          DateTime? createdAt;
          try {
            createdAt = DateTime.parse(dateStr);
          } catch (e) {
            createdAt = DateTime.now();
          }

          backups.add({
            'hash': hash,
            'message': message,
            'createdAt': createdAt,
            'author': author,
          });
        }
      }

      return backups;
    } catch (e) {
      debugPrint('获取备份列表失败: $e');
      return [];
    }
  }

  /// 应用备份（git reset）
  static Future<bool> applyBackup(
    String saveDataPath,
    String commitHash,
  ) async {
    try {
      if (!await isWorktreeManaged(saveDataPath)) {
        debugPrint('存档目录未被 git worktree 管理: $saveDataPath');
        return false;
      }

      // 获取当前 HEAD 的 hash
      final currentHeadResult = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: saveDataPath);

      if (currentHeadResult.exitCode != 0) {
        debugPrint('获取当前 HEAD 失败: ${currentHeadResult.stderr}');
        return false;
      }

      final currentHead = currentHeadResult.stdout.toString().trim();

      // 使用 git reset --hard 重置到目标提交
      final resetHardResult = await Process.run('git', [
        'reset',
        '--hard',
        commitHash,
      ], workingDirectory: saveDataPath);

      if (resetHardResult.exitCode != 0) {
        debugPrint('Git reset --hard 失败: ${resetHardResult.stderr}');
        return false;
      }

      // 使用 git reset --soft 将 HEAD 变更回最新提交
      final resetSoftResult = await Process.run('git', [
        'reset',
        '--soft',
        currentHead,
      ], workingDirectory: saveDataPath);

      if (resetSoftResult.exitCode != 0) {
        debugPrint('Git reset --soft 失败: ${resetSoftResult.stderr}');
        // 这里失败不算致命错误，因为文件已经恢复了
      }

      debugPrint('备份应用成功: $commitHash');
      return true;
    } catch (e) {
      debugPrint('应用备份失败: $e');
      return false;
    }
  }

  /// 同步到云端（git push --all）
  static Future<bool> pushToCloud(String saveDataPath, String remoteUrl) async {
    try {
      if (!await isWorktreeManaged(saveDataPath)) {
        return false;
      }

      // 添加远程仓库（如果不存在）
      await _addRemoteIfNotExists(saveDataPath, remoteUrl);

      // 推送所有分支
      final pushResult = await Process.run('git', [
        'push',
        '--all',
        'origin',
      ], workingDirectory: saveDataPath);

      if (pushResult.exitCode != 0) {
        debugPrint('Git push 失败: ${pushResult.stderr}');
        return false;
      }

      debugPrint('推送到云端成功');
      return true;
    } catch (e) {
      debugPrint('推送到云端失败: $e');
      return false;
    }
  }

  /// 从云端同步（git pull --all）
  static Future<bool> pullFromCloud(String saveDataPath) async {
    try {
      if (!await isWorktreeManaged(saveDataPath)) {
        return false;
      }

      // 拉取所有分支
      final pullResult = await Process.run('git', [
        'pull',
        '--all',
      ], workingDirectory: saveDataPath);

      if (pullResult.exitCode != 0) {
        debugPrint('Git pull 失败: ${pullResult.stderr}');
        return false;
      }

      debugPrint('从云端同步成功');
      return true;
    } catch (e) {
      debugPrint('从云端同步失败: $e');
      return false;
    }
  }

  /// 检查 git 状态
  static Future<Map<String, dynamic>> getGitStatus(String saveDataPath) async {
    try {
      if (!await isWorktreeManaged(saveDataPath)) {
        return {'managed': false};
      }

      // 获取状态
      final statusResult = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: saveDataPath);

      final hasChanges = statusResult.stdout.toString().trim().isNotEmpty;

      // 检查是否有远程更新
      await Process.run('git', ['fetch'], workingDirectory: saveDataPath);

      final behindResult = await Process.run('git', [
        'rev-list',
        '--count',
        'HEAD..@{u}',
      ], workingDirectory: saveDataPath);

      final behindCount =
          int.tryParse(behindResult.stdout.toString().trim()) ?? 0;

      return {
        'managed': true,
        'hasChanges': hasChanges,
        'hasRemoteUpdates': behindCount > 0,
        'behindCount': behindCount,
      };
    } catch (e) {
      debugPrint('获取 Git 状态失败: $e');
      return {'managed': false, 'error': e.toString()};
    }
  }

  /// 添加远程仓库（如果不存在）
  static Future<void> _addRemoteIfNotExists(
    String saveDataPath,
    String remoteUrl,
  ) async {
    try {
      // 检查是否已有 origin 远程仓库
      final remoteResult = await Process.run('git', [
        'remote',
        'get-url',
        'origin',
      ], workingDirectory: saveDataPath);

      if (remoteResult.exitCode != 0) {
        // 添加远程仓库
        await Process.run('git', [
          'remote',
          'add',
          'origin',
          remoteUrl,
        ], workingDirectory: saveDataPath);
      }
    } catch (e) {
      debugPrint('添加远程仓库失败: $e');
    }
  }

  /// 启动前同步检查
  static Future<Map<String, dynamic>> checkSyncBeforeLaunch() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      // 在数据目录执行 git pull --all
      final pullResult = await Process.run('git', [
        'pull',
        '--all',
      ], workingDirectory: appDataDir.path);

      return {
        'success': pullResult.exitCode == 0,
        'output': pullResult.stdout.toString(),
        'error': pullResult.stderr.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
