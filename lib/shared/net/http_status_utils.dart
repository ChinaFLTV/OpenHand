/// Shared HTTP status helpers for code paths that only need generic status
/// classification instead of domain-specific diagnostic messages.
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
