import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'app_data_service.dart';
import 'git_worktree_service.dart';
import 'logging_service.dart';

class GitRepoConfig {
  final String repoUrl;

  const GitRepoConfig({required this.repoUrl});

  factory GitRepoConfig.fromJson(Map<String, dynamic> json) {
    return GitRepoConfig(repoUrl: json['repoUrl'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'repoUrl': repoUrl};
  }

  @override
  String toString() {
    return repoUrl;
  }
}

class CloudSyncConfigService {
  static const String _localJsonFileName = 'local.json';

  // 获取 local.json 文件路径
  static Future<File> _getLocalJsonFile() async {
    final appDataDir = await AppDataService.getAppDataDirectory();
    return File(path.join(appDataDir.path, _localJsonFileName));
  }

  // 验证 Git 仓库 URL 格式
  static bool isValidGitUrl(String gitUrl) {
    try {
      // 支持的格式：
      // https://username:token@github.com/user/repo.git
      // https://github.com/user/repo.git
      // git@github.com:user/repo.git
      // ssh://git@github.com/user/repo.git

      if (gitUrl.startsWith('https://') ||
          gitUrl.startsWith('http://') ||
          gitUrl.startsWith('git@') ||
          gitUrl.startsWith('ssh://')) {
        return gitUrl.contains('.git') || gitUrl.contains('/');
      }
      return false;
    } catch (e) {
      LoggingService.logError('验证 Git URL 失败: $e', e);
      return false;
    }
  }

  // 读取本地配置
  static Future<Map<String, dynamic>> _readLocalConfig() async {
    try {
      final localJsonFile = await _getLocalJsonFile();
      if (await localJsonFile.exists()) {
        final jsonString = await localJsonFile.readAsString();
        return jsonDecode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      LoggingService.logError('读取 local.json 失败: $e', e);
    }
    return <String, dynamic>{};
  }

  // 写入本地配置
  static Future<void> _writeLocalConfig(Map<String, dynamic> config) async {
    try {
      final localJsonFile = await _getLocalJsonFile();
      final jsonString = const JsonEncoder.withIndent('  ').convert(config);
      await localJsonFile.writeAsString(jsonString);
    } catch (e) {
      LoggingService.logError('写入 local.json 失败: $e', e);
    }
  }

  // 获取 Git 仓库配置
  static Future<Map<String, dynamic>?> getGitRepoConfig() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();
      final remoteUrl = await GitWorktreeService.getRemoteUrl(appDataDir.path);

      if (remoteUrl != null && remoteUrl.isNotEmpty) {
        return {'repoUrl': remoteUrl};
      }
      return null;
    } catch (e) {
      LoggingService.logError('获取 Git 仓库配置失败: $e', e);
    }
    return null;
  }

  // 保存 Git 仓库配置
  static Future<void> saveGitRepoConfig(String? repoUrl) async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();

      if (repoUrl != null && repoUrl.isNotEmpty) {
        // 设置远程仓库地址
        final success = await GitWorktreeService.setRemoteUrl(
          appDataDir.path,
          repoUrl,
        );
        if (!success) {
          LoggingService.warning('设置远程仓库地址失败');
        }
      } else {
        // 移除远程仓库
        await GitWorktreeService.removeRemote(appDataDir.path);
      }
    } catch (e) {
      LoggingService.logError('保存 Git 仓库配置失败: $e', e);
    }
  }

  // 从 URL 字符串保存配置
  static Future<bool> saveGitRepoConfigFromUrl(String gitUrl) async {
    if (isValidGitUrl(gitUrl)) {
      await saveGitRepoConfig(gitUrl);
      return true;
    }
    return false;
  }

  // 检查是否已配置 Git 仓库
  static Future<bool> isGitRepoConfigured() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();
      return await GitWorktreeService.hasRemoteConfigured(appDataDir.path);
    } catch (e) {
      LoggingService.logError('检查 Git 仓库配置失败: $e', e);
      return false;
    }
  }

  // 清除 Git 仓库配置
  static Future<void> clearGitRepoConfig() async {
    try {
      final appDataDir = await AppDataService.getAppDataDirectory();
      await GitWorktreeService.removeRemote(appDataDir.path);
    } catch (e) {
      LoggingService.logError('清除 Git 仓库配置失败: $e', e);
    }
  }

  // 获取自动同步配置
  static Future<bool> getAutoSyncEnabled() async {
    try {
      final localConfig = await _readLocalConfig();
      return localConfig['autoSync'] as bool? ?? false;
    } catch (e) {
      LoggingService.logError('获取自动同步配置失败: $e', e);
      return false;
    }
  }

  // 设置自动同步配置
  static Future<void> setAutoSyncEnabled(bool enabled) async {
    try {
      final localConfig = await _readLocalConfig();
      localConfig['autoSync'] = enabled;
      await _writeLocalConfig(localConfig);
    } catch (e) {
      LoggingService.logError('设置自动同步配置失败: $e', e);
    }
  }

  // 获取游戏路径数据
  static Future<Map<String, Map<String, String>>> getGamePaths() async {
    try {
      final localConfig = await _readLocalConfig();
      final gamePaths = localConfig['gamePaths'] as Map<String, dynamic>?;
      if (gamePaths != null) {
        final result = <String, Map<String, String>>{};
        for (final entry in gamePaths.entries) {
          final gameId = entry.key;
          final pathData = entry.value as Map<String, dynamic>;
          result[gameId] = Map<String, String>.from(pathData);
        }
        return result;
      }
    } catch (e) {
      LoggingService.logError('获取游戏路径失败: $e', e);
    }
    return <String, Map<String, String>>{};
  }

  // 设置游戏路径数据
  static Future<void> setGamePaths(
    Map<String, Map<String, String>> gamePaths,
  ) async {
    try {
      final localConfig = await _readLocalConfig();
      localConfig['gamePaths'] = gamePaths;
      await _writeLocalConfig(localConfig);
    } catch (e) {
      LoggingService.logError('设置游戏路径失败: $e', e);
    }
  }

  // 保存单个游戏的路径信息
  static Future<void> saveGamePaths(
    String gameId,
    String executablePath,
    String? saveDataPath,
  ) async {
    try {
      final gamePaths = await getGamePaths();
      final gamePathData = <String, String>{'executablePath': executablePath};
      if (saveDataPath != null) {
        gamePathData['saveDataPath'] = saveDataPath;
      }
      gamePaths[gameId] = gamePathData;
      await setGamePaths(gamePaths);
    } catch (e) {
      LoggingService.logError('保存游戏路径失败: $e', e);
    }
  }

  // 删除游戏的路径信息
  static Future<void> removeGamePaths(String gameId) async {
    try {
      final gamePaths = await getGamePaths();
      gamePaths.remove(gameId);
      await setGamePaths(gamePaths);
    } catch (e) {
      LoggingService.logError('删除游戏路径失败: $e', e);
    }
  }

  // === 兼容性方法（用于迁移） ===

  // 获取旧的云同步配置（用于迁移）
  static Future<Map<String, dynamic>?> getCloudSyncConfig() async {
    return await getGitRepoConfig();
  }

  // 检查是否已配置云同步（兼容性）
  static Future<bool> isCloudSyncConfigured() async {
    return await isGitRepoConfigured();
  }
}
