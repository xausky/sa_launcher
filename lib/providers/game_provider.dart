import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game.dart';
import '../services/game_storage.dart';
import '../services/cloud_backup_service.dart';

// 游戏列表状态管理
class GameListNotifier extends AsyncNotifier<List<Game>> {
  @override
  Future<List<Game>> build() async {
    return await GameStorage.getGames();
  }

  // 加载游戏列表
  Future<void> loadGames() async {
    state = const AsyncValue.loading();
    try {
      final games = await GameStorage.getGames();
      state = AsyncValue.data(games);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // 添加游戏
  Future<void> addGame(Game game) async {
    try {
      await GameStorage.addGame(game);
      await loadGames(); // 重新加载列表

      // 触发自动上传到云端
      CloudBackupService.autoUploadToCloud();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // 更新游戏
  Future<void> updateGame(Game updatedGame) async {
    try {
      debugPrint('updateGame: ${updatedGame.toJson()}');
      await GameStorage.updateGame(updatedGame);
      await loadGames(); // 重新加载列表

      // 触发自动上传到云端
      CloudBackupService.autoUploadToCloud();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // 删除游戏
  Future<void> deleteGame(String gameId) async {
    try {
      // 先找到游戏以获取封面路径
      final currentState = state;
      if (currentState is AsyncData<List<Game>>) {
        final game = currentState.value.firstWhere((g) => g.id == gameId);

        // 删除封面图片
        if (game.coverImageFileName != null) {
          await GameStorage.deleteGameCover(game.coverImageFileName!);
        }
      }

      await GameStorage.deleteGame(gameId);
      await loadGames(); // 重新加载列表

      // 触发自动上传到云端
      CloudBackupService.autoUploadToCloud();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // 刷新游戏列表
  Future<void> refresh() async {
    await loadGames();
  }
}

// 游戏列表Provider
final gameListProvider = AsyncNotifierProvider<GameListNotifier, List<Game>>(
  () {
    return GameListNotifier();
  },
);

// 获取特定游戏的Provider
final gameByIdProvider = Provider.family<Game?, String>((ref, gameId) {
  final gameList = ref.watch(gameListProvider);
  return gameList.when(
    data: (games) => games.cast<Game?>().firstWhere(
      (game) => game?.id == gameId,
      orElse: () => null,
    ),
    loading: () => null,
    error: (_, __) => null,
  );
});
