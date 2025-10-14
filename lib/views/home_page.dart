import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sa_launcher/controllers/backup_controller.dart';
import 'package:sa_launcher/models/game_process.dart';
import 'package:sa_launcher/views/dialogs/dialogs.dart';
import 'package:sa_launcher/views/snacks/snacks.dart';
import '../models/game.dart';
import '../controllers/game_controller.dart';
import '../controllers/game_process_controller.dart';
import '../services/auto_backup_service.dart';
import '../services/app_data_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/logging_service.dart';
import 'dialogs/edit_game_view.dart';
import 'game_detail_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GameController gameController = Get.find<GameController>();
  final GameProcessController gameProcessController = Get.find<GameProcessController>();

  @override
  void initState() {
    super.initState();
    _checkForCloudUpdates();

    // 设置自动备份消息回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gameProcessController.setMessageCallback(_showAutoBackupMessage);
    });
  }

  // 显示自动备份消息
  void _showAutoBackupMessage(String message, bool isSuccess) {
    if (isSuccess) {
      Snacks.success(message);
    } else {
      Snacks.warning(message);
    }
  }

  // 检查云端更新
  Future<void> _checkForCloudUpdates() async {
    try {
      final hasUpdates = await CloudBackupService.hasCloudUpdates();
      if (hasUpdates && mounted) {
        _showCloudUpdateDialog();
      }
    } catch (e) {
      LoggingService.instance.info('检查云端更新失败: $e');
    }
  }

  // 显示云端更新对话框
  void _showCloudUpdateDialog() async {
    final download = await Dialogs.showCloudUpdateDialog();
    if (download) {
      _downloadFromCloud();
    }
  }

  // 从云端下载
  Future<void> _downloadFromCloud() async {
    try {
      final result = await CloudBackupService.downloadFromCloud(
        skipConfirmation: true,
      );

      if (result == CloudSyncResult.success) {
        // 重新加载游戏列表
        await gameController.loadGames();

        Snacks.success('云端配置下载成功，游戏列表已更新');
      } else if (result != CloudSyncResult.noChanges) {
        Snacks.error('下载失败: ${CloudBackupService.getSyncResultMessage(result)}');
      }
    } catch (e) {
      Snacks.error('下载失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SALauncher'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings),
            tooltip: '设置',
          ),
          IconButton(
            onPressed: () => gameController.refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Obx(() {
        if (gameController.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (gameController.errorMessage.value.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  '加载游戏列表失败: ${gameController.errorMessage.value}',
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => gameController.refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        
        return _buildGameGrid(context, gameController.games);
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addGame(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGameGrid(BuildContext context, RxMap<String, Game> games) {
    if (games.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.games, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '还没有添加任何游戏',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _addGame(context),
              icon: const Icon(Icons.add),
              label: const Text('添加第一个游戏'),
            ),
          ],
        ),
      );
    }

    final runningGames = Get.find<GameProcessController>().runningGames;

    return Obx(() {
      final gameList = games.values.toList();
      gameList.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.75,
          ),
          itemCount: gameList.length,
          itemBuilder: (context, index) {
            final game = gameList[index];
            final info = runningGames[game.id];
            return GameCard(
              game: game,
              info: info,
              onLaunch: () => _launchGame(context, game),
              onEdit: () => _editGame(context, game),
              onDelete: () => _deleteGame(context, game),
              onDetail: () => _showGameDetail(context, game),
              onKill: () => _killGame(context, game),
            );
          },
        ),
      );
    });
  }

  Future<void> _killGame(BuildContext context, Game game) async {
    Get.find<GameProcessController>().killGame(game.id);
  }

  Future<void> _launchGame(BuildContext context, Game game) async {
    try {
      // 检查是否需要应用自动备份
      var checkResult = await AutoBackupService.checkAutoBackupBeforeLaunch(
        game,
      );

      if (checkResult.shouldSyncCloud) {
        final shouldApply = await Dialogs.showConfirmDialog(
          '发现云端更新',
          '检测到云端有更新的配置和存档备份。\n\n是否要从云端下载最新版本？',
        );
        if (shouldApply == true) {
          await CloudBackupService.downloadFromCloud(skipConfirmation: true);
          checkResult = await AutoBackupService.checkAutoBackupBeforeLaunch(
            game,
          );
        }
      }

      if (checkResult.shouldApply) {
        final shouldApply = await Dialogs.showAutoBackupDialog(
          game,
          checkResult,
        );
        if (shouldApply == true) {
          // 显示应用备份的进度对话框
          await Dialogs.showProgressDialog('正在应用自动备份', () async {
            final applySuccess = await AutoBackupService.applyAutoBackup(game);
            if (!applySuccess) {
              Dialogs.showErrorDialog('应用自动备份失败');
            }
          });
        }
      }

      // 启动游戏
      final gameProcessController = Get.find<GameProcessController>();
      final success = await gameProcessController.launchGame(game.id, game.executablePath);
      if (!success) {
        Dialogs.showErrorDialog('启动游戏失败');
      }
    } catch (e) {
      Dialogs.showErrorDialog('启动游戏失败: $e');
    }
  }

  Future<void> _addGame(BuildContext context) async {
    final result = await Dialogs.showAddGameDialog();

    if (result == true) {
      gameController.refresh();
    }
  }

  Future<void> _editGame(BuildContext context, Game game) async {
    final result = await Dialogs.showEditGameDialog(game);

    if (result == true) {
      gameController.refresh();
    }
  }

  Future<void> _deleteGame(BuildContext context, Game game) async {
    final confirm = await Dialogs.showConfirmDialog(
      '确认删除',
      '确定要删除游戏 "${game.title}" 吗？',
    );

    if (confirm == true) {
      await gameController.deleteGame(game.id);
    }
  }

  void _showGameDetail(BuildContext context, Game game) {
    Get.to(() => GameDetailPage(game: game), binding: BindingsBuilder(() {
      Get.lazyPut(() => BackupController(gameId: game.id));
    }));
  }

  void _openSettings(BuildContext context) {
    Get.to(() => const SettingsPage());
  }



}

