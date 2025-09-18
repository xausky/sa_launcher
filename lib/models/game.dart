import 'package:flutter/material.dart';

class Game {
  final String id;
  final String title;
  final String executablePath;
  final String? coverImageFileName;
  final String? saveDataPath;
  final DateTime createdAt;

  Game({
    required this.id,
    required this.title,
    required this.executablePath,
    this.coverImageFileName,
    this.saveDataPath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'executablePath': executablePath,
      'coverImageFileName': coverImageFileName,
      'saveDataPath': saveDataPath,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'],
      title: json['title'],
      executablePath: json['executablePath'],
      coverImageFileName: json['coverImageFileName'],
      saveDataPath: json['saveDataPath'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
    );
  }

  Game copyWith({
    String? id,
    String? title,
    String? executablePath,
    String? coverImageFileName,
    String? saveDataPath,
    DateTime? createdAt,
  }) {
    return Game(
      id: id ?? this.id,
      title: title ?? this.title,
      executablePath: executablePath ?? this.executablePath,
      coverImageFileName: coverImageFileName ?? this.coverImageFileName,
      saveDataPath: saveDataPath ?? this.saveDataPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
