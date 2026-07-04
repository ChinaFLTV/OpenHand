import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';

void main() {
  group('AiPromptTemplateInfo locale labels', () {
    test('resolve localized names without Flutter UI dependencies', () {
      final info = AiPromptTemplatePolicies.entries.first.info;

      expect(info.nameForLocale(const _TestLocale('zh')), '默认助手');
      expect(
        info.nameForLocale(const _TestLocale('zh', scriptCode: 'Hant')),
        '預設助手',
      );
      expect(
        info.nameForLocale(const _TestLocale('fr')),
        'Assistant par défaut',
      );
      expect(info.nameForLocale(const _TestLocale('es')), 'Default Assistant');
    });
  });
}

class _TestLocale {
  const _TestLocale(this.languageCode, {this.scriptCode});

  final String languageCode;
  final String? scriptCode;
}
