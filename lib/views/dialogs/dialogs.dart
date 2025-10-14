import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sa_launcher/models/file_modification.dart';
import 'package:sa_launcher/models/game.dart';
import 'package:sa_launcher/models/game_process.dart';
import 'package:sa_launcher/services/auto_backup_service.dart';
import 'edit_game_view.dart';
import 'file_tracking_results_view.dart';

class Dialogs {

  static Future<void> showProgressDialog(String name, AsyncCallback runner) async {
    try {
      Get.dialog(AlertDialog(title: Text(name), content: SizedBox(width: 100, height: 100, child: Center(child: const CircularProgressIndicator(),),)), barrierDismissible: false);
      await runner();
    } finally {
      Get.back();
    }
  }

  static Future<String?> showInputDialog(String title, String hintText) async {
    final controller = TextEditingController();
    final now = DateTime.now();
    controller.text =
    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Get.dialog<String?>(AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: null),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              Get.back(result: name);
            }
          },
          child: const Text('创建'),
        ),
      ],
    ));
  }

  static Future<bool> showConfirmDialog(String title, String content) async {
    return await Get.dialog<bool>(AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Get.back(result: true),
          child: const Text('确定'),
        ),
      ],
    )) ?? false;
  }

  static Future<void> showErrorDialog(String message) async {
    await Get.dialog(AlertDialog(
      title: const Text('错误'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('确定'),
        ),
      ],
    ));
  }

  static Future<void> showSuccessDialog(String message) async {
    await Get.dialog(AlertDialog(
      title: const Text('成功'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text('确定'),
        ),
      ],
    ));
  }

  static Future<bool> showFileTrackingConfirmDialog() async {
    return await Get.dialog<bool>(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.track_changes, color: Colors.blue),
            SizedBox(width: 8),
            Text('启动游戏并追踪文件修改'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此功能将：', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('1. 启动游戏并且追踪游戏对计算机文件的修改。'),
            SizedBox(height: 4),
            Text('2. 在游戏运行结束后显示所有修改的文件列表和修改次数。'),
            SizedBox(height: 4),
            Text('3. 用于对于不知道存档目录的游戏追踪存档目录使用。'),
            SizedBox(height: 12),
            Text(
              '注意：',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '使用本方法运行游戏会对游戏性能以及系统性能产生一定负面影响。',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('确定启动'),
          ),
        ],
      ),
    ) ??
        false;
  }

  static Future<bool?> showEditGameDialog(Game game) async {
    return await Get.dialog<bool>(
      const EditGameView(),
    );
  }

  static Future<void> showFileTrackingResultsDialog(
      FileTrackingSession session) async {
    await Get.dialog(FileTrackingResultsView(session: session));
  }

  static Future<bool> showCloudUpdateDialog() async {
    return await Get.dialog<bool>(
          AlertDialog(
            title: const Text('发现云端更新'),
            content: const Text('检测到云端有更新的配置和存档备份。\n\n是否要从云端下载最新版本？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('稍后'),
              ),
              TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text('立即下载'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<bool?> showAddGameDialog() async {
    return await Get.dialog<bool>(
      const EditGameView(),
    );
  }

  static Future<bool?> showAutoBackupDialog(
    Game game,
    BackupCheckResult checkResult,
  ) async {
    return await Get.dialog<bool>(
      AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.green[600]),
            const SizedBox(width: 12),
            const Text('发现更新的自动备份'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '游戏 "${game.title}" 存在更新的自动备份存档。',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),

            // 时间信息卡片
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
                      Icon(
                        Icons.auto_awesome,
                        color: Colors.green[600],
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '自动备份时间:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(checkResult.autoBackupTime!),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.folder, color: Colors.blue[600], size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        '存档目录时间:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    checkResult.saveDataTime != null
                        ? _formatDateTime(checkResult.saveDataTime!)
                        : '不存在或为空',
                    style: TextStyle(
                      fontSize: 14,
                      color: checkResult.saveDataTime != null
                          ? null
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[600], size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '应用备份将覆盖当前存档文件！',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('是否要应用自动备份后再启动游戏？', style: TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('跳过'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('应用备份'),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}