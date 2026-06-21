/**
 * hook_webview.js
 * Hook Android WebView loadUrl / evaluateJavascript，监控 JS 桥通信。
 */
Java.perform(function () {
  const WebView = Java.use('android.webkit.WebView');

  WebView.loadUrl.overloads.forEach(function (overload) {
    overload.implementation = function () {
      const args = Array.prototype.slice.call(arguments);
      console.log('[OH_WEBVIEW] loadUrl: ' + args[0]);
      return overload.apply(this, arguments);
    };
  });

  WebView.evaluateJavascript.overloads.forEach(function (overload) {
    overload.implementation = function () {
      const args = Array.prototype.slice.call(arguments);
      console.log('[OH_WEBVIEW] evaluateJavascript: ' + args[0]);
      return overload.apply(this, arguments);
    };
  });

  // Hook JS->Native 桥（addJavascriptInterface）
  WebView.addJavascriptInterface.overloads.forEach(function (overload) {
    overload.implementation = function () {
      const args = Array.prototype.slice.call(arguments);
      console.log('[OH_WEBVIEW] addJavascriptInterface name: ' + args[1]);
      return overload.apply(this, arguments);
    };
  });

  console.log('[OH_WEBVIEW] WebView hooked');
});
