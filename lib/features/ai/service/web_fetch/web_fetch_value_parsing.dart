import '../web_engine/web_engine_value_parsing.dart';

double? webFetchScoreFromValue(Object? value) {
  return webEngineScoreFromValue(value);
}

int? webFetchHttpStatusFromValue(Object? value) {
  return webEngineHttpStatusFromValue(value);
}
