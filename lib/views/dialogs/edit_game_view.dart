import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:sa_launcher/views/snacks/snacks.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sa_launcher/models/game.dart';
import 'package:sa_launcher/controllers/game_list_controller.dart';
import 'package:sa_launcher/services/game_storage.dart';
import 'package:sa_launcher/services/game_launcher.dart';
import 'package:sa_launcher/services/app_data_service.dart';
import 'dialogs.dart';

class EditGameView extends StatefulWidget {
  final Game? gameToEdit;

  const EditGameView({super.key, this.gameToEdit});

  @override
  State<EditGameView> createState() => _EditGameViewState();
}

class _EditGameViewState extends State<EditGameView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _pathController = TextEditingController();
  final _saveDataPathController = TextEditingController();
  final _focusNode = FocusNode();

  final GameListController gameController = Get.find<GameListController>();

  String? _coverImagePath;
  bool _isLoading = false;
  bool _coverImageChanged = false; // 标记封面是否有变化

  @override
  void initState() {
    super.initState();
    if (widget.gameToEdit != null) {
      _titleController.text = widget.gameToEdit!.title;
      _pathController.text = widget.gameToEdit!.executablePath;
      _saveDataPathController.text = widget.gameToEdit!.saveDataPath ?? '';
      // 如果编辑现有游戏，需要获取完整路径用于显示
      if (widget.gameToEdit!.coverImageFileName != null) {
        AppDataService.getGameCoverPath(
          widget.gameToEdit!.coverImageFileName,
        ).then((path) => setState(() => _coverImagePath = path));
      }
    }
    // 获取焦点以支持键盘事件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pathController.dispose();
    _saveDataPathController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickExecutable() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'msi'],
        dialogTitle: '选择游戏可执行文件',
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path!;
        _pathController.text = filePath;

        // 如果标题为空，使用文件名作为默认标题
        if (_titleController.text.isEmpty) {
          final fileName = path.basenameWithoutExtension(filePath);
          _titleController.text = fileName;
        }
      }
    } catch (e) {
      Snacks.error('选择文件失败: $e');
    }
  }

  Future<void> _pickSaveDataPath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择存档文件夹',
      );

      if (selectedDirectory != null) {
        _saveDataPathController.text = selectedDirectory;
      }
    } catch (e) {
      Snacks.error('选择文件夹失败: $e');
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: '选择封面图片',
        allowedExtensions: null,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _coverImagePath = result.files.first.path!;
          _coverImageChanged = true;
        });
      }
    } catch (e) {
      Snacks.error('选择图片失败: $e');
    }
  }

  Future<void> _pasteImageFromClipboard() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        Snacks.error('此平台不支持剪切板功能');
        return;
      }

      final reader = await clipboard.read();

      // 检查剪切板中是否有PNG图像
      if (reader.canProvide(Formats.png)) {
        reader.getFile(Formats.png, (file) async {
          try {
            final stream = file.getStream();
            final bytes = <int>[];

            await for (final chunk in stream) {
              bytes.addAll(chunk);
            }

            // 保存图像到临时文件
            final tempDir = Directory.systemTemp;
            final tempFile = File(
              '${tempDir.path}/temp_cover_${DateTime.now().millisecondsSinceEpoch}.png',
            );

            await tempFile.writeAsBytes(bytes);

            setState(() {
              _coverImagePath = tempFile.path;
              _coverImageChanged = true;
            });
          } catch (e) {
            Snacks.error('处理剪切板图像失败: $e');
          }
        });
      } else {
        Snacks.error('剪切板中没有图像数据');
      }
    } catch (e) {
      Snacks.error('读取剪切板失败: $e');
    }
  }

  void _removeCoverImage() {
    setState(() {
      _coverImagePath = null;
      _coverImageChanged = true;
    });
  }

  Future<void> _searchGameOnIGDB() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      Snacks.error('请先输入游戏标题');
      return;
    }

    final url = 'https://www.igdb.com/search?q=$title';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        Snacks.error('无法打开浏览器');
      }
    } catch (e) {
      Snacks.error('打开链接失败: $e');
    }
  }

  Future<void> _saveGame() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? savedCoverPath;
      final gameId =
          widget.gameToEdit?.id ??
          DateTime.now().millisecondsSinceEpoch.toString();

      // 处理封面图片更新
      if (_coverImageChanged) {
        // 如果是编辑模式且有旧封面，先删除旧封面
        if (widget.gameToEdit != null &&
            widget.gameToEdit!.coverImageFileName != null) {
          await GameStorage.deleteGameCover(
            widget.gameToEdit!.coverImageFileName!,
          );
        }

        // 如果选择了新的封面图片，保存它
        if (_coverImagePath != null) {
          savedCoverPath = await GameStorage.saveGameCover(
            _coverImagePath!,
            gameId,
          );
        } else {
          // 用户删除了封面，设置为null
          savedCoverPath = null;
        }
      } else {
        // 封面没有变化，保持原有文件名
        savedCoverPath = widget.gameToEdit?.coverImageFileName;
      }

      final game = Game(
        id: gameId,
        title: _titleController.text.trim(),
        executablePath: _pathController.text.trim(),
        coverImageFileName: savedCoverPath,
        saveDataPath: _saveDataPathController.text.trim().isEmpty
            ? null
            : _saveDataPathController.text.trim(),
        createdAt: widget.gameToEdit?.createdAt ?? DateTime.now(),
        playCount: widget.gameToEdit?.playCount ?? 0,
        totalPlaytime: widget.gameToEdit?.totalPlaytime ?? Duration.zero,
        lastPlayedAt: widget.gameToEdit?.lastPlayedAt
      );

      // 使用GetX来管理状态
      if (widget.gameToEdit != null) {
        await gameController.updateGame(game);
      } else {
        await gameController.addGame(game);
      }

      if(mounted) {
        Get.until((route) => !Get.isDialogOpen!);
      }
    } catch (e) {
      Snacks.error('保存游戏失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inversePrimary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.gameToEdit != null ? '编辑游戏' : '添加游戏',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 封面图片预览和操作按钮
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 封面图片预览 - 放在左侧
                            Expanded(
                                flex: 2,
                                child: Container(alignment: Alignment.center,child: Stack(
                                  children: [
                                    Container(
                                      width: 200,
                                      height: 200 / 0.75, // 使用0.75比例
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey,
                                          width: 2,
                                          style: BorderStyle.solid,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey[50],
                                      ),
                                      child: _coverImagePath != null
                                          ? ClipRRect(
                                        borderRadius:
                                        BorderRadius.circular(6),
                                        child: Image.file(
                                          File(_coverImagePath!),
                                          key: ValueKey(_coverImagePath!),
                                          fit: BoxFit.cover,
                                          width: 200,
                                          height: 200 / 0.75,
                                        ),
                                      )
                                          : const Center(
                                        child: Column(
                                          mainAxisAlignment:
                                          MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_photo_alternate,
                                              size: 48,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              '暂无封面图片',
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // 删除按钮（仅在有图片时显示）
                                    if (_coverImagePath != null)
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: _removeCoverImage,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                              BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),)
                            ),
                            const SizedBox(width: 16),
                            // 操作按钮 - 放在右侧
                            Expanded(
                              flex: 1,
                              child: SizedBox(height: 200/0.75, child: Column(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _pickCoverImage,
                                    icon: const Icon(Icons.image),
                                    label: const Text('选择封面'),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _pasteImageFromClipboard,
                                    icon: const Icon(Icons.paste),
                                    label: const Text('粘贴封面'),
                                  ),
                                ],
                              ),),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 游戏标题
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: '游戏标题',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: _searchGameOnIGDB,
                              icon: const Icon(Icons.search),
                              tooltip: '在 IGDB 上搜索',
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入游戏标题';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // 可执行文件路径
                        TextFormField(
                          controller: _pathController,
                          decoration: InputDecoration(
                            labelText: '可执行文件路径',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: _pickExecutable,
                              icon: const Icon(Icons.folder_open),
                            ),
                          ),
                          readOnly: true,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请选择可执行文件';
                            }
                            if (!GameLauncher.isExecutable(value)) {
                              return '请选择有效的可执行文件 (.exe 或 .msi)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // 存档路径
                        TextFormField(
                          controller: _saveDataPathController,
                          decoration: InputDecoration(
                            labelText: '存档路径 (可选)',
                            hintText: '选择游戏存档文件夹',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: _pickSaveDataPath,
                              icon: const Icon(Icons.folder_open),
                            ),
                          ),
                          readOnly: true,
                        ),
                        const SizedBox(height: 24),

                        // 保存按钮
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveGame,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                              : Text(
                            widget.gameToEdit != null ? '更新游戏' : '添加游戏',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
