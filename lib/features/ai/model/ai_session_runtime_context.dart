import '../../../app/support/openhand_paths.dart';
import '../../mcp/model/mcp_server.dart';
import '../../memory/model/user_memory_entry.dart';
import '../../skills/model/local_skill.dart';
import 'ai_allow_command_rule.dart';
import 'ai_builtin_tool_config.dart';

class AiRepositorySnapshot {

  factory AiRepositorySnapshot.fromJson(Map<String, Object?> json) {
    final recentCommitsValue = json['recent_commits'];
    return AiRepositorySnapshot(
      workingDirectory: '${json['working_directory'] ?? ''}',
      isGitRepository: json['is_git_repository'] == true,
      repositoryRootPath: '${json['repository_root_path'] ?? ''}',
      currentBranch: '${json['current_branch'] ?? ''}',
      mainBranch: '${json['main_branch'] ?? ''}',
      statusSnapshot: '${json['status_snapshot'] ?? ''}',
      recentCommits: recentCommitsValue is List
          ? recentCommitsValue
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      capturedAtIso8601: '${json['captured_at'] ?? ''}',
    );
  }
  const AiRepositorySnapshot({
    required this.workingDirectory,
    required this.isGitRepository,
    this.repositoryRootPath = '',
    this.currentBranch = '',
    this.mainBranch = '',
    this.statusSnapshot = '',
    this.recentCommits = const <String>[],
    this.capturedAtIso8601 = '',
  });

  final String workingDirectory;
  final bool isGitRepository;
  final String repositoryRootPath;
  final String currentBranch;
  final String mainBranch;
  final String statusSnapshot;
  final List<String> recentCommits;
  final String capturedAtIso8601;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'working_directory': workingDirectory,
      'is_git_repository': isGitRepository,
      'repository_root_path': repositoryRootPath,
      'current_branch': currentBranch,
      'main_branch': mainBranch,
      'status_snapshot': statusSnapshot,
      'recent_commits': recentCommits,
      'captured_at': capturedAtIso8601,
    };
  }
}

class AiWorkspaceInstructionDocument {
  const AiWorkspaceInstructionDocument({
    required this.path,
    required this.name,
    required this.content,
  });

  final String path;
  final String name;
  final String content;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'name': name,
      'character_count': content.length,
    };
  }
}

class AiSessionRuntimeContext {
  const AiSessionRuntimeContext({
    required this.localeTag,
    required this.appVersion,
    required this.appBuildNumber,
    required this.settingsFilePath,
    required this.skillsStoragePath,
    required this.mcpServersFilePath,
    required this.userMemoryFilePath,
    required this.compressionThresholdChars,
    required this.memoryEnabled,
    required this.memoryEntries,
    this.templateId = '',
    this.singleRoundToolCallLimit = 40,
    this.sequentialToolRoundLimit = 24,
    this.imageSizeLimitBytes = 1024 * 1024,
    this.writeCommandConfirmationEnabled = true,
    this.connectTimeoutSeconds = 60,
    this.responseTimeoutSeconds = 120,
    this.streamIdleTimeoutSeconds = 120,
    this.autoTitleEnabled = true,
    this.telemetryDebugEnabled = false,
    this.telemetryCaptureRawPayload = true,
    this.telemetryCaptureEnvironment = false,
    this.telemetryMaxPayloadChars = 200000,
    this.platformName = '',
    this.workingDirectory = '',
    this.todayLocalDate = '',
    this.timeZoneName = '',
    this.repositorySnapshot,
    this.allowCommandRules = const <AiAllowCommandRule>[],
    this.availableSkills = const <LocalSkill>[],
    this.availableMcpServers = const <McpServer>[],
    this.builtinToolConfigs = const <AiBuiltinToolConfig>[],
    this.workspaceInstructionDocuments =
        const <AiWorkspaceInstructionDocument>[],
  });

