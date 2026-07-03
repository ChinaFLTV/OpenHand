import '../../../shared/util/input_value_parsing.dart';

enum AiAutoTitleFetchMode {
  asynchronous('async'),
  synchronous('sync');

  const AiAutoTitleFetchMode(this.storageValue);

  final String storageValue;

  static AiAutoTitleFetchMode fromStorage(String? value) {
    final normalized = lowercaseStringFromValue(value);
    for (final mode in values) {
      if (mode.storageValue == normalized) {
        return mode;
      }
    }
    return AiAutoTitleFetchMode.asynchronous;
  }
}
