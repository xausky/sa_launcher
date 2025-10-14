import 'package:get/get.dart';
import 'package:sa_launcher/controllers/game_controller.dart';
import 'package:sa_launcher/models/save_backup.dart';
import 'package:sa_launcher/services/save_backup_service.dart';

class BackupController extends GetxController {
  final String gameId;
  final backupMap = <String, SaveBackup>{}.obs;

  BackupController({
    required this.gameId
  });

  @override
  void onInit() {
    super.onInit();
    loadBackups();
  }

  Future<void> loadBackups() async {
    final backups = await SaveBackupService.getGameBackups(gameId);
    for(var backup in backups) {
      backupMap[backup.id] = backup;
    }
  }

  Future<void> newBackup(String name) async {
    final game = Get.find<GameController>().getGameById(gameId);
    if (game == null || game.saveDataPath == null) {
      return;
    }
    final backup = await SaveBackupService.createBackup(gameId, game.saveDataPath!, name);
    if(backup == null) {
      return;
    }
    backupMap[backup.id] = backup;
  }

  Future<void> applyBackup(SaveBackup backup) async {

  }

  Future<void> deleteBackup(SaveBackup backup) async {
    await SaveBackupService.deleteBackup(backup);
    backupMap.remove(backup.id);
  }
}