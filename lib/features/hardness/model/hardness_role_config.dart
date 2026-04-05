import 'dart:convert';

class HardnessRoleConfig {
  const HardnessRoleConfig({
    required this.cliName,
    required this.modelId,
  });

  final String cliName;
  final String modelId;

  bool get isConfigured => cliName.trim().isNotEmpty && modelId.trim().isNotEmpty;

  HardnessRoleConfig copyWith({String? cliName, String? modelId}) {
    return HardnessRoleConfig(
      cliName: cliName ?? this.cliName,
      modelId: modelId ?? this.modelId,
    );
  }

  Map<String, Object?> toJson() => {'cli_name': cliName, 'model_id': modelId};

  static HardnessRoleConfig fromJson(Map<String, Object?> json) {
    return HardnessRoleConfig(
      cliName: '${json['cli_name'] ?? ''}',
      modelId: '${json['model_id'] ?? ''}',
    );
  }

  static HardnessRoleConfig get empty => const HardnessRoleConfig(cliName: '', modelId: '');

  @override
  String toString() => jsonEncode(toJson());
}
