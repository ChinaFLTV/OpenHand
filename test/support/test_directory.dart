import 'dart:io';

import 'package:openhand/shared/util/bounded_delete.dart';

const BoundedDeletePolicy _testDirectoryDeletePolicy = BoundedDeletePolicy(
  maxEntries: 100000,
  maxDepth: 128,
  operationTimeout: Duration(seconds: 5),
  totalTimeout: Duration(seconds: 30),
);

/// Idempotently removes a test-owned system-temporary directory without
/// following links or invoking an unbounded recursive delete.
Future<void> deleteTestDirectory(Directory directory) {
  return deletePathBounded(
    directory.path,
    policy: _testDirectoryDeletePolicy,
    allowedRoot: Directory.systemTemp.path,
  );
}
