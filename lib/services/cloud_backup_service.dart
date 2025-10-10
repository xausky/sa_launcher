import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sa_launcher/services/git_worktree_service.dart';
import 'cloud_sync_config_service.dart';
import 'app_data_service.dart';

enum CloudSyncResult {
  success,
  noConfig,
  connectionError,
  uploadError,
  downloadError,
  noChanges,
  fileNotFound,
  needsConfirmation,
}

class CloudBackupService {
  // Git 云同步：推送到远程仓库
  static Future<CloudSyncResult> gitPushToCloud() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      // 检查是否已配置远程仓库
      if (!await GitWorktreeService.hasRemoteConfigured(appDataDir.path)) {
        return CloudSyncResult.noConfig;
      }

      // 推送所有分支
      final pushResult = await Process.run('git', [
        'push',
        '--all',
        'origin',
      ], workingDirectory: appDataDir.path);

      if (pushResult.exitCode != 0) {
        debugPrint('Git push 失败: ${pushResult.stderr}');
        return CloudSyncResult.uploadError;
      }

      // 推送标签
      await Process.run('git', [
        'push',
        '--tags',
        'origin',
      ], workingDirectory: appDataDir.path);

      debugPrint('Git 推送成功');
      return CloudSyncResult.success;
    } catch (e) {
      debugPrint('Git 推送失败: $e');
      return CloudSyncResult.uploadError;
    }
  }

  // Git 云同步：从远程仓库拉取
  static Future<CloudSyncResult> gitPullFromCloud() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      // 拉取所有分支
      final pullResult = await GitWorktreeService.pull(appDataDir.path, "main");

      if (!pullResult) {
        debugPrint('Git pull 失败');
        return CloudSyncResult.downloadError;
      }

      debugPrint('Git 拉取成功');
      return CloudSyncResult.success;
    } catch (e) {
      debugPrint('Git 拉取失败: $e');
      return CloudSyncResult.downloadError;
    }
  }

  // 上传到云端（Git 推送）
  static Future<CloudSyncResult> uploadToCloud({
    bool skipConfirmation = false,
  }) async {
    return await gitPushToCloud();
  }

  // 从云端下载（Git 拉取）
  static Future<CloudSyncResult> downloadFromCloud({
    bool skipConfirmation = false,
  }) async {
    return await gitPullFromCloud();
  }

  // 测试 Git 连接
  static Future<bool> testCloudConnection() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();
      final remoteUrl = await GitWorktreeService.getRemoteUrl(appDataDir.path);

      if (remoteUrl == null) {
        return false;
      }

      // 测试连接，尝试 ls-remote
      final lsRemoteResult = await Process.run('git', [
        'ls-remote',
        '--heads',
        remoteUrl,
      ]);

      if (lsRemoteResult.exitCode == 0) {
        debugPrint('Git 连接测试成功');
        return true;
      } else {
        debugPrint('Git 连接测试失败: ${lsRemoteResult.stderr}');
        return false;
      }
    } catch (e) {
      debugPrint('测试 Git 连接失败: $e');
      return false;
    }
  }

  // 获取同步状态信息
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      if (!await GitWorktreeService.hasRemoteConfigured(appDataDir.path)) {
        return {'configured': false, 'error': '未配置 Git 仓库'};
      }
      Map<String, dynamic> result = {'configured': true};

      // 检查本地仓库状态
      final statusResult = await Process.run('git', [
        'status',
        '--porcelain',
      ], workingDirectory: appDataDir.path);

      result['hasLocalChanges'] = statusResult.stdout
          .toString()
          .trim()
          .isNotEmpty;

      // 检查远程状态
      final fetchResult = await Process.run('git', [
        'fetch',
      ], workingDirectory: appDataDir.path);

      if (fetchResult.exitCode == 0) {
        // 检查是否落后于远程
        final behindResult = await Process.run('git', [
          'rev-list',
          '--count',
          'HEAD..@{u}',
        ], workingDirectory: appDataDir.path);

        if (behindResult.exitCode == 0) {
          final behindCount =
              int.tryParse(behindResult.stdout.toString().trim()) ?? 0;
          result['behindRemote'] = behindCount > 0;
          result['behindCount'] = behindCount;
        }

        // 检查是否领先于远程
        final aheadResult = await Process.run('git', [
          'rev-list',
          '--count',
          '@{u}..HEAD',
        ], workingDirectory: appDataDir.path);

        if (aheadResult.exitCode == 0) {
          final aheadCount =
              int.tryParse(aheadResult.stdout.toString().trim()) ?? 0;
          result['aheadRemote'] = aheadCount > 0;
          result['aheadCount'] = aheadCount;
        }
      }

      return result;
    } catch (e) {
      return {'configured': true, 'error': e.toString()};
    }
  }

  // 自动上传到云端（静默模式）
  static Future<void> autoUploadToCloud() async {
    try {
      // 检查是否启用了自动同步
      final autoSyncEnabled = await CloudSyncConfigService.getAutoSyncEnabled();
      if (!autoSyncEnabled) {
        return;
      }

      // 检查是否配置了 Git 仓库
      final isConfigured = await CloudSyncConfigService.isGitRepoConfigured();
      if (!isConfigured) {
        return;
      }

      debugPrint('开始自动推送到 Git 远程仓库...');

      final result = await gitPushToCloud();

      if (result == CloudSyncResult.success) {
        debugPrint('Git 自动推送成功');
      } else if (result != CloudSyncResult.noChanges) {
        debugPrint('Git 自动推送失败: ${getSyncResultMessage(result)}');
      }
    } catch (e) {
      debugPrint('自动推送异常: $e');
    }
  }

  // 检查云端是否有更新（用于启动时检查）
  static Future<bool> hasCloudUpdates() async {
    try {
      // 检查是否配置了 Git 仓库
      final isConfigured = await CloudSyncConfigService.isGitRepoConfigured();
      if (!isConfigured) {
        return false;
      }

      final hasGitUpdates = await _hasGitUpdates();
      return hasGitUpdates ?? false;
    } catch (e) {
      debugPrint('检查云端更新失败: $e');
      return false;
    }
  }

  // 检查 Git 远程仓库是否有更新
  static Future<bool?> _hasGitUpdates() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      // 执行 git fetch 获取远程更新
      final fetchResult = await Process.run('git', [
        'fetch',
      ], workingDirectory: appDataDir.path);

      if (fetchResult.exitCode != 0) {
        debugPrint('Git fetch 失败: ${fetchResult.stderr}');
        return null; // 无法检查，返回 null
      }

      // 检查是否落后于远程分支
      final behindResult = await Process.run('git', [
        'rev-list',
        '--count',
        'HEAD..@{u}',
      ], workingDirectory: appDataDir.path);

      if (behindResult.exitCode == 0) {
        final behindCount =
            int.tryParse(behindResult.stdout.toString().trim()) ?? 0;
        return behindCount > 0;
      }

      return null;
    } catch (e) {
      debugPrint('检查 Git 更新失败: $e');
      return null;
    }
  }

  // 获取同步结果的描述信息
  static String getSyncResultMessage(CloudSyncResult result) {
    switch (result) {
      case CloudSyncResult.success:
        return '同步成功';
      case CloudSyncResult.noConfig:
        return '未配置 Git 仓库';
      case CloudSyncResult.connectionError:
        return '网络连接错误';
      case CloudSyncResult.uploadError:
        return '推送失败';
      case CloudSyncResult.downloadError:
        return '拉取失败';
      case CloudSyncResult.noChanges:
        return '没有变更需要同步';
      case CloudSyncResult.fileNotFound:
        return '文件未找到';
      case CloudSyncResult.needsConfirmation:
        return '需要用户确认';
    }
  }
}
