import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/git_operation_service.dart';

class GitLogPage extends ConsumerStatefulWidget {
  const GitLogPage({super.key});

  @override
  ConsumerState<GitLogPage> createState() => _GitLogPageState();
}

class _GitLogPageState extends ConsumerState<GitLogPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gitService = ref.watch(gitOperationServiceProvider);
    final operations = gitService.operations;
    final currentOperation = gitService.currentOperation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Git 操作日志'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: () {
              ref.read(gitOperationServiceProvider).clearHistory();
            },
            icon: const Icon(Icons.clear_all),
            tooltip: '清除历史',
          ),
        ],
      ),
      body: Column(
        children: [
          // 当前操作状态
          if (currentOperation != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getStatusColor(currentOperation.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getStatusColor(currentOperation.status),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getStatusIcon(currentOperation.status),
                        color: _getStatusColor(currentOperation.status),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前操作: ${currentOperation.fullCommand}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(currentOperation.status),
                          ),
                        ),
                      ),
                      if (currentOperation.status == GitOperationStatus.running)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '工作目录: ${currentOperation.workingDirectory}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '开始时间: ${_formatDateTime(currentOperation.startTime)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (currentOperation.output != null && currentOperation.output!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '输出:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 100,
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              child: Text(
                                currentOperation.output!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (currentOperation.error != null && currentOperation.error!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '错误:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentOperation.error!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // 历史操作列表
          Expanded(
            child: operations.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '暂无 Git 操作历史',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: operations.length,
                    itemBuilder: (context, index) {
                      final operation = operations[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          leading: Icon(
                            _getStatusIcon(operation.status),
                            color: _getStatusColor(operation.status),
                          ),
                          title: Text(
                            operation.fullCommand,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${_formatDateTime(operation.startTime)} - ${operation.workingDirectory}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Text(
                            _getStatusText(operation.status),
                            style: TextStyle(
                              color: _getStatusColor(operation.status),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (operation.endTime != null)
                                    Text(
                                      '结束时间: ${_formatDateTime(operation.endTime!)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (operation.output != null && operation.output!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '输出:',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        operation.output!,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (operation.error != null && operation.error!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '错误:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        operation.error!,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(GitOperationStatus status) {
    switch (status) {
      case GitOperationStatus.running:
        return Colors.blue;
      case GitOperationStatus.success:
        return Colors.green;
      case GitOperationStatus.error:
        return Colors.red;
      case GitOperationStatus.idle:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(GitOperationStatus status) {
    switch (status) {
      case GitOperationStatus.running:
        return Icons.play_arrow;
      case GitOperationStatus.success:
        return Icons.check_circle;
      case GitOperationStatus.error:
        return Icons.error;
      case GitOperationStatus.idle:
        return Icons.pause_circle;
    }
  }

  String _getStatusText(GitOperationStatus status) {
    switch (status) {
      case GitOperationStatus.running:
        return '运行中';
      case GitOperationStatus.success:
        return '成功';
      case GitOperationStatus.error:
        return '失败';
      case GitOperationStatus.idle:
        return '空闲';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }
}