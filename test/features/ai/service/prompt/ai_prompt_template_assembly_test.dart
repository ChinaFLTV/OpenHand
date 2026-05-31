import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_assembly.dart';

void main() {
  test('shared section selection excludes workflow for hermes and all for machine expert', () {
    expect(
      aiPromptSharedSectionsForTemplate('machine_expert'),
      isEmpty,
    );

    final hermes = aiPromptSharedSectionsForTemplate('hermes_talker');
    expect(hermes.map((item) => item.tag), isNot(contains('workflow')));

    final programming = aiPromptSharedSectionsForTemplate('programming_expert');
    expect(programming.map((item) => item.tag), contains('workflow'));
  });

  test('detects chinese instructions with cjk threshold heuristic', () {
    expect(aiPromptInstructionsLooksLikeChinese('Atomic Change Discipline'), isFalse);
    expect(
      aiPromptInstructionsLooksLikeChinese('你是一个简洁高效的助手，请保持结构化输出。'),
      isTrue,
    );
  });

  test('detects v4 discipline markers from headings and xml tags', () {
    expect(
      aiPromptInstructionsHasV4DisciplineMarker(
        '## Atomic Change Discipline\nKeep changes focused.',
      ),
      isTrue,
    );
    expect(
      aiPromptInstructionsHasV4DisciplineMarker(
        '<uncertainty_honesty>Say when unsure.</uncertainty_honesty>',
      ),
      isTrue,
    );
    expect(
      aiPromptInstructionsHasV4DisciplineMarker('Plain instructions only.'),
      isFalse,
    );
  });

  test('appends shared sections only when xml tag is absent', () {
    final assembled = appendAiPromptSharedSectionsIfAbsent(
      '<identity>existing</identity>\nBase',
      const <AiPromptLoadedSection>[
        AiPromptLoadedSection(tag: 'identity', content: '<identity>new</identity>'),
        AiPromptLoadedSection(tag: 'workflow', content: '<workflow>Do work</workflow>'),
      ],
    );

    expect(assembled, contains('<identity>existing</identity>'));
    expect(assembled, isNot(contains('<identity>new</identity>')));
    expect(assembled, contains('<workflow>Do work</workflow>'));
  });

  test('appends v4 discipline using language-appropriate snippet only once', () {
    final english = appendAiPromptV4DisciplineIfAbsent(
      'Keep answers concise.',
      zhSnippet: '## 通用纪律\n中文',
      enSnippet: '## Atomic Change Discipline\nEnglish',
    );
    expect(english, contains('## Atomic Change Discipline'));
    expect(english, isNot(contains('## 通用纪律')));

    final chinese = appendAiPromptV4DisciplineIfAbsent(
      '请保持输出简洁。',
      zhSnippet: '## 通用纪律\n中文',
      enSnippet: '## Atomic Change Discipline\nEnglish',
    );
    expect(chinese, contains('## 通用纪律'));
    expect(chinese, isNot(contains('## Atomic Change Discipline')));

    final untouched = appendAiPromptV4DisciplineIfAbsent(
      '## Atomic Change Discipline\nExisting',
      zhSnippet: '## 通用纪律\n中文',
      enSnippet: '## Atomic Change Discipline\nEnglish',
    );
    expect(untouched, equals('## Atomic Change Discipline\nExisting'));
  });

  test('appends memory tone policy only when absent', () {
    final appended = appendAiPromptMemoryTonePolicyIfAbsent('Base instructions.');
    expect(appended, contains('## Memory Tone Policy'));

    final untouched = appendAiPromptMemoryTonePolicyIfAbsent(
      '## Memory Tone Policy\nAlready present.',
    );
    expect(untouched, equals('## Memory Tone Policy\nAlready present.'));
  });
}
