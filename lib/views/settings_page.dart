import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/app_data_service.dart';
import '../services/cloud_sync_config_service.dart';
import '../services/cloud_backup_service.dart';
import '../controllers/game_controller.dart';
import '../services/logging_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GameController gameController = Get.find<GameController>();
  bool _autoBackupEnabled = false;
  bool _autoSyncEnabled = false;
  bool _isLoading = true;
  int _autoBackupCount = 3; // 默认保存3个自动备份

  // 云同步相关状态
  final TextEditingController _cloudUrlController = TextEditingController();
  bool _isCloudConfigured = false;
  bool _isTestingConnection = false;
  bool _isSyncing = false;
  Map<String, dynamic>? _syncStatus;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _cloudUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await AppDataService.getSettings();
      final cloudConfig = await CloudSyncConfigService.getCloudSyncConfig();
      final autoSyncEnabled = await CloudSyncConfigService.getAutoSyncEnabled();

      setState(() {
        _autoBackupEnabled = settings['autoBackupEnabled'] as bool? ?? false;
        _autoBackupCount = settings['autoBackupCount'] as int? ?? 3;
        _autoSyncEnabled = autoSyncEnabled;
        _isCloudConfigured = cloudConfig != null;
        if (cloudConfig != null) {
          _cloudUrlController.text = cloudConfig.toString();
        }
        _isLoading = false;
      });

      // 如果已配置云同步，获取同步状态
      if (_isCloudConfigured) {
        _updateSyncStatus();
      }
    } catch (e) {
      LoggingService.instance.info('加载设置失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    try {
      await AppDataService.updateSettings({
        'autoBackupEnabled': _autoBackupEnabled,
        'autoBackupCount': _autoBackupCount,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置已保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存设置失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 保存自动同步设置
  Future<void> _saveAutoSyncSetting(bool enabled) async {
    try {
      await CloudSyncConfigService.setAutoSyncEnabled(enabled);
      setState(() {
        _autoSyncEnabled = enabled;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '自动云同步已启用' : '自动云同步已关闭'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存自动同步设置失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 更新同步状态
  Future<void> _updateSyncStatus() async {
    try {
      final status = await CloudBackupService.getSyncStatus();
      setState(() {
        _syncStatus = status;
      });
    } catch (e) {
      LoggingService.instance.info('获取同步状态失败: $e');
    }
  }

  // 保存云同步配置
  Future<void> _saveCloudConfig() async {
    final url = _cloudUrlController.text.trim();
    if (url.isEmpty) {
      await CloudSyncConfigService.clearCloudSyncConfig();
      setState(() {
        _isCloudConfigured = false;
        _syncStatus = null;
      });
      return;
    }

    final success = await CloudSyncConfigService.saveCloudSyncConfigFromUrl(
      url,
    );
    if (success) {
      setState(() {
        _isCloudConfigured = true;
      });
      _updateSyncStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('云同步配置已保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('云同步配置格式错误，请检查URL格式'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 测试云连接
  Future<void> _testCloudConnection() async {
    setState(() {
      _isTestingConnection = true;
    });

    try {
      final connected = await CloudBackupService.testCloudConnection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(connected ? '连接成功' : '连接失败'),
            backgroundColor: connected ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      if (connected) {
        _updateSyncStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('测试连接失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isTestingConnection = false;
      });
    }
  }

  // 上传到云端
  Future<void> _uploadToCloud() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      // 首先检查是否需要确认
      final result = await CloudBackupService.uploadToCloud();

      if (result == CloudSyncResult.needsConfirmation) {
        // 需要用户确认，显示对话框
        final confirmed = await _showConfirmationDialog(
          title: '确认上传',
          content: '云端文件比本地文件更新，上传将覆盖云端的新版本。\n\n确定要继续上传吗？',
        );

        if (!confirmed) {
          setState(() {
            _isSyncing = false;
          });
          return;
        }

        // 用户确认后，跳过确认检查重新上传
        final confirmedResult = await CloudBackupService.uploadToCloud(
          skipConfirmation: true,
        );
        _handleSyncResult(confirmedResult, '上传');
      } else {
        _handleSyncResult(result, '上传');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  // 从云端下载
  Future<void> _downloadFromCloud() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      // 首先检查是否需要确认
      final result = await CloudBackupService.downloadFromCloud();

      if (result == CloudSyncResult.needsConfirmation) {
        // 需要用户确认，显示对话框
        final confirmed = await _showConfirmationDialog(
          title: '确认下载',
          content: '本地文件比云端文件更新，下载将覆盖本地的新版本。\n\n确定要继续下载吗？',
        );

        if (!confirmed) {
          setState(() {
            _isSyncing = false;
          });
          return;
        }

        // 用户确认后，跳过确认检查重新下载
        final confirmedResult = await CloudBackupService.downloadFromCloud(
          skipConfirmation: true,
        );
        await _handleDownloadResult(confirmedResult);
      } else {
        await _handleDownloadResult(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  // 显示确认对话框
  Future<bool> _showConfirmationDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // 处理同步结果
  void _handleSyncResult(CloudSyncResult result, String operation) {
    final message = CloudBackupService.getSyncResultMessage(result);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$operation结果: $message'),
          backgroundColor:
              result == CloudSyncResult.success ||
                  result == CloudSyncResult.noChanges
              ? Colors.green
              : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (result == CloudSyncResult.success) {
      _updateSyncStatus();
    }
  }

  // 处理下载结果
  Future<void> _handleDownloadResult(CloudSyncResult result) async {
    _handleSyncResult(result, '下载');

    if (result == CloudSyncResult.success) {
      // 重新加载应用数据并刷新游戏列表
      await gameController.loadGames();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置已同步，游戏列表已刷新'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '存档管理',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // 自动存档备份开关
                        SwitchListTile(
                          title: const Text('自动存档备份'),
                          subtitle: const Text(
                            '游戏结束时自动检查存档变化并创建备份\n每个游戏只保留一个自动备份',
                          ),
                          value: _autoBackupEnabled,
                          onChanged: (value) {
                            setState(() {
                              _autoBackupEnabled = value;
                            });
                            _saveSettings();
                          },
                        ),

                        if (_autoBackupEnabled) ...[
                          const SizedBox(height: 16),

                          // 自动备份数量配置
                          ListTile(
                            title: const Text('自动备份保存数量'),
                            subtitle: Text(
                              '当前保存 $_autoBackupCount 个自动备份，超出数量时会自动删除最旧的备份',
                            ),
                            trailing: SizedBox(
                              width: 120,
                              child: DropdownButton<int>(
                                value: _autoBackupCount,
                                isExpanded: true,
                                items: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((
                                  count,
                                ) {
                                  return DropdownMenuItem<int>(
                                    value: count,
                                    child: Text('$count 个'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _autoBackupCount = value;
                                    });
                                    _saveSettings();
                                  }
                                },
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info, color: Colors.blue[600]),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    '自动备份将以 "auto-时间.zip" 为文件名保存，并在备份列表中置顶显示。只有检测到存档目录变更时才会创建新的自动备份。',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 云同步配置
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '云同步配置',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // S3 URL 输入框
                        TextField(
                          controller: _cloudUrlController,
                          decoration: const InputDecoration(
                            labelText: 'S3 服务器地址',
                            hintText:
                                's3://accessKey:secretKey@endpoint/bucket/path',
                            border: OutlineInputBorder(),
                            helperText:
                                '格式: s3://accessKey:secretKey@endpoint/bucket/path',
                          ),
                          maxLines: 2,
                        ),

                        const SizedBox(height: 16),

                        // 配置操作按钮
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: _saveCloudConfig,
                              child: const Text('保存配置'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed:
                                  _isCloudConfigured && !_isTestingConnection
                                  ? _testCloudConnection
                                  : null,
                              child: _isTestingConnection
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('测试连接'),
                            ),
                          ],
                        ),

                        if (_isCloudConfigured) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),

                          // 同步状态信息
                          if (_syncStatus != null) ...[
                            _buildSyncStatusWidget(),
                            const SizedBox(height: 16),
                          ],

                          // 同步操作按钮
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: !_isSyncing
                                      ? _uploadToCloud
                                      : null,
                                  icon: _isSyncing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.cloud_upload),
                                  label: const Text('上传到云端'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: !_isSyncing
                                      ? _downloadFromCloud
                                      : null,
                                  icon: _isSyncing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.cloud_download),
                                  label: const Text('从云端下载'),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // 自动同步开关
                          SwitchListTile(
                            title: const Text('自动云同步'),
                            subtitle: const Text('启用后，在创建备份或修改游戏配置时自动上传到云端'),
                            value: _autoSyncEnabled,
                            onChanged: _isCloudConfigured
                                ? (value) => _saveAutoSyncSetting(value)
                                : null,
                          ),

                          const SizedBox(height: 16),

                          // 说明信息
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info, color: Colors.blue[600]),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        '云同步说明',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '• 云同步会备份应用配置文件 (app.json)、游戏封面 (covers) 和存档备份 (backups)\n'
                                  '• 同步时会比较本地和云端文件的最后修改时间和大小，确保数据一致性\n'
                                  '• 自动同步功能会在创建备份或修改游戏配置时自动上传到云端\n'
                                  '• 云同步配置保存在 local.json 中，不会被同步到其他设备',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // 构建同步状态显示组件
  Widget _buildSyncStatusWidget() {
    if (_syncStatus == null) {
      return const SizedBox.shrink();
    }

    final status = _syncStatus!;
    final localExists = status['localExists'] as bool? ?? false;
    final remoteExists = status['remoteExists'] as bool? ?? false;
    final localModified = status['localModified'] as String?;
    final remoteModified = status['remoteModified'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '同步状态',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),

          // 本地文件状态
          Row(
            children: [
              Icon(
                localExists ? Icons.folder : Icons.folder_off,
                color: localExists ? Colors.blue : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localExists ? '本地文件: $localModified' : '本地文件: 不存在',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // 云端文件状态
          Row(
            children: [
              Icon(
                remoteExists ? Icons.cloud : Icons.cloud_off,
                color: remoteExists ? Colors.blue : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remoteExists ? '云端文件: $remoteModified' : '云端文件: 不存在',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),

          if (status['error'] != null) ...[
            const SizedBox(height: 8),
            Text(
              '错误: ${status['error']}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
