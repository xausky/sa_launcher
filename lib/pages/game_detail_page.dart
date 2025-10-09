import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/game_process.dart';
import '../models/game.dart';
import '../models/save_backup.dart';
import '../models/file_modification.dart';
import '../services/save_backup_service.dart';
import '../services/auto_backup_service.dart';
import '../services/app_data_service.dart';
import '../providers/game_process_provider.dart';
import '../providers/game_provider.dart';
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

    // 设置文件追踪回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameProcessProvider.notifier).setFileTrackingCallback((
        gameId,
        session,
      ) {
        if (gameId == widget.game.id && mounted) {
          _showFileTrackingResults(session);
        }
      });
    });
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
        child: SizedBox(
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

  Future<void> _launchGameWithFileTracking() async {
    final confirmed = await _showFileTrackingConfirmDialog();
    if (!confirmed) return;

    try {
      final success = await ref
          .read(gameProcessProvider.notifier)
          .launchGameWithFileTracking(
            widget.game.id,
            widget.game.executablePath,
          );
      if (!success) {
        _showErrorDialog('启动游戏失败');
      }
    } catch (e) {
      _showErrorDialog('启动游戏失败: $e');
    }
  }

  Future<bool> _showFileTrackingConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
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
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('确定启动'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showFileTrackingResults(FileTrackingSession session) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
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

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(gameProcessInfoProvider(widget.game.id));

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
                  _buildGameInfo(info),
                  const SizedBox(height: 24),

                  // 游戏统计信息
                  _buildStatsSection(),
                  const SizedBox(height: 24),

                  // 存档备份管理
                  _buildBackupSection(),
                ],
              ),
            ),
    );
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
                      _buildPathInfoRow('执行文件', widget.game.executablePath),
                      if (widget.game.saveDataPath != null &&
                          widget.game.saveDataPath!.isNotEmpty)
                        _buildPathInfoRow('存档路径', widget.game.saveDataPath!),
                      if (info?.isRunning ?? false)
                        _buildInfoRow(
                          '运行状态',
                          '${info?.processId}(${info?.processCount})',
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
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (!(info?.isRunning ?? false)) ...[
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
                ] else
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
      _showErrorDialog('打开目录失败: $e');
    }
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

  Widget _buildStatsSection() {
    return Consumer(
      builder: (context, ref, child) {
        // 获取最新的游戏数据
        final gamesAsyncValue = ref.watch(gameListProvider);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '游戏统计',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                gamesAsyncValue.when(
                  data: (games) {
                    final game = games.firstWhere(
                      (g) => g.id == widget.game.id,
                      orElse: () => widget.game,
                    );
                    return _buildStatsContent(game);
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '加载统计数据失败: $error',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