class GameCard extends StatelessWidget {
  final Game game;
  final GameProcessInfo? info;
  final VoidCallback onLaunch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDetail;
  final VoidCallback onKill;

  GameCard({
    super.key,
    required this.game,
    required this.info,
    required this.onLaunch,
    required this.onEdit,
    required this.onDelete,
    required this.onDetail,
    required this.onKill,
  });

  final _isHovered = false.obs;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      child: Obx(() => Card(
        elevation: _isHovered.value ? 8 : 2,
        child: Stack(
          children: [
            // 游戏封面（占满整个卡片）
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey, width: 1),
                color: Colors.grey[50],
              ),
              child: FutureBuilder<String?>(
                future: AppDataService.getGameCoverPath(
                  game.coverImageFileName,
                ),
                builder: (context, snapshot) {
                  final coverPath = snapshot.data;

                  return coverPath != null && File(coverPath).existsSync()
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      File(coverPath),
                      key: ValueKey(game.coverImageFileName!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  )
                      : Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.games,
                        size: 48,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 游戏标题和统计信息（浮动在封面底部）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // 游戏统计信息
                    _buildGameStatsInfo(game, info),
                  ],
                ),
              ),
            ),

            // 悬停时显示的操作按钮
            if (_isHovered.value)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!(info?.isRunning ?? false))
                        ElevatedButton.icon(
                          onPressed: onLaunch,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('启动'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: onKill,
                          icon: const Icon(Icons.stop),
                          label: const Text('停止'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: onDetail,
                            icon: const Icon(Icons.info),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    )
    );
  }

  Widget _buildGameStatsInfo(Game game, GameProcessInfo? info) {
    if (info?.isRunning ?? false) {
      return _buildRunningInfo(info);
    }

    if (game.playCount == 0) {
      return const Text(
        '从未游玩',
        style: TextStyle(fontSize: 10, color: Colors.white70),
      );
    }

    return Column(
      children: [
        Text(
          '游玩时长: ${game.formattedTotalPlaytime}',
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
        Text(
          '最后游玩: ${game.formattedLastPlayedAt}',
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildRunningInfo(GameProcessInfo? info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${info?.processId}(${info?.processCount})',
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
