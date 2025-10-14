import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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


}