const int kRollingHash30Mask = 0x3fffffff;
const int kRollingHashPositive31BitMask = 0x7fffffff;
const int kRollingHash31Multiplier = 31;

int rollingHashWithMask<T>(
  Iterable<T> values,
  int Function(T value) hashOf, {
  int seed = 0,
  int mask = kRollingHash30Mask,
}) {
  final safeMask = mask < 0 ? kRollingHash30Mask : mask;
  var hash = seed & safeMask;
  for (final value in values) {
    hash = (hash * kRollingHash31Multiplier + hashOf(value)) & safeMask;
  }
  return hash;
}

int rollingHash30<T>(
  Iterable<T> values,
  int Function(T value) hashOf, {
  int seed = 0,
}) => rollingHashWithMask(values, hashOf, seed: seed);

int rollingHashPositive31Bit<T>(
  Iterable<T> values,
  int Function(T value) hashOf, {
  int seed = 0,
}) => rollingHashWithMask(
  values,
  hashOf,
  seed: seed,
  mask: kRollingHashPositive31BitMask,
);
