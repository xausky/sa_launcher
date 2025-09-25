import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game.dart';
import '../providers/game_provider.dart';

// 获取按游戏时长排序的游戏列表
final gamesSortedByPlaytimeProvider = Provider<List<Game>>((ref) {
  final gamesAsync = ref.watch(gameListProvider);
  return gamesAsync.when(
    data: (games) {
      final sortedGames = List<Game>.from(games);
      sortedGames.sort((a, b) => b.totalPlaytime.compareTo(a.totalPlaytime));
      return sortedGames;
    },
    loading: () => [],
    error: (error, stackTrace) => [],
  );
});

// 获取最近游玩的游戏列表
final recentlyPlayedGamesProvider = Provider<List<Game>>((ref) {
  final gamesAsync = ref.watch(gameListProvider);
  return gamesAsync.when(
    data: (games) {
      final recentlyPlayedGames = games
          .where((game) => game.lastPlayedAt != null)
          .toList();

      recentlyPlayedGames.sort(
        (a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!),
      );

      return recentlyPlayedGames.take(10).toList();
    },
    loading: () => [],
    error: (error, stackTrace) => [],
  );
});

// 获取总游戏时长
final totalPlaytimeProvider = Provider<Duration>((ref) {
  final gamesAsync = ref.watch(gameListProvider);
  return gamesAsync.when(
    data: (games) {
      Duration total = Duration.zero;

      for (final game in games) {
        total += game.totalPlaytime;
      }

      return total;
    },
    loading: () => Duration.zero,
    error: (error, stackTrace) => Duration.zero,
  );
});

// 获取游戏数量统计
final gameCountStatsProvider = Provider<Map<String, int>>((ref) {
  final gamesAsync = ref.watch(gameListProvider);
  return gamesAsync.when(
    data: (games) {
      int totalGames = games.length;
      int playedGames = games.where((game) => game.playCount > 0).length;
      int recentlyPlayedGames = games
          .where(
            (game) =>
                game.lastPlayedAt != null &&
                DateTime.now().difference(game.lastPlayedAt!).inDays <= 7,
          )
          .length;

      return {
        'total': totalGames,
        'played': playedGames,
        'recentlyPlayed': recentlyPlayedGames,
      };
    },
    loading: () => {'total': 0, 'played': 0, 'recentlyPlayed': 0},
    error: (error, stackTrace) => {
      'total': 0,
      'played': 0,
      'recentlyPlayed': 0,
    },
  );
});
