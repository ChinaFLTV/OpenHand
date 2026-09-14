import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 按文件名后缀取图标。文件树、@ 提及和技能包清单共用，避免同一类文件
/// 在不同表面显示不同图标。
IconData openHandFileNameIcon(String fileName) {
  return switch (p.extension(fileName).toLowerCase()) {
    '.dart' ||
    '.py' ||
    '.go' ||
    '.rs' ||
    '.java' ||
    '.kt' ||
    '.swift' ||
    '.c' ||
    '.cpp' ||
    '.h' ||
    '.hpp' ||
    '.xml' => Icons.code_rounded,
    '.js' || '.jsx' || '.ts' || '.tsx' => Icons.javascript_rounded,
    '.json' => Icons.data_object_rounded,
    '.yaml' || '.yml' => Icons.settings_rounded,
    '.md' => Icons.article_rounded,
    '.html' || '.htm' || '.vue' => Icons.web_rounded,
    '.css' || '.scss' || '.less' => Icons.palette_rounded,
    '.png' ||
    '.jpg' ||
    '.jpeg' ||
    '.gif' ||
    '.svg' ||
    '.webp' => Icons.image_rounded,
    '.sh' || '.bash' || '.zsh' => Icons.terminal_rounded,
    '.lock' => Icons.lock_rounded,
    '.sql' => Icons.storage_rounded,
    '.txt' || '.log' => Icons.description_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}
