import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:sa_launcher/controllers/backup_controller.dart';
import 'package:sa_launcher/controllers/game_controller.dart';
import 'package:sa_launcher/models/game_process.dart';
import 'package:sa_launcher/services/app_data_service.dart';
import 'package:sa_launcher/views/dialogs/dialogs.dart';
import 'package:sa_launcher/models/game.dart';
import 'package:sa_launcher/models/save_backup.dart';
import 'package:sa_launcher/services/auto_backup_service.dart';
import 'package:sa_launcher/controllers/game_process_controller.dart';
import 'package:sa_launcher/controllers/game_list_controller.dart';
import 'package:sa_launcher/views/snacks/snacks.dart';

class GameDetailPage extends GetView<GameController> {
  GameDetailPage({super.key});

  final GameProcessController gameProcessController = Get.find<GameProcessController>();

  bool _checkPath() {
    if (controller.game.value?.saveDataPath == null || controller.game.value!.saveDataPath!.isEmpty) {
      Snacks.error('请先在游戏设置中配置存档路径');
      return false;
    }
    return true;
  }

  Future<void> _createBackup() async {
    if(!_checkPath()) {
      return;
    }
    final name = await Dialogs.showInputDialog("创建备份", "请输入备份名称");
    if (name != null && name.isNotEmpty) {
      Dialogs.showProgressDialog("正在创建备份", () async {
        await Get.find<BackupController>().newBackup(name);
      });
    }
  }


  Future<void> _applyBackup(SaveBackup backup) async {
    if(!_checkPath()) {
      return;
    }

    final confirmed = await Dialogs.showConfirmDialog(
      '应用存档备份',
      '确定要应用备份 "${backup.name}" 吗？\n\n这将覆盖当前的存档文件！',
    );

    if (confirmed) {
      if (confirmed) {
        await Dialogs.showProgressDialog("正在应用备份", () => Get.find<BackupController>().applyBackup(backup), result: (r) async {
          if(r) {
            Snacks.success("应用备份成功");
          } else {
            Snacks.success("应用备份失败");
          }
        }, error: (e) async {
          Snacks.error("应用备份失败 $e");
        });

      }
    }
  }

  Future<void> _deleteBackup(SaveBackup backup) async {
    final confirmed = await Dialogs.showConfirmDialog(
      '删除备份',
      '确定要删除备份 "${backup.name}" 吗？\n\n此操作无法撤销！',
    );

    if (confirmed) {
      Dialogs.showProgressDialog("正在删除备份", () async {
        await Get.find<BackupController>().deleteBackup(backup);
      });
    }
  }

  Future<void> _editGame() async {
    await Dialogs.showEditGameDialog(controller.game.value!);
  }

  Future<void> _launchGame() async {
    try {
      final success = await gameProcessController
          .launchGame(controller.game.value!.id, controller.game.value!.executablePath);
      if (!success) {
        Snacks.error('启动游戏失败');
      }
    } catch (e) {
      Snacks.error('启动游戏失败: $e');
    }
  }

