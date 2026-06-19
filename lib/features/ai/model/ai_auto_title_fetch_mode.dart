enum AiAutoTitleFetchMode {
  asynchronous('async'),
  synchronous('sync');

  const AiAutoTitleFetchMode(this.storageValue);

  final String storageValue;

  static AiAutoTitleFetchMode fromStorage(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    for (final mode in values) {
      if (mode.storageValue == normalized) {
        return mode;
      }
    }
    return AiAutoTitleFetchMode.asynchronous;
  }
}
