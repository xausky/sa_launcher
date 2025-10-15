
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:sa_launcher/views/dialogs/dialogs.dart';
import 'package:sa_launcher/views/snacks/snacks.dart';

import '../../models/file_modification.dart';
import '../../models/game_process.dart';

class FileTrackingResultsView extends StatelessWidget {
  final FileTrackingSession session;

  const FileTrackingResultsView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.track_changes, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text(
                    '文件修改追踪结果',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // 统计信息
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.folder,
                      title: '修改文件数',
                      value: '${session.modifiedFileCount}个',
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.edit,
                      title: '总修改次数',
                      value: '${session.totalModifications}次',
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.schedule,
                      title: '追踪时长',
                      value: _formatDuration(session.duration),
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),

            // 文件列表
            Expanded(
              child: session.modifiedFileCount == 0
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '未检测到文件修改',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '可能游戏没有修改任何文件，或者文件修改发生在系统目录中',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: session.sortedModifications.length,
                      itemBuilder: (context, index) {
                        final modification =
                            session.sortedModifications[index];
                        return _buildFileModificationItem(modification);
                      },
                    ),
            ),

            // 底部按钮
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileModificationItem(FileModification modification) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.insert_drive_file,
          color: modification.modificationCount > 5 ? Colors.red : Colors.blue,
        ),
        title: Text(
          modification.fileName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              modification.filePath,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '修改次数: ${modification.modificationCount} | 最后修改: ${_formatDateTime(modification.lastModified)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: modification.modificationCount > 5
                    ? Colors.red[100]
                    : Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${modification.modificationCount}次',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: modification.modificationCount > 5
                      ? Colors.red[800]
                      : Colors.blue[800],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _openDirectory(modification.directoryPath, '目录'),
              icon: const Icon(Icons.folder_open, size: 20),
              tooltip: '打开目录',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        isThreeLine: true,
      ),
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
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(75)),
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

  Future<void> _openDirectory(String p, String pathType) async {
    try {
      // 对于执行文件，打开其所在目录
      String directoryPath;
      if (pathType == '执行文件') {
        directoryPath = path.dirname(p);
      } else {
        // 对于存档路径，直接打开该目录
        directoryPath = p;
      }

      // 使用 Windows 的 explorer 命令打开目录
      await Process.run('explorer', [directoryPath]);
    } catch (e) {
      Snacks.error('打开目录失败: $e');
    }
  }
}