  Future<void> _launchGameWithFileTracking() async {
    final confirmed = await Dialogs.showFileTrackingConfirmDialog();
    if (!confirmed) return;

    try {
      final success = await gameProcessController
          .launchGameWithFileTracking(
        controller.game.value!.id,
        controller.game.value!.executablePath,
          );
      if (!success) {
        Snacks.error('启动游戏失败');
      }
    } catch (e) {
      Snacks.error('启动游戏失败: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if(controller.game.value == null) {
        return Center(child: CircularProgressIndicator(),);
      }
      final info = gameProcessController.runningGames[controller.game.value!.id];
      return Scaffold(
        appBar: AppBar(
          title: Text(controller.game.value!.title),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              onPressed: _editGame,
              icon: const Icon(Icons.edit),
              tooltip: '编辑游戏',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 游戏基本信息
              _buildGameInfo(info),
              const SizedBox(height: 24),

              // 游戏统计信息
              _buildStatsSection(context),
              const SizedBox(height: 24),

              // 存档备份管理
              _buildBackupSection(context),
            ],
          ),
        ),
      );
    });
  }


  Widget _buildGameInfo(GameProcessInfo? info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 游戏封面
                Container(
                  width: 100,
                  height: 100 / 0.75,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey, width: 1),
                  ),
                  child: FutureBuilder<String?>(
                    future: AppDataService.getGameCoverPath(
                      controller.game.value!.coverImageFileName,
                    ),
                    builder: (context, snapshot) {
                      final coverPath = snapshot.data;

                      return coverPath != null && File(coverPath).existsSync()
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.file(
                          File(coverPath),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      )
                          : Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.games,
                            size: 32,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),

                // 游戏信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPathInfoRow('执行文件', controller.game.value!.executablePath),
                      if (controller.game.value!.saveDataPath != null &&
                          controller.game.value!.saveDataPath!.isNotEmpty)
                        _buildPathInfoRow('存档路径', controller.game.value!.saveDataPath!),
                      if (info?.isRunning ?? false)
                        _buildInfoRow(
                          '运行状态',
                          '${info?.processId}(${info?.processCount})',
                          color: Colors.green,
                        ),
                      _buildInfoRow(
                        '添加时间',
                        _formatDateTime(controller.game.value!.createdAt),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 操作按钮
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: (!(info?.isRunning ?? false)) ? [
                ElevatedButton.icon(
                  onPressed: _launchGame,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('启动游戏'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _launchGameWithFileTracking,
                  icon: const Icon(Icons.track_changes),
                  label: const Text('启动游戏（并且追踪文件修改）'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _editGame,
                  icon: const Icon(Icons.edit),
                  label: const Text('编辑'),
                ),
              ] : [
                ElevatedButton.icon(
                  onPressed: () async {
                    await gameProcessController
                        .killGame(controller.game.value!.id);
                  },
                  icon: const Icon(Icons.stop),
                  label: const Text('停止游戏'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _editGame,
                  icon: const Icon(Icons.edit),
                  label: const Text('编辑'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: color != null ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: color != null ? FontWeight.bold : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _openDirectory(value, label),
            icon: const Icon(Icons.folder_open, size: 18),
            tooltip: '打开$label目录',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Future<void> _openDirectory(String path, String pathType) async {
    try {
      // 对于执行文件，打开其所在目录
      String directoryPath;
      if (pathType == '执行文件') {
        directoryPath = path.substring(0, path.lastIndexOf('\\'));
      } else {
        // 对于存档路径，直接打开该目录
        directoryPath = path;
      }

      // 使用 Windows 的 explorer 命令打开目录
      await Process.run('explorer', [directoryPath]);
    } catch (e) {
      Snacks.error('打开目录失败: $e');
    }
  }

  Widget _buildBackupSection(BuildContext context) {
    return Obx(() {
      final backups = AutoBackupService.sortBackupsWithAutoFirst(Get.find<BackupController>().backupMap.values.toList());
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '存档备份',
                    style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                    controller.game.value!.saveDataPath != null &&
                        controller.game.value!.saveDataPath!.isNotEmpty
                        ? _createBackup
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('新建备份'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (controller.game.value!.saveDataPath == null ||
                  controller.game.value!.saveDataPath!.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[600]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '请先在游戏设置中配置存档路径才能创建备份',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                )
              else if (backups.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '还没有存档备份',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '点击"新建备份"来创建第一个备份',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: backups.length,
                  itemBuilder: (context, index) {
                    final backup = backups[index];
                    return _buildBackupItem(backup);
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildBackupItem(SaveBackup backup) {
    final isAutoBackup = AutoBackupService.isAutoBackup(backup);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isAutoBackup ? Colors.green[50] : null,
      child: ListTile(
        leading: Icon(
          isAutoBackup ? Icons.auto_awesome : Icons.archive,
          color: isAutoBackup ? Colors.green : Colors.blue,
        ),
        title: Row(
          children: [
            Text(isAutoBackup ? '自动备份' : backup.name),
            if (isAutoBackup) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'AUTO',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('创建时间: ${_formatDateTime(backup.createdAt)}'),
            Text('文件大小: ${backup.formattedFileSize}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _applyBackup(backup),
              icon: const Icon(Icons.restore),
              tooltip: '应用备份',
              color: Colors.green,
            ),
            IconButton(
              onPressed: () => _deleteBackup(backup),
              icon: const Icon(Icons.delete),
              tooltip: '删除备份',
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    return Obx(() {
      final game = controller.game.value!;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '游戏统计',
                style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildStatsContent(game),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildStatsContent(Game game) {
    if (game.playCount == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.analytics_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                '还没有游戏统计数据',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              Text(
                '开始游戏后将自动记录游戏时长',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.schedule,
                title: '总游戏时长',
                value: game.formattedTotalPlaytime,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.play_circle,
                title: '游戏次数',
                value: '${game.playCount}次',
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.access_time,
                title: '最后游玩',
                value: game.formattedLastPlayedAt,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.trending_up,
                title: '平均时长',
                value: game.playCount > 0
                    ? _formatDuration(
                        Duration(
                          seconds:
                              game.totalPlaytime.inSeconds ~/ game.playCount,
                        ),
                      )
                    : '0分钟',
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '$hours小时$minutes分钟';
    } else {
      return '$minutes分钟';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }
}
