class InstructionMarketEntry {
  const InstructionMarketEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.accent,
    required this.avatarUrl,
    required this.sourceKey,
    required this.body,
    this.interpretation = '',
    this.role = '',
    this.style = '',
    this.approach = '',
    this.tone = '',
    this.localizationKey,
  });
  final String id, name, description, category;
  final int accent;
  final String avatarUrl, sourceKey, body, interpretation;
  final String role, style, approach, tone;
  final String? localizationKey;
}

const kInstructionMarketCategoryAction = 'action';
const kInstructionMarketCategoryVitality = 'vitality';
const kInstructionMarketCategoryInsight = 'insight';
const kInstructionMarketCategoryCompanion = 'companion';
