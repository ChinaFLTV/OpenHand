import '../../../../shared/util/input_value_parsing.dart';

const int _minHttpStatusCode = 100;
const int _maxHttpStatusCode = 599;

double? webFetchScoreFromValue(Object? value) {
  return optionalNonNegativeDoubleFromValue(value);
}

int? webFetchHttpStatusFromValue(Object? value) {
  final parsed = optionalIntegralIntFromValue(value);
  if (parsed == null) return null;
  if (parsed < _minHttpStatusCode || parsed > _maxHttpStatusCode) {
    return null;
  }
  return parsed;
}
