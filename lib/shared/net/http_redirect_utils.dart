/// Shared HTTP-redirect helpers used by both the AI chat client and the MCP
/// tool-discovery client. Centralised here to avoid drift between the two
/// hand-rolled redirect loops that previously carried byte-identical copies.
library;

/// Whether [statusCode] belongs to the set of HTTP status codes that must be
/// followed as a redirect (per RFC 7231 & 7538).
bool isRedirectStatusCode(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

/// Returns `true` when [target] crosses an origin boundary relative to
/// [source] (different scheme, host, or effective port). Used to decide
/// whether to strip sensitive headers before replaying the request.
bool isCrossOriginRedirect(Uri source, Uri target) {
  return source.scheme != target.scheme ||
      source.host != target.host ||
      effectivePort(source) != effectivePort(target);
}

/// Returns the effective port for [uri]: the explicit port if present,
/// otherwise the scheme's default (80 for http, 443 for https). Unknown
/// schemes return -1 so equality comparisons never silently match.
int effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => -1,
  };
}

/// Case-insensitive header lookup that returns the trimmed value, or an
/// empty string when the header is absent. Mirrors the lenient behaviour the
/// existing redirect loops expected from dart:io headers.
String readResponseHeader(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value.trim();
    }
  }
  return '';
}
