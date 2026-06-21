/**
 * hook_native_func.js
 * Hook Native (JNI / so) 导出函数，打 NativePointer 地址、参数 hexdump、返回值。
 * 使用方式：替换 LIB_NAME / FUNC_NAME，通过 Frida attach/spawn 注入。
 */
const LIB_NAME = 'libexample.so';
const FUNC_NAME = 'Java_com_example_NativeClass_nativeMethod';

const lib = Process.getModuleByName(LIB_NAME);
const funcAddr = lib.getExportByName(FUNC_NAME);

if (funcAddr) {
  Interceptor.attach(funcAddr, {
    onEnter: function (args) {
      this.arg0 = args[0];
      this.arg1 = args[1];
      console.log('[OH_NATIVE] ' + FUNC_NAME + ' enter');
      console.log('[OH_NATIVE] arg[0]: ' + args[0]);
      console.log('[OH_NATIVE] arg[1]: ' + args[1]);
      // hexdump 第三个参数（若为 buffer pointer）：
      // console.log(hexdump(args[2], { length: 64 }));
    },
    onLeave: function (retval) {
      console.log('[OH_NATIVE] ' + FUNC_NAME + ' leave => ' + retval);
    },
  });
  console.log('[OH_NATIVE] hooked: ' + FUNC_NAME + ' @ ' + funcAddr);
} else {
  console.error('[OH_NATIVE] export not found: ' + FUNC_NAME + ' in ' + LIB_NAME);
}
