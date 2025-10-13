import 'logging_service.dart';
import 'restic_service.dart';

class InitService {
  // 应用初始化
  static Future<void> initializeApp() async {
    LoggingService.instance.info('开始初始化应用...');
    
    try {
      // 1. 初始化 restic 仓库
      await _initializeResticRepositories();
      
      LoggingService.instance.info('应用初始化完成');
    } catch (e) {
      LoggingService.instance.info('应用初始化失败: $e');
    }
  }
  
  // 初始化 restic 仓库
  static Future<void> _initializeResticRepositories() async {
    try {
      // 看看本地仓库是否存在
      final localLatestSnapshot = await ResticService.getLatestSnapshot();
      if(localLatestSnapshot != null) {
        return;
      }
      // 初始化本地仓库
      final localInitialized = await ResticService.initLocalRepository();
      if (localInitialized) {
        LoggingService.instance.info('本地 restic 仓库初始化成功');
      } else {
        LoggingService.instance.info('本地 restic 仓库初始化失败或已存在');
      }
    } catch (e) {
      LoggingService.instance.info('初始化 restic 仓库失败: $e');
    }
  }
}