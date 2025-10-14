import 'package:get/get.dart';
import 'game_controller.dart';
import 'game_process_controller.dart';
import 'game_stats_controller.dart';

class ControllersBinding implements Bindings {
  @override
  void dependencies() {
    // 初始化游戏控制器
    Get.put<GameController>(GameController(), permanent: true);
    
    // 初始化游戏进程控制器
    Get.put<GameProcessController>(GameProcessController(), permanent: true);
    
    // 初始化游戏统计控制器
    Get.put<GameStatsController>(GameStatsController(), permanent: true);
  }
}