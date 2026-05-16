/// WebSearch / WebFetch 引擎适配器抛出的统一 HTTP 异常。
///
/// 之前 web_search 包用 `HttpException`、web_fetch 包用 `WebFetchHttpException`，
/// 两个类型完全平行，导致跨包调用 / 公共 catch 链无法共用。统一到这里。
class WebEngineHttpException implements Exception {
  WebEngineHttpException(this.message);

  final String message;

  @override
  String toString() => 'WebEngineHttpException: $message';
}
