import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_message_metadata.dart';

void main() {
  test('object normalizes loose map keys', () {
    final value = KnowledgeMessageMetadata.object(<Object?, Object?>{
      1: 'numeric-key',
      'prompt_append': <Object?, Object?>{'chunk_count': '1'},
    });

    expect(value, isNotNull);
    expect(value!['1'], 'numeric-key');
    expect((value['prompt_append'] as Map)['chunk_count'], '1');
  });

  test('object keeps invalid JSON as null while accepting JSON objects', () {
    expect(KnowledgeMessageMetadata.object('not-json'), isNull);
    expect(KnowledgeMessageMetadata.object('[1, 2]'), isNull);
    expect(
      KnowledgeMessageMetadata.object('{"enabled": true, "status": "success"}'),
      <String, Object?>{'enabled': true, 'status': 'success'},
    );
  });
}
