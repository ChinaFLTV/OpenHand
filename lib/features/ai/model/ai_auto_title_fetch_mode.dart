import '../../../shared/util/input_value_parsing.dart';

enum AiAutoTitleFetchMode {
  asynchronous('async'),
  synchronous('sync');

  const AiAutoTitleFetchMode(this.storageValue);

  final String storageValue;

  static AiAutoTitleFetchMode fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (mode) => mode.storageValue,
      fallback: AiAutoTitleFetchMode.asynchronous,
      normalize: (item) => item.toLowerCase(),
    );
  }
}
