/**
 * hook_aes_cbc.js
 * Hook javax.crypto.Cipher doFinal，截取 AES/CBC（或其他对称加密）的明文输入/输出。
 */
Java.perform(function () {
  const Cipher = Java.use('javax.crypto.Cipher');
  const ByteString = Java.use('com.android.okhttp.okio.ByteString');

  Cipher.doFinal.overloads.forEach(function (overload) {
    overload.implementation = function () {
      const args = Array.prototype.slice.call(arguments);
      const algorithm = this.getAlgorithm();
      if (algorithm && (
        algorithm.indexOf('AES') >= 0 ||
        algorithm.indexOf('DES') >= 0 ||
        algorithm.indexOf('RSA') >= 0
      )) {
        console.log('[OH_CRYPTO] Cipher.doFinal algorithm: ' + algorithm);
        if (args.length > 0 && args[0]) {
          const inputHex = Array.from(args[0])
            .map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); })
            .join('');
          console.log('[OH_CRYPTO] input_hex: ' + inputHex);
          try {
            console.log('[OH_CRYPTO] input_utf8: ' + Java.use('java.lang.String')
              .$new(args[0], 'UTF-8'));
          } catch (_) {}
        }
      }
      const result = overload.apply(this, arguments);
      if (result && algorithm && algorithm.indexOf('AES') >= 0) {
        const outHex = Array.from(result)
          .map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); })
          .join('');
        console.log('[OH_CRYPTO] output_hex: ' + outHex);
      }
      return result;
    };
  });
  console.log('[OH_CRYPTO] Cipher.doFinal hooked');
});
