/// WebSearch 与 WebFetch 引擎适配器共用的 HTTP 异常。
class WebEngineHttpException implements Exception {
  WebEngineHttpException(this.message);

  final String message;

  @override
  String toString() => 'WebEngineHttpException: $message';
}
