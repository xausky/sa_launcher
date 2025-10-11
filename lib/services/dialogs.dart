
import 'package:flutter/material.dart';

class Dialogs {

  static Future<bool?> showSyncCloudDialog(
      BuildContext context,
      String name,
      ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发现 $name 存在冲突云端更新'),
        content: const Text('检测到云端有更新的配置和存档备份且无法合并。\n\n是否使用云端版本（本地版本将被覆盖）？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('使用本地版本'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('使用云端版本'),
          ),
        ],
      ),
    );
  }

}