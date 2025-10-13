import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sa_launcher/services/restic_service.dart';
import 'app_data_service.dart';
import 'logging_service.dart';

class CloudSyncConfig {
  final String endPoint;
  final String accessKey;
  final String secretKey;
  final String bucket;
  final String objectPath;

  const CloudSyncConfig({
    required this.endPoint,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.objectPath,
  });

  factory CloudSyncConfig.fromJson(Map<String, dynamic> json) {
    return CloudSyncConfig(
      endPoint: json['endPoint'] as String,
      accessKey: json['accessKey'] as String,
      secretKey: json['secretKey'] as String,
      bucket: json['bucket'] as String,
      objectPath: json['objectPath'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'endPoint': endPoint,
      'accessKey': accessKey,
      'secretKey': secretKey,
      'bucket': bucket,
      'objectPath': objectPath,
    };
  }

  @override
  String toString() {
    return 's3://$accessKey:$secretKey@$endPoint/$bucket/$objectPath';
  }
}

class CloudSyncConfigService {
  static const String _localJsonFileName = 'local.json';

  // 获取 local.json 文件路径
  static Future<File> _getLocalJsonFile() async {
    final appDataDir = await AppDataService.getAppDataDirectory();
    return File(path.join(appDataDir.path, _localJsonFileName));
  }

  // 从 S3 URL 解析配置信息
  static CloudSyncConfig? parseS3Url(String s3Url) {
    try {
      // 格式: s3://accessKey:secretKey@endPoint/bucket/path
      if (!s3Url.startsWith('s3://')) {
        return null;
      }

      final uri = Uri.parse(s3Url);

      // 解析认证信息
      final userInfo = uri.userInfo;
      if (userInfo.isEmpty) {
        return null;
      }

      final authParts = userInfo.split(':');
      if (authParts.length != 2) {
        return null;
      }

      final accessKey = authParts[0];
      final secretKey = authParts[1];

      // 解析主机名（endPoint）
      final endPoint = uri.host;
      if (endPoint.isEmpty) {
        return null;
      }

      // 解析路径，提取 bucket 和 objectPath
      final pathSegments = uri.pathSegments;
      if (pathSegments.isEmpty) {
        return null;
      }

      final bucket = pathSegments[0];
      final objectPath = pathSegments.length > 1
          ? pathSegments.sublist(1).join('/')
          : '';

      return CloudSyncConfig(
        endPoint: endPoint,
        accessKey: accessKey,
        secretKey: secretKey,
        bucket: bucket,
        objectPath: objectPath,
      );
    } catch (e) {
      LoggingService.instance.info('解析 S3 URL 失败: $e');
      return null;
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
      LoggingService.instance.info('读取 local.json 失败: $e');
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
      LoggingService.instance.info('写入 local.json 失败: $e');
    }
  }

  // 获取云同步配置
  static Future<CloudSyncConfig?> getCloudSyncConfig() async {
    try {
      final localConfig = await _readLocalConfig();
      final cloudSyncData = localConfig['cloudSync'] as Map<String, dynamic>?;

      if (cloudSyncData != null) {
        return CloudSyncConfig.fromJson(cloudSyncData);
      }
    } catch (e) {
      LoggingService.instance.info('获取云同步配置失败: $e');
    }
    return null;
  }

  // 保存云同步配置
  static Future<void> saveCloudSyncConfig(CloudSyncConfig? config) async {
    try {
      final localConfig = await _readLocalConfig();

      if (config != null) {
        localConfig['cloudSync'] = config.toJson();
      } else {
        localConfig.remove('cloudSync');
      }

      await _writeLocalConfig(localConfig);
    } catch (e) {
      LoggingService.instance.info('保存云同步配置失败: $e');
    }
  }

  // 从 URL 字符串保存配置
  static Future<bool> saveCloudSyncConfigFromUrl(String s3Url) async {
    final config = parseS3Url(s3Url);
    if (config != null) {
      await saveCloudSyncConfig(config);
      await ResticService.initRemoteRepository(cloudConfig: config);
      return true;
    }
    return false;
  }

  // 检查是否已配置云同步
  static Future<bool> isCloudSyncConfigured() async {
    final config = await getCloudSyncConfig();
    return config != null;
  }

  // 清除云同步配置
  static Future<void> clearCloudSyncConfig() async {
    await saveCloudSyncConfig(null);
  }

  // 获取自动同步配置
  static Future<bool> getAutoSyncEnabled() async {
    try {
      final localConfig = await _readLocalConfig();
      return localConfig['autoSync'] as bool? ?? false;
    } catch (e) {
      LoggingService.instance.info('获取自动同步配置失败: $e');
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
      LoggingService.instance.info('设置自动同步配置失败: $e');
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
      LoggingService.instance.info('获取游戏路径失败: $e');
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
      LoggingService.instance.info('设置游戏路径失败: $e');
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
      LoggingService.instance.info('保存游戏路径失败: $e');
    }
  }

  // 删除游戏的路径信息
  static Future<void> removeGamePaths(String gameId) async {
    try {
      final gamePaths = await getGamePaths();
      gamePaths.remove(gameId);
      await setGamePaths(gamePaths);
    } catch (e) {
      LoggingService.instance.info('删除游戏路径失败: $e');
    }
  }
}
