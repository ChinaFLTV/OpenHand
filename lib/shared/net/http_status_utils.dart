/// 通用 HTTP 状态分类工具，不包含领域诊断文案。
library;

const int kHttpSuccessStatusMin = 200;
const int kHttpSuccessStatusMax = 299;

bool isHttpSuccessStatus(int statusCode) {
  return statusCode >= kHttpSuccessStatusMin &&
      statusCode <= kHttpSuccessStatusMax;
}

bool isHttpFailureStatus(int statusCode) {
  return !isHttpSuccessStatus(statusCode);
}
