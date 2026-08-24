/// 构造期 / 入口处的入参约束校验。
///
/// 收敛全库手写的 `ArgumentError.value(...)`：同一类约束只保留一份文案，
/// 避免同样的「必须大于零」在不同文件里出现中英混排与措辞漂移。
library;

const String _positiveMessage = '必须大于零。';
const String _nonNegativeMessage = '不能为负。';

/// 时长必须为正；零与负值都视为非法配置，直接抛出而不是静默回落。
void requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, _positiveMessage);
  }
}

/// 时长必须为正且不能超过 [maximum]。
void requirePositiveDurationAtMost(
  Duration value,
  Duration maximum,
  String name,
) {
  requirePositiveDuration(value, name);
  if (value > maximum) {
    throw ArgumentError.value(value, name, '不能超过 $maximum。');
  }
}

/// 时长允许为零（表示「不等待」），但不允许为负。
void requireNonNegativeDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, _nonNegativeMessage);
  }
}

/// 时长允许为零，但不能超过 [maximum]。
void requireNonNegativeDurationAtMost(
  Duration value,
  Duration maximum,
  String name,
) {
  requireNonNegativeDuration(value, name);
  if (value > maximum) {
    throw ArgumentError.value(value, name, '不能超过 $maximum。');
  }
}

/// 数值必须为正；用于容量、并发度、字节上限一类不允许为零的配置。
void requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, _positiveMessage);
  }
}

/// 数值必须为正且不能超过 [maximum]。
void requirePositiveIntAtMost(int value, int maximum, String name) {
  requirePositiveInt(value, name);
  if (value > maximum) {
    throw ArgumentError.value(value, name, '不能超过 $maximum。');
  }
}

/// 数值允许为零，但不允许为负。
void requireNonNegativeInt(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, _nonNegativeMessage);
  }
}

/// 数值允许为零，但不能超过 [maximum]。
void requireNonNegativeIntAtMost(int value, int maximum, String name) {
  requireNonNegativeInt(value, name);
  if (value > maximum) {
    throw ArgumentError.value(value, name, '不能超过 $maximum。');
  }
}

/// 两个可选依赖不能同时提供，避免发布版因 `assert` 被移除而产生歧义。
void requireAtMostOneProvided({
  required Object? firstValue,
  required String firstName,
  required Object? secondValue,
  required String secondName,
}) {
  if (firstValue != null && secondValue != null) {
    throw ArgumentError('$firstName 与 $secondName 不能同时提供。');
  }
}
