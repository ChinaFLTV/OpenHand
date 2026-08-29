import '../../../shared/util/text_normalization.dart';

enum OpenHandSlashCommandKind {
  help,
  feedback,
  newSession,
  status,
  stop,
  settings,
  workspace,
  skills,
  memory,
  mcp,
  crons,
}

class OpenHandSlashCommand {
  const OpenHandSlashCommand({required this.kind, this.argument = ''});

  final OpenHandSlashCommandKind kind;
  final String argument;
}

OpenHandSlashCommand? parseOpenHandSlashCommand(String rawInput) {
  final trimmed = rawInput.trim();
  if (!trimmed.startsWith('/')) {
    return null;
  }
  final parts = trimmed.split(kInlineWhitespacePattern);
  if (parts.isEmpty) {
    return null;
  }
  final commandToken = parts.first.toLowerCase();
  final argument = trimmed.substring(parts.first.length).trim();
  final kind = switch (commandToken) {
    '/help' || '/commands' => OpenHandSlashCommandKind.help,
    '/feedback' || '/report' => OpenHandSlashCommandKind.feedback,
    '/new' => OpenHandSlashCommandKind.newSession,
    '/status' => OpenHandSlashCommandKind.status,
    '/stop' || '/abort' || '/cancel' => OpenHandSlashCommandKind.stop,
    '/settings' || '/config' => OpenHandSlashCommandKind.settings,
    '/workspace' ||
    '/sessions' ||
    '/chat' => OpenHandSlashCommandKind.workspace,
    '/skills' => OpenHandSlashCommandKind.skills,
    '/memory' => OpenHandSlashCommandKind.memory,
    '/mcp' => OpenHandSlashCommandKind.mcp,
    '/crons' || '/cron' => OpenHandSlashCommandKind.crons,
    _ => null,
  };
  if (kind == null) {
    return null;
  }
  return OpenHandSlashCommand(kind: kind, argument: argument);
}
