import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:super_clipboard/super_clipboard.dart';
import '../models/game.dart';
import '../providers/game_provider.dart';
import '../services/game_storage.dart';
import '../services/game_launcher.dart';

class AddGamePage extends StatefulWidget {
  final Game? gameToEdit;
  final WidgetRef ref;

  const AddGamePage({super.key, this.gameToEdit, required this.ref});

  @override
  State<AddGamePage> createState() => _AddGamePageState();
}

class _AddGamePageState extends State<AddGamePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _pathController = TextEditingController();
  final _focusNode = FocusNode();

  String? _coverImagePath;
  bool _isLoading = false;
  bool _coverImageChanged = false; // 标记封面是否有变化

  @override
  void initState() {
    super.initState();
    if (widget.gameToEdit != null) {
      _titleController.text = widget.gameToEdit!.title;
      _pathController.text = widget.gameToEdit!.executablePath;
      _coverImagePath = widget.gameToEdit!.coverImagePath;
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
      _showErrorDialog('选择文件失败: $e');
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
      _showErrorDialog('选择图片失败: $e');
    }
  }

  Future<void> _pasteImageFromClipboard() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        _showErrorDialog('此平台不支持剪切板功能');
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
            _showErrorDialog('处理剪切板图像失败: $e');
          }
        });
      } else {
        _showErrorDialog('剪切板中没有图像数据');
      }
    } catch (e) {
      _showErrorDialog('读取剪切板失败: $e');
    }
  }

  void _removeCoverImage() {
    setState(() {
      _coverImagePath = null;
      _coverImageChanged = true;
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Ctrl+Shift+V 粘贴
      if (event.logicalKey == LogicalKeyboardKey.keyV &&
          HardwareKeyboard.instance.isControlPressed &&
          HardwareKeyboard.instance.isShiftPressed) {
        _pasteImageFromClipboard();
        return true;
      }
      // Delete 键删除封面
      if (event.logicalKey == LogicalKeyboardKey.delete &&
          _coverImagePath != null) {
        _removeCoverImage();
        return true;
      }
    }
    return false;
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
            widget.gameToEdit!.coverImagePath != null) {
          await GameStorage.deleteGameCover(widget.gameToEdit!.coverImagePath!);
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
        // 封面没有变化，保持原有路径
        savedCoverPath = widget.gameToEdit?.coverImagePath;
      }

      final game = Game(
        id: gameId,
        title: _titleController.text.trim(),
        executablePath: _pathController.text.trim(),
        coverImagePath: savedCoverPath,
        createdAt: widget.gameToEdit?.createdAt ?? DateTime.now(),
      );

      // 使用Riverpod来管理状态
      if (widget.gameToEdit != null) {
        await widget.ref.read(gameListProvider.notifier).updateGame(game);
      } else {
        await widget.ref.read(gameListProvider.notifier).addGame(game);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showErrorDialog('保存游戏失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorDialog(String message) {
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

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: Dialog(
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
                      onPressed: () => Navigator.pop(context),
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
                          // 封面图片预览 - 使用和外部卡片相同的比例
                          Center(
                            child: GestureDetector(
                              onTap: _pickCoverImage,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Stack(
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
                                                    '点击选择封面图片',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    '或按 Ctrl+Shift+V 粘贴图像',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 12,
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
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 游戏标题
                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: '游戏标题',
                              border: OutlineInputBorder(),
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
      ),
    );
  }
}
