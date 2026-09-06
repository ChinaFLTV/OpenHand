import '../util/input_value_parsing.dart';

const int kTcpPortMin = 1;
const int kTcpPortMax = 65535;

bool isValidTcpPort(int? port) {
  return port != null && port >= kTcpPortMin && port <= kTcpPortMax;
}

int? validTcpPort(int? port) {
  return isValidTcpPort(port) ? port : null;
}

int clampTcpPort(int port) {
  return port.clamp(kTcpPortMin, kTcpPortMax);
}

int? tcpPortFromValue(Object? value) {
  return validTcpPort(optionalIntFromValue(value));
}

int tcpPortFromValueOr(Object? value, {required int fallback}) {
  return tcpPortFromValue(value) ?? fallback;
}

int clampedTcpPortFromValue(Object? value, {required int fallback}) {
  return clampTcpPort(optionalIntFromValue(value) ?? fallback);
}

int? tcpPortFromText(String value) {
  return validTcpPort(optionalIntFromText(value));
}

int tcpPortFromTextOr(String value, {required int fallback}) {
  return tcpPortFromText(value) ?? fallback;
}
