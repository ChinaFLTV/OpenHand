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

/// highlight / 代码编辑器用的语言名。无法识别时返回 null，由调用方退回纯文本。
String? openHandEditorLanguageFromFileName(String fileName) {
  return switch (p.extension(fileName).toLowerCase()) {
    '.dart' => 'dart',
    '.py' => 'python',
    '.js' || '.jsx' => 'javascript',
    '.ts' || '.tsx' => 'typescript',
    '.json' => 'json',
    '.yaml' || '.yml' => 'yaml',
    '.md' => 'markdown',
    '.html' || '.htm' => 'html',
    '.css' => 'css',
    '.scss' => 'scss',
    '.less' => 'less',
    '.xml' => 'xml',
    '.sql' => 'sql',
    '.go' => 'go',
    '.rs' => 'rust',
    '.java' => 'java',
    '.kt' => 'kotlin',
    '.swift' => 'swift',
    '.c' => 'c',
    '.cpp' || '.cc' || '.cxx' || '.h' || '.hpp' => 'cpp',
    '.sh' || '.bash' || '.zsh' => 'bash',
    '.rb' => 'ruby',
    '.php' => 'php',
    '.lua' => 'lua',
    '.r' => 'r',
    '.toml' || '.ini' || '.cfg' => 'ini',
    '.gradle' || '.groovy' => 'groovy',
    '.dockerfile' => 'dockerfile',
    _ => null,
  };
}

const Set<String> _kOpenHandNonTextPreviewExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
  '.mp4',
  '.webm',
  '.mov',
  '.m4v',
  '.mkv',
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.flac',
  '.pdf',
  '.zip',
  '.gz',
  '.tgz',
  '.7z',
  '.rar',
  '.woff',
  '.woff2',
  '.ttf',
  '.otf',
  '.eot',
  '.exe',
  '.dll',
  '.so',
  '.dylib',
  '.bin',
  '.xlsx',
  '.xls',
  '.doc',
  '.docx',
  '.ppt',
  '.pptx',
};

/// 明显不是文本的后缀（图片、音视频、字体、压缩包等），不丢进代码编辑器。
bool openHandFileNameLooksLikeBinary(String fileName) {
  return _kOpenHandNonTextPreviewExtensions.contains(
    p.extension(fileName).toLowerCase(),
  );
}
