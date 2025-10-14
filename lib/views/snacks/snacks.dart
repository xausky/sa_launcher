import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Snacks {
  // 显示成功消息
  static void success(String message, {Duration? duration}) {
    Get.snackbar(
      '成功',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  // 显示错误消息
  static void error(String message, {Duration? duration}) {
    Get.snackbar(
      '错误',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red,
      colorText: Colors.white,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  // 显示信息消息
  static void info(String message, {Duration? duration}) {
    Get.snackbar(
      '提示',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  // 显示警告消息
  static void warning(String message, {Duration? duration}) {
    Get.snackbar(
      '警告',
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: duration ?? const Duration(seconds: 3),
    );
  }
}