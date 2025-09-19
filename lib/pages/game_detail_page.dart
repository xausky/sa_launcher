import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/game.dart';
import '../models/save_backup.dart';
import '../services/save_backup_service.dart';
import '../services/auto_backup_service.dart';
import '../services/app_data_service.dart';
import '../providers/game_process_provider.dart';
import 'add_game_page.dart';

class GameDetailPage extends ConsumerStatefulWidget {
  final Game game;

  const GameDetailPage({super.key, required this.game});

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  List<SaveBackup> _backups = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    try {
      final backups = await SaveBackupService.getGameBackups(widget.game.id);
      // 使用自动备份服务的排序方法，自动备份置顶
      final sortedBackups = AutoBackupService.sortBackupsWithAutoFirst(backups);
      setState(() {
        _backups = sortedBackups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorDialog('加载备份列表失败: $e');
    }
  }

  Future<void> _createBackup() async {
    if (widget.game.saveDataPath == null || widget.game.saveDataPath!.isEmpty) {
      _showErrorDialog('请先在游戏设置中配置存档路径');
      return;
    }

    final result = await _showCreateBackupDialog();
    if (result != null && result.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final backup = await SaveBackupService.createBackup(
          widget.game.id,
          widget.game.saveDataPath!,
          result,
        );

        if (backup != null) {
          await _loadBackups();
          _showSuccessDialog('备份创建成功');
        } else {
          _showErrorDialog('备份创建失败');
        }
      } catch (e) {
        setState(() => _isLoading = false);
        _showErrorDialog('备份创建失败: $e');
      }
    }
  }

  Future<String?> _showCreateBackupDialog() async {
    final controller = TextEditingController();
    final now = DateTime.now();
    controller.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建存档备份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请输入备份名称:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '备份名称',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop(name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyBackup(SaveBackup backup) async {
    if (widget.game.saveDataPath == null || widget.game.saveDataPath!.isEmpty) {
      _showErrorDialog('请先在游戏设置中配置存档路径');
      return;
    }

    final confirmed = await _showConfirmDialog(
      '应用存档备份',
      '确定要应用备份 "${backup.name}" 吗？\n\n这将覆盖当前的存档文件！',
    );

    if (confirmed) {
      setState(() => _isLoading = true);
      try {
        final success = await SaveBackupService.applyBackup(
          backup,
          widget.game.saveDataPath!,
        );

        setState(() => _isLoading = false);
        if (success) {
          _showSuccessDialog('存档备份应用成功');
        } else {
          _showErrorDialog('存档备份应用失败');
        }
      } catch (e) {
        setState(() => _isLoading = false);
        _showErrorDialog('存档备份应用失败: $e');
      }
    }
  }

  Future<void> _deleteBackup(SaveBackup backup) async {
    final confirmed = await _showConfirmDialog(
      '删除备份',
      '确定要删除备份 "${backup.name}" 吗？\n\n此操作无法撤销！',
    );

    if (confirmed) {
      setState(() => _isLoading = true);
      try {
        final success = await SaveBackupService.deleteBackup(backup);
        if (success) {
          await _loadBackups();
          _showSuccessDialog('备份删除成功');
        } else {
          setState(() => _isLoading = false);
          _showErrorDialog('备份删除失败');
        }
      } catch (e) {
        setState(() => _isLoading = false);
        _showErrorDialog('备份删除失败: $e');
      }
    }
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('确定'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('成功'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGame() async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 500,
          height: 600,
          child: AddGamePage(gameToEdit: widget.game, ref: ref),
        ),
      ),
    );
  }

  Future<void> _launchGame() async {
    try {
      final success = await ref
          .read(gameProcessProvider.notifier)
          .launchGame(widget.game.id, widget.game.executablePath);
      if (!success) {
        _showErrorDialog('启动游戏失败');
      }
    } catch (e) {
      _showErrorDialog('启动游戏失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(isGameRunningProvider(widget.game.id));
    final processId = ref.watch(gameProcessIdProvider(widget.game.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.game.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _editGame,
            icon: const Icon(Icons.edit),
            tooltip: '编辑游戏',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 游戏基本信息
                  _buildGameInfo(isRunning, processId),
                  const SizedBox(height: 24),

                  // 存档备份管理
                  _buildBackupSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildGameInfo(bool isRunning, int? processId) {
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
                      widget.game.coverImageFileName,
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
                      _buildInfoRow('执行文件', widget.game.executablePath),
                      if (widget.game.saveDataPath != null &&
                          widget.game.saveDataPath!.isNotEmpty)
                        _buildInfoRow('存档路径', widget.game.saveDataPath!),
                      if (isRunning)
                        _buildInfoRow(
                          '运行状态',
                          'PID: $processId',
                          color: Colors.green,
                        ),
                      _buildInfoRow(
                        '添加时间',
                        _formatDateTime(widget.game.createdAt),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                if (!isRunning)
                  ElevatedButton.icon(
                    onPressed: _launchGame,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('启动游戏'),
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
                    label: const Text('停止游戏'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                const SizedBox(width: 12),
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

  Widget _buildBackupSection() {
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed:
                      widget.game.saveDataPath != null &&
                          widget.game.saveDataPath!.isNotEmpty
                      ? _createBackup
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('新建备份'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (widget.game.saveDataPath == null ||
                widget.game.saveDataPath!.isEmpty)
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
            else if (_backups.isEmpty)
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
                itemCount: _backups.length,
                itemBuilder: (context, index) {
                  final backup = _backups[index];
                  return _buildBackupItem(backup);
                },
              ),
          ],
        ),
      ),
    );
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

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }
}
