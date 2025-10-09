import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sa_launcher/models/game_process.dart';
import '../models/game.dart';
import '../providers/game_provider.dart';
import '../providers/game_process_provider.dart';
import '../services/auto_backup_service.dart';
import '../services/app_data_service.dart';
import '../services/cloud_backup_service.dart';
import 'add_game_page.dart';
import 'game_detail_page.dart';
import 'settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    _checkForCloudUpdates();

    // 设置自动备份消息回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(gameProcessProvider.notifier)
          .setMessageCallback(_showAutoBackupMessage);
    });
  }

  // 显示自动备份消息
  void _showAutoBackupMessage(String message, bool isSuccess) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
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
      print('检查云端更新失败: $e');
    }
  }

  // 显示云端更新对话框
  void _showCloudUpdateDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('发现云端更新'),
          content: const Text('检测到云端有更新的配置和存档备份。\n\n是否要从云端下载最新版本？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('稍后'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _downloadFromCloud();
              },
              child: const Text('立即下载'),
            ),
          ],
        );
      },
    );
  }

  // 从云端下载
  Future<void> _downloadFromCloud() async {
    try {
      final result = await CloudBackupService.downloadFromCloud(
        skipConfirmation: true,
      );

      if (result == CloudSyncResult.success) {
        // 重新加载游戏列表
        await ref.read(gameListProvider.notifier).loadGames();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('云端配置下载成功，游戏列表已更新'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result != CloudSyncResult.noChanges) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '下载失败: ${CloudBackupService.getSyncResultMessage(result)}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameListAsync = ref.watch(gameListProvider);

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
            onPressed: () => ref.read(gameListProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: gameListAsync.when(
        data: (games) => _buildGameGrid(context, ref, games),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                '加载游戏列表失败: $error',
                style: const TextStyle(fontSize: 16, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(gameListProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addGame(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGameGrid(BuildContext context, WidgetRef ref, List<Game> games) {
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
              onPressed: () => _addGame(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('添加第一个游戏'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final game = games[index];
          return GameCard(
            game: game,
            onLaunch: () => _launchGame(context, ref, game),
            onEdit: () => _editGame(context, ref, game),
            onDelete: () => _deleteGame(context, ref, game),
            onDetail: () => _showGameDetail(context, game),
          );
        },
      ),
    );
  }

  Future<void> _launchGame(
    BuildContext context,
    WidgetRef ref,
    Game game,
  ) async {
    try {
      // 检查是否需要应用自动备份
      var checkResult = await AutoBackupService.checkAutoBackupBeforeLaunch(
        game,
      );

      if (checkResult.shouldSyncCloud) {
        final shouldApply = await _showSyncCloudDialog(
          context,
          game,
          checkResult,
        );
        if (shouldApply == true) {
          await CloudBackupService.downloadFromCloud(skipConfirmation: true);
          checkResult = await AutoBackupService.checkAutoBackupBeforeLaunch(
            game,
          );
        }
      }

      if (checkResult.shouldApply) {
        final shouldApply = await _showAutoBackupDialog(
          context,
          game,
          checkResult,
        );
        if (shouldApply == true) {
          // 显示应用备份的进度对话框
          final applySuccess = await _showApplyBackupProgress(context, game);
          if (!applySuccess) {
            _showErrorDialog(context, '应用自动备份失败');
            return;
          }
        }
      }

      // 启动游戏
      final success = await ref
          .read(gameProcessProvider.notifier)
          .launchGame(game.id, game.executablePath);
      if (!success) {
        _showErrorDialog(context, '启动游戏失败');
      }
    } catch (e) {
      _showErrorDialog(context, '启动游戏失败: $e');
    }
  }

  Future<bool?> _showSyncCloudDialog(
    context,
    Game game,
    BackupCheckResult checkResult,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现云端更新'),
        content: const Text('检测到云端有更新的配置和存档备份。\n\n是否要从云端下载最新版本？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('不需要同步'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('下载最新版本'),
          ),
        ],
      ),
    );
  }

  Future<void> _addGame(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AddGamePage(ref: ref),
    );

    if (result == true) {
      ref.read(gameListProvider.notifier).refresh();
    }
  }

  Future<void> _editGame(BuildContext context, WidgetRef ref, Game game) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AddGamePage(gameToEdit: game, ref: ref),
    );

    if (result == true) {
      ref.read(gameListProvider.notifier).refresh();
    }
  }

  Future<void> _deleteGame(
    BuildContext context,
    WidgetRef ref,
    Game game,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除游戏 "${game.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(gameListProvider.notifier).deleteGame(game.id);
    }
  }

  void _showGameDetail(BuildContext context, Game game) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => GameDetailPage(game: game)));
  }

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsPage()));
  }

  // 显示自动备份应用提示对话框
  Future<bool?> _showAutoBackupDialog(
    BuildContext context,
    Game game,
    BackupCheckResult checkResult,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('跳过'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('应用备份'),
          ),
        ],
      ),
    );
  }

  // 显示应用备份进度对话框
  Future<bool> _showApplyBackupProgress(BuildContext context, Game game) async {
    bool success = false;

    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('正在应用自动备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在应用游戏 "${game.title}" 的自动备份...'),
          ],
        ),
      ),
    );

    try {
      // 异步执行备份应用
      success = await AutoBackupService.applyAutoBackup(game);
    } catch (e) {
      success = false;
    } finally {
      // 关闭进度对话框
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    return success;
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class GameCard extends ConsumerStatefulWidget {
  final Game game;
  final VoidCallback onLaunch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDetail;

  const GameCard({
    super.key,
    required this.game,
    required this.onLaunch,
    required this.onEdit,
    required this.onDelete,
    required this.onDetail,
  });

  @override
  ConsumerState<GameCard> createState() => _GameCardState();
}

class _GameCardState extends ConsumerState<GameCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(gameProcessInfoProvider(widget.game.id));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Card(
        elevation: _isHovered ? 8 : 2,
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
                  widget.game.coverImageFileName,
                ),
                builder: (context, snapshot) {
                  final coverPath = snapshot.data;

                  return coverPath != null && File(coverPath).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.file(
                            File(coverPath),
                            key: ValueKey(widget.game.coverImageFileName!),
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
                      widget.game.title,
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
                    _buildGameStatsInfo(widget.game, info),
                  ],
                ),
              ),
            ),

            // 悬停时显示的操作按钮
            if (_isHovered)
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
                          onPressed: widget.onLaunch,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('启动'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () async {
                            await ref
                                .read(gameProcessProvider.notifier)
                                .killGame(widget.game.id);
                          },
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
                            onPressed: widget.onDetail,
                            icon: const Icon(Icons.info),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: widget.onDelete,
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
