import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sa_launcher/services/cloud_backup_service.dart';
import 'package:sa_launcher/services/logging_service.dart';
import 'package:sa_launcher/services/restic_service.dart';
import 'package:sa_launcher/views/home_page.dart';
import '../controllers/bindings/main_binding.dart';

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> with TickerProviderStateMixin {
  String _statusMessage = '正在初始化应用...';
  double _displayedProgress = 0.0;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _performInitialization();
  }

  void _initAnimations() {
    // 进度条动画控制器 - 用于实际进度更新
    _progressController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // 进度条动画曲线 - 实际进度更新时使用
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 0.99,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));

    // 监听实际进度更新动画
    _progressAnimation.addListener(() {
      setState(() {
        _displayedProgress = _progressAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  // 执行初始化流程
  Future<void> _performInitialization() async {
    try {
      // 步骤1: 初始化本地仓库
      _updateStatus('正在初始化本地仓库...', 0.2);
      await _initializeResticRepositories();

      // 步骤2: 检查云端更新
      _updateStatus('正在检查云端更新...', 0.6);
      await _checkForCloudUpdates();

      if (mounted) {
        Get.offAll(
          () => const HomePage(),
          binding: MainBinding(),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = '初始化失败: $e';
      });
      LoggingService.instance.info('初始化失败: $e');

      if (mounted) {
        _showErrorDialog(e);
      }
    }
  }

  // 初始化 restic 仓库
  Future<void> _initializeResticRepositories() async {
    try {
      final localLatestSnapshot = await ResticService.getLatestSnapshot();
      if (localLatestSnapshot != null) {
        return;
      }

      final localInitialized = await ResticService.initLocalRepository();
      if (localInitialized) {
        LoggingService.instance.info('本地 restic 仓库初始化成功');
      } else {
        LoggingService.instance.info('本地 restic 仓库初始化失败或已存在');
      }
    } catch (e) {
      LoggingService.instance.info('初始化 restic 仓库失败: $e');
      rethrow;
    }
  }

  // 检查云端更新
  Future<void> _checkForCloudUpdates() async {
    try {
      final hasUpdates = await CloudBackupService.hasCloudUpdates();
      if (hasUpdates) {
        _updateStatus('发现云端更新，正在下载...', 0.8);
        await _downloadFromCloud();
      }
    } catch (e) {
      LoggingService.instance.info('检查云端更新失败: $e');
      // 云端更新检查失败不影响初始化流程
    }
  }

  // 从云端下载
  Future<void> _downloadFromCloud() async {
    try {
      final result = await CloudBackupService.downloadFromCloud(
        skipConfirmation: true,
      );

      if (result != CloudSyncResult.success && result != CloudSyncResult.noChanges) {
        throw Exception(CloudBackupService.getSyncResultMessage(result));
      }
    } catch (e) {
      LoggingService.instance.info('从云端下载失败: $e');
      rethrow;
    }
  }

  // 更新状态
  void _updateStatus(String message, double progress) {
    setState(() {
      _statusMessage = message;
    });

    // 从当前显示的进度开始动画到新进度
    _progressController.reset();
    _progressController.forward();
  }

  // 显示错误对话框
  void _showErrorDialog(dynamic error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('初始化失败'),
          content: Text('初始化过程中发生错误: ${error.toString()}'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const InitPage()),
                );
              },
              child: const Text('重试'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 应用图标
              const Icon(
                Icons.gamepad,
                size: 80,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 32),

              // 应用标题
              const Text(
                '游戏启动器',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 48),

              // 状态消息
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              // 进度条
              Container(
                width: 300,
                child: LinearProgressIndicator(
                  value: _displayedProgress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 进度百分比
              Text(
                '${(_displayedProgress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}