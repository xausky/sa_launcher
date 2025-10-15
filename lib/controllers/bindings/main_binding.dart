import 'package:get/get.dart';
import 'package:sa_launcher/controllers/game_list_controller.dart';
import 'package:sa_launcher/controllers/game_process_controller.dart';

class MainBinding implements Bindings {
  @override
  void dependencies() {
    // 初始化游戏控制器
    Get.put<GameListController>(GameListController(), permanent: true);
    
    // 初始化游戏进程控制器
    Get.put<GameProcessController>(GameProcessController(), permanent: true);
  }
}