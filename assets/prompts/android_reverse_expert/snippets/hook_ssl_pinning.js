/**
 * hook_ssl_pinning.js
 * 绕过常见 SSL Pinning 方案：
 *   1. X509TrustManager checkServerTrusted — 清空验证
 *   2. OkHttp3 CertificatePinner check — 清空验证
 *   3. javax.net.ssl.HostnameVerifier verify — 强制返回 true
 * 注：需设备已安装 mitmproxy / Burp CA 为用户证书。
 */
Java.perform(function () {
  // --- 1. X509TrustManager ---
  try {
    const X509TrustManager = Java.use('javax.net.ssl.X509TrustManager');
    const SSLContext = Java.use('javax.net.ssl.SSLContext');
    const TrustManagerImpl = Java.use(
      'com.android.org.conscrypt.TrustManagerImpl',
    );
    TrustManagerImpl.checkTrustedRecursive.implementation = function () {
      console.log('[OH_SSL] TrustManagerImpl.checkTrustedRecursive bypassed');
    };
  } catch (e) {
    console.log('[OH_SSL] TrustManagerImpl bypass skipped: ' + e);
  }

  // --- 2. OkHttp3 CertificatePinner ---
  try {
    const CertificatePinner = Java.use('okhttp3.CertificatePinner');
    CertificatePinner.check.overloads.forEach(function (overload) {
      overload.implementation = function () {
        console.log('[OH_SSL] OkHttp3 CertificatePinner.check bypassed');
      };
    });
  } catch (e) {
    console.log('[OH_SSL] OkHttp3 CertificatePinner bypass skipped: ' + e);
  }

  // --- 3. HostnameVerifier ---
  try {
    const HostnameVerifier = Java.use('javax.net.ssl.HostnameVerifier');
    Java.enumerateLoadedClasses({
      onMatch: function (className) {
        try {
          const cls = Java.use(className);
          if (cls.verify && cls.verify.overloads) {
            cls.verify.overloads.forEach(function (overload) {
              if (overload.argumentTypes.length === 2) {
                overload.implementation = function () {
                  console.log('[OH_SSL] HostnameVerifier.verify bypassed: ' + className);
                  return true;
                };
              }
            });
          }
        } catch (_) {}
      },
      onComplete: function () {},
    });
  } catch (e) {
    console.log('[OH_SSL] HostnameVerifier bypass skipped: ' + e);
  }

  console.log('[OH_SSL] SSL Pinning bypass loaded');
});
