import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  group('UserMemoryEntry', () {
    test('userProfile entries are flagged', () {
      final entry = UserMemoryEntry(
        id: UserMemoryEntry.userProfileEntryId,
        type: UserMemoryEntry.userProfileType,
        createdAt: DateTime.utc(2026, 4, 25),
        content: 'User is a Flutter developer.',
        tags: const [],
      );
      expect(entry.isUserProfile, isTrue);
      expect(entry.isAutoLearned, isFalse);
    });

    test('autoLearned tag is detected', () {
      final entry = UserMemoryEntry(
        id: 'm-1',
        type: UserMemoryEntry.userType,
        createdAt: DateTime.utc(2026, 4, 25),
        content: 'preference: prefers concise code reviews',
        tags: const [UserMemoryEntry.autoLearnedTag],
      );
      expect(entry.isAutoLearned, isTrue);
    });

    test('autoLearned tag detection is case-insensitive', () {
      final entry = UserMemoryEntry(
        id: 'm-ci',
        type: UserMemoryEntry.userType,
        createdAt: DateTime.utc(2026, 4, 25),
        content: 'case-insensitive tag match',
        tags: const ['AUTO', '自主学习'],
      );
      expect(entry.isAutoLearned, isTrue);
    });

    test('regular user entry is not flagged as profile or auto-learned', () {
      final entry = UserMemoryEntry(
        id: 'm-2',
        type: UserMemoryEntry.userType,
        createdAt: DateTime.utc(2026, 4, 25),
        content: 'Just a normal memory note.',
        tags: const ['manual'],
      );
      expect(entry.isUserProfile, isFalse);
      expect(entry.isAutoLearned, isFalse);
    });
  });
}
