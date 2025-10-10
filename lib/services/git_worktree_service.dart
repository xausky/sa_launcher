import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'app_data_service.dart';
import 'logging_service.dart';

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
        LoggingService.instance.info('Git 仓库已存在: ${appDataDir.path}');
        return true;
      }

      // 初始化 git 仓库
      final initResult = await Process.run('git', [
        'init',
      ], workingDirectory: appDataDir.path);

      if (initResult.exitCode != 0) {
        LoggingService.instance.logError('Git 初始化失败: ${initResult.stderr}');
        return false;
      }

      // 配置用户信息（如果没有全局配置）
      await _configureGitUser(appDataDir.path);

      await Process.run('git', [
        'config',
        'i18n.logoutputencoding',
        'utf8',
      ], workingDirectory: appDataDir.path);

      // 创建初始提交
      await createMainCommit(appDataDir.path);

      LoggingService.instance.info('Git 仓库初始化成功: ${appDataDir.path}');
      return true;
    } catch (e) {
      LoggingService.instance.logError('初始化 Git 仓库失败', e);
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
      LoggingService.instance.logError('配置 Git 用户信息失败', e);
    }
  }

  /// 创建初始提交
  static Future<void> createMainCommit(String repoPath) async {
    try {
      // 创建 .gitignore 文件
      final gitignoreFile = File(path.join(repoPath, '.gitignore'));
      await gitignoreFile.writeAsString('local.json');

      // 添加文件到暂存区
      await Process.run('git', ['add', '.'], workingDirectory: repoPath);

      // 创建主提交
      await Process.run('git', [
        'commit',
        '-m',
        'main-update',
      ], workingDirectory: repoPath);
    } catch (e) {
      LoggingService.instance.logError('创建初始提交失败', e);
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
      final gitContent = (await gitFile.readAsString())
          .replaceAll(RegExp(r'[\r\n]'), '')
          .trim();
      if (gitContent.startsWith('gitdir:')) {
        final worktreePath = gitContent.substring(7).trim();
        return await Directory(worktreePath).exists();
      }
      return false;
    } catch (e) {
      LoggingService.instance.logError('检查 worktree 管理状态失败', e);
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
        LoggingService.instance.info('存档目录已被 worktree 管理: $saveDataPath');
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
            LoggingService.instance.logError('删除已存在的 worktree 失败: ${removeResult.stderr}');
            return false;
          }
        }
      }

      final worktreeResult = await Process.run('git', [
        'worktree',
        'add',
        '--orphan',
        '-B',
        gameId,
        gameId,
      ], workingDirectory: appDataDir.path);

      if (worktreeResult.exitCode != 0) {
        LoggingService.instance.logError('创建 worktree 失败: ${worktreeResult.stderr}');
        return false;
      }

      // 实现 hack 方法重定向 worktree
      if (!await _redirectWorktree(gameId, saveDataPath)) {
        return false;
      }

      LoggingService.instance.info('为游戏 $gameId 创建 worktree 成功');
      return true;
    } catch (e) {
      LoggingService.instance.logError('创建 worktree 失败', e);
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
      LoggingService.instance.info('Worktree 重定向成功: $saveDataPath');
      return true;
    } catch (e) {
      LoggingService.instance.logError('重定向 worktree 失败', e);
      return false;
    }
  }

  /// 在存档目录创建备份（git commit）
  /// 返回值：成功时返回 commit hash，没有变更时返回 'NO_CHANGES'，失败时返回 null
  static Future<String?> createBackup(
    String saveDataPath,
    String message,
  ) async {
    try {
      // 检查是否为 git worktree 管理的目录
      if (!await isWorktreeManaged(saveDataPath)) {
        LoggingService.instance.warning('存档目录未被 git worktree 管理: $saveDataPath');
        return null;
      }

      // 添加所有变更到暂存区
      final addResult = await Process.run('git', [
        'add',
        '.',
      ], workingDirectory: saveDataPath);

      if (addResult.exitCode != 0) {
        LoggingService.instance.logError('Git add 失败: ${addResult.stderr}');
        return null;
      }

      // 检查是否有变更需要提交
      final statusResult = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: saveDataPath);

      if (statusResult.stdout.toString().trim().isEmpty) {
        LoggingService.instance.info('没有变更需要提交');
        return 'NO_CHANGES';
      }

      // 创建提交
      final commitResult = await Process.run('git', [
        'commit',
        '-m',
        message,
      ], workingDirectory: saveDataPath);

      if (commitResult.exitCode != 0) {
        LoggingService.instance.logError('Git commit 失败: ${commitResult.stderr}');
        return null;
      }

      // 获取最新提交的 hash
      final hashResult = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: saveDataPath);

      if (hashResult.exitCode == 0) {
        final commitHash = hashResult.stdout.toString().trim();
        LoggingService.instance.info('备份创建成功，提交 hash: $commitHash');
        return commitHash;
      }

      return null;
    } catch (e) {
      LoggingService.instance.logError('创建 Git 备份失败', e);
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
      ], workingDirectory: saveDataPath, stdoutEncoding: utf8);

      if (logResult.exitCode != 0) {
        LoggingService.instance.logError('Git log 失败: ${logResult.stderr}');
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
      LoggingService.instance.logError('获取备份列表失败', e);
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
        LoggingService.instance.warning('存档目录未被 git worktree 管理: $saveDataPath');
        return false;
      }

      // 获取当前 HEAD 的 hash
      final currentHeadResult = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: saveDataPath);

      if (currentHeadResult.exitCode != 0) {
        LoggingService.instance.logError('获取当前 HEAD 失败: ${currentHeadResult.stderr}');
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
        LoggingService.instance.logError('Git reset --hard 失败: ${resetHardResult.stderr}');
        return false;
      }

      // 使用 git reset --soft 将 HEAD 变更回最新提交
      final resetSoftResult = await Process.run('git', [
        'reset',
        '--soft',
        currentHead,
      ], workingDirectory: saveDataPath);

      if (resetSoftResult.exitCode != 0) {
        LoggingService.instance.warning('Git reset --soft 失败: ${resetSoftResult.stderr}');
        // 这里失败不算致命错误，因为文件已经恢复了
      }

      LoggingService.instance.info('备份应用成功: $commitHash');
      return true;
    } catch (e) {
      LoggingService.instance.logError('应用备份失败', e);
      return false;
    }
  }

  /// 同步到云端（git push --all）
  static Future<bool> push(String saveDataPath) async {
    try {
      // 推送所有分支
      final pushResult = await Process.run('git', [
        'push',
        '--force-with-lease',
        '--all',
        'origin',
      ], workingDirectory: saveDataPath);

      if (pushResult.exitCode != 0) {
        LoggingService.instance.logError('Git push 失败: ${pushResult.stderr}');
        return false;
      }

      LoggingService.instance.info('推送到云端成功');
      return true;
    } catch (e) {
      LoggingService.instance.logError('推送到云端失败', e);
      return false;
    }
  }

  /// 从云端同步
  static Future<bool> pull(String tagrtPath, String branch) async {
    try {
      if (branch != "main" && !await isWorktreeManaged(tagrtPath)) {
        return false;
      }

      final fetchResult = await Process.run('git', [
        'fetch',
      ], workingDirectory: tagrtPath);
      if (fetchResult.exitCode != 0) {
        LoggingService.instance.logError('Git fetch 失败: ${fetchResult.stderr}');
        return false;
      }

      final branchResult = await Process.run('git', [
        'branch',
        '--set-upstream-to=origin/$branch',
        branch,
      ], workingDirectory: tagrtPath);

      if (branchResult.exitCode != 0) {
        LoggingService.instance.logError('Git branch 失败: ${branchResult.stderr}');
        return false;
      }

      // 拉取分支
      final pullResult = await Process.run('git', [
        'pull', '--rebase',
      ], workingDirectory: tagrtPath);

      if (pullResult.exitCode != 0) {
        LoggingService.instance.logError('Git pull 失败: ${pullResult.stderr}');
        return false;
      }

      LoggingService.instance.info('从云端同步成功');
      return true;
    } catch (e) {
      LoggingService.instance.logError('从云端同步失败', e);
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
      LoggingService.instance.logError('获取 Git 状态失败', e);
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
      LoggingService.instance.logError('添加远程仓库失败', e);
    }
  }

  /// 启动前同步检查
  static Future<Map<String, dynamic>> checkSyncBeforeLaunch() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      // 在数据目录执行 git pull --all
      final pullResult = await pull(appDataDir.path, "main");

      return {'success': pullResult};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 获取远程仓库地址
  static Future<String?> getRemoteUrl(String repoPath) async {
    try {
      final result = await Process.run('git', [
        'remote',
        'get-url',
        'origin',
      ], workingDirectory: repoPath);

      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
      return null;
    } catch (e) {
      LoggingService.instance.logError('获取远程仓库地址失败', e);
      return null;
    }
  }

  /// 设置远程仓库地址
  static Future<bool> setRemoteUrl(String repoPath, String remoteUrl) async {
    try {
      // 检查是否已有 origin 远程仓库
      final checkResult = await Process.run('git', [
        'remote',
        'get-url',
        'origin',
      ], workingDirectory: repoPath);

      if (checkResult.exitCode == 0) {
        // 更新现有远程仓库地址
        final updateResult = await Process.run('git', [
          'remote',
          'set-url',
          'origin',
          remoteUrl,
        ], workingDirectory: repoPath);

        return updateResult.exitCode == 0;
      } else {
        // 添加新的远程仓库
        final addResult = await Process.run('git', [
          'remote',
          'add',
          'origin',
          remoteUrl,
        ], workingDirectory: repoPath);

        return addResult.exitCode == 0;
      }
    } catch (e) {
      LoggingService.instance.logError('设置远程仓库地址失败', e);
      return false;
    }
  }

  /// 移除远程仓库
  static Future<bool> removeRemote(String repoPath) async {
    try {
      final result = await Process.run('git', [
        'remote',
        'remove',
        'origin',
      ], workingDirectory: repoPath);

      return result.exitCode == 0;
    } catch (e) {
      LoggingService.instance.logError('移除远程仓库失败', e);
      return false;
    }
  }

  /// 检查是否已配置远程仓库
  static Future<bool> hasRemoteConfigured(String repoPath) async {
    try {
      final result = await Process.run('git', [
        'remote',
        'get-url',
        'origin',
      ], workingDirectory: repoPath);

      return result.exitCode == 0;
    } catch (e) {
      LoggingService.instance.logError('检查远程仓库配置失败: $e');
      return false;
    }
  }

  /// 修改备份信息（如果是最新提交使用 git commit --amend，否则使用 git rebase -i 修改提交信息）
  /// 返回值：成功时返回 true，失败时返回 false
  static Future<bool> modifyBackupInfo(
    String saveDataPath,
    String commitHash,
    String newMessage,
  ) async {
    try {
      if (!await isWorktreeManaged(saveDataPath)) {
        LoggingService.instance.warning('存档目录未被 git worktree 管理: $saveDataPath');
        return false;
      }

      // 获取当前 HEAD 的 hash
      final currentHeadResult = await Process.run('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: saveDataPath);

      if (currentHeadResult.exitCode != 0) {
        LoggingService.instance.logError('获取当前 HEAD 失败: ${currentHeadResult.stderr}');
        return false;
      }

      final currentHead = currentHeadResult.stdout.toString().trim();

      // 判断是否为最新提交
      if (commitHash == currentHead) {
        // 是最新提交，使用 git commit --amend 修改提交信息
        final amendResult = await Process.run('git', [
          'commit',
          '--amend',
          '-m',
          newMessage,
        ], workingDirectory: saveDataPath);

        if (amendResult.exitCode != 0) {
          LoggingService.instance.logError('Git commit amend 失败: ${amendResult.stderr}');
          return false;
        }
      } else {
        // 不是最新提交，使用 git rebase -i 修改提交信息
        // 由于 git rebase -i 是交互式命令，我们需要使用环境变量来避免交互
        final rebaseResult = await Process.run('git', [
          'rebase',
          '-i',
          '$commitHash^',
        ], workingDirectory: saveDataPath, environment: {
          'GIT_EDITOR': 'echo "pick $commitHash $newMessage" >',
        });

        if (rebaseResult.exitCode != 0) {
          LoggingService.instance.logError('Git rebase 失败: ${rebaseResult.stderr}');
          return false;
        }
      }

      LoggingService.instance.logError('备份信息修改成功: $commitHash -> $newMessage');
      return true;
    } catch (e) {
      LoggingService.instance.logError('修改备份信息失败: $e');
      return false;
    }
  }
}
