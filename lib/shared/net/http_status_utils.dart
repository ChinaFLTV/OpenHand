/// 通用 HTTP 状态分类工具，不包含领域诊断文案。
library;

const int kHttpSuccessStatusMin = 200;
const int kHttpSuccessStatusMax = 299;
const int kHttpRequestTimeoutStatusCode = 408;
const int kHttpConflictStatusCode = 409;
const int kHttpTooEarlyStatusCode = 425;
const int kHttpTooManyRequestsStatusCode = 429;
const int kHttpInternalServerErrorStatusCode = 500;
const int kHttpBadGatewayStatusCode = 502;
const int kHttpServiceUnavailableStatusCode = 503;
const int kHttpGatewayTimeoutStatusCode = 504;
const int kHttpServerErrorStatusMin = kHttpInternalServerErrorStatusCode;
const int kHttpServerErrorStatusMax = 599;

/// 瞬时失败、适合有限次自动重试的状态码（不含 409 冲突与其余 5xx）。
const Set<int> kHttpTransientRetryableStatusCodes = <int>{
  kHttpRequestTimeoutStatusCode,
  kHttpTooEarlyStatusCode,
  kHttpTooManyRequestsStatusCode,
  kHttpInternalServerErrorStatusCode,
  kHttpBadGatewayStatusCode,
  kHttpServiceUnavailableStatusCode,
  kHttpGatewayTimeoutStatusCode,
};

bool isHttpSuccessStatus(int statusCode) {
  return statusCode >= kHttpSuccessStatusMin &&
      statusCode <= kHttpSuccessStatusMax;
}

bool isHttpFailureStatus(int statusCode) {
  return !isHttpSuccessStatus(statusCode);
}

bool isHttpServerErrorStatus(int statusCode) {
  return statusCode >= kHttpServerErrorStatusMin &&
      statusCode <= kHttpServerErrorStatusMax;
}

bool isHttpTransientRetryableStatus(int statusCode) {
  return kHttpTransientRetryableStatusCodes.contains(statusCode);
}