  final String localeTag;
  final String appVersion;
  final String appBuildNumber;
  final String settingsFilePath;
  final String skillsStoragePath;
  final String mcpServersFilePath;
  final String userMemoryFilePath;
  final int compressionThresholdChars;
  final bool memoryEnabled;
  final List<UserMemoryEntry> memoryEntries;
  /// Identifier of the thread template currently active for this session.
  /// Used by the tool runtime to scope template-specific builtins such as
  /// `skill_manager` (Hermes Talker only).
  final String templateId;
  final int singleRoundToolCallLimit;
  final int sequentialToolRoundLimit;
  /// Per-image attachment size cap (bytes). When the user picks an image
  /// larger than this value, the attachment pipeline auto-compresses it
  /// before persisting and before the editor opens.
  final int imageSizeLimitBytes;
  final bool writeCommandConfirmationEnabled;
  /// HTTP connection/send timeout for AI requests (seconds).
  final int connectTimeoutSeconds;
  /// Response timeout for non-streaming AI requests (seconds).
  final int responseTimeoutSeconds;
  /// Per-chunk stream idle timeout for streaming AI requests (seconds).
  final int streamIdleTimeoutSeconds;
  /// Whether to auto-generate session titles.
  final bool autoTitleEnabled;
  /// Whether telemetry debug mode is enabled (populates request/response
  /// metadata on messages for the audit dialogs).
  final bool telemetryDebugEnabled;
  /// Whether to persist the raw AI response body alongside other telemetry.
  final bool telemetryCaptureRawPayload;
  /// Whether to capture process environment variables, working directory
  /// and platform info into message metadata. Off by default because env
  /// vars can contain secrets.
  final bool telemetryCaptureEnvironment;
  /// Hard cap on how many characters of captured payload to persist per
  /// message to keep on-disk session files bounded.
  final int telemetryMaxPayloadChars;
  final String platformName;
  final String workingDirectory;
  final String todayLocalDate;
  final String timeZoneName;
  final AiRepositorySnapshot? repositorySnapshot;
  final List<AiAllowCommandRule> allowCommandRules;
  final List<LocalSkill> availableSkills;
  final List<McpServer> availableMcpServers;
  final List<AiBuiltinToolConfig> builtinToolConfigs;
  final List<AiWorkspaceInstructionDocument> workspaceInstructionDocuments;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'locale_tag': localeTag,
      'app_version': appVersion,
      'app_build_number': appBuildNumber,
      'application_directory': OpenHandPaths.applicationDirectoryPath(),
      'home_directory': OpenHandPaths.homeDirectoryPath(),
      'settings_file_path': settingsFilePath,
      'skills_storage_path': skillsStoragePath,
      'mcp_servers_file_path': mcpServersFilePath,
      'user_memory_file_path': userMemoryFilePath,
      'sessions_directory_path': OpenHandPaths.defaultSessionsDirectoryPath(),
      'compression_threshold_chars': compressionThresholdChars,
      'single_round_tool_call_limit': singleRoundToolCallLimit,
      'sequential_tool_round_limit': sequentialToolRoundLimit,
      'image_size_limit_bytes': imageSizeLimitBytes,
      'write_command_confirmation_enabled': writeCommandConfirmationEnabled,
      'platform_name': platformName,
      'working_directory': workingDirectory,
      'today_local_date': todayLocalDate,
      'time_zone_name': timeZoneName,
      'memory_enabled': memoryEnabled,
      'memory_entry_count': memoryEntries.length,
      'available_skill_count': availableSkills.length,
      'available_skill_names': availableSkills
          .map((item) => item.name)
          .toList(growable: false),
      'allow_command_rule_count': allowCommandRules.length,
      'allow_command_patterns': allowCommandRules
          .map((item) => item.pattern)
          .toList(growable: false),
      'allow_command_rules': allowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'available_mcp_server_count': availableMcpServers.length,
      'available_mcp_server_names': availableMcpServers
          .map((item) => item.name)
          .toList(growable: false),
      'workspace_instruction_document_count':
          workspaceInstructionDocuments.length,
      'workspace_instruction_documents': workspaceInstructionDocuments
          .map((item) => item.toJson())
          .toList(growable: false),
      'repository_snapshot': repositorySnapshot?.toJson(),
    };
  }
}
