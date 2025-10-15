import 'package:get/get.dart';
import 'package:sa_launcher/controllers/game_list_controller.dart';
import 'package:sa_launcher/models/game.dart';

class GameController extends GetxController {
  final String gameId; // 传入要查看的游戏 ID
  final GameListController listController = Get.find<GameListController>();
  final game = Rx<Game?>(null);

  GameController({required this.gameId});

  @override
  void onInit() {
    super.onInit();
    game.value = listController.games[gameId];
    ever(listController.games, (Map<String, Game> games) {
      game.value = games[gameId];
    });
  }

}