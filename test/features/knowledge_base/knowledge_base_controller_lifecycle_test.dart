import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_settings_store.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_store.dart';
import 'package:openhand/features/knowledge_base/knowledge_base_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('dispose is idempotent and suppresses late notifications', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    final controller = KnowledgeBaseController(
      settingsStore: KnowledgeBaseSettingsStore(database: database),
      store: KnowledgeBaseStore(database: database),
    );

    controller.dispose();

    expect(controller.notifyListeners, returnsNormally);
    expect(controller.dispose, returnsNormally);
    await database.close();
  });
}
