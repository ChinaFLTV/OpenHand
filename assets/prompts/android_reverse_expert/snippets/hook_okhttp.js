/**
 * hook_okhttp.js
 * Hook OkHttp3 onResponse，打印完整 HTTP 请求/响应（URL、headers、body）。
 * 适用于 OkHttp 3.x / 4.x。
 */
Java.perform(function () {
  const OkHttpClient = Java.use('okhttp3.OkHttpClient');
  const Chain = Java.use('okhttp3.Interceptor$Chain');
  const RequestBody = Java.use('okhttp3.RequestBody');
  const ResponseBody = Java.use('okhttp3.ResponseBody');
  const Buffer = Java.use('okio.Buffer');

  // 用 network interceptor 拦截已压缩的真实流量
  OkHttpClient.networkInterceptors().forEach(function () {});
  // 通过 addNetworkInterceptor 无法 retroactively hook；改 intercept 直接 hook
  const intercept = Java.use('okhttp3.RealCall').getResponseWithInterceptorChain;
  if (intercept && intercept.overloads.length > 0) {
    intercept.overloads[0].implementation = function () {
      const resp = intercept.overloads[0].apply(this, arguments);
      try {
        const req = this.request();
        console.log('[OH_OKHTTP] url: ' + req.url().toString());
        console.log('[OH_OKHTTP] method: ' + req.method());
        const reqBody = req.body();
        if (reqBody) {
          const buf = Buffer.$new();
          reqBody.writeTo(buf);
          console.log('[OH_OKHTTP] req_body: ' + buf.readUtf8());
        }
        const bodyClone = resp.peekBody(1024 * 1024);
        console.log('[OH_OKHTTP] resp_code: ' + resp.code());
        console.log('[OH_OKHTTP] resp_body: ' + bodyClone.string());
      } catch (e) {
        console.error('[OH_OKHTTP] error: ' + e);
      }
      return resp;
    };
    console.log('[OH_OKHTTP] OkHttp3 RealCall intercepted');
  } else {
    console.error('[OH_OKHTTP] RealCall.getResponseWithInterceptorChain not found');
  }
});
