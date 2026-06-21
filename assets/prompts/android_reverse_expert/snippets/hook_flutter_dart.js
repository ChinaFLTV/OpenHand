/**
 * hook_flutter_dart.js
 * Flutter/Dart AOT 逆向辅助 hook：配合 blutter / Doldrums 解析结果，
 * hook Dart VM snapshot 中已定位的函数地址（通过 NativePointer）。
 *
 * 使用方式：
 *   1. 用 blutter 解析 libapp.so 得到 Function 地址偏移
 *   2. 替换 LIBAPP_FUNC_OFFSET 为目标函数在 libapp.so 中的偏移量（hex）
 *   3. Frida spawn/attach 注入本脚本
 */
const LIBAPP_FUNC_OFFSET = '0x0'; // 替换为 blutter 输出的函数偏移

const libapp = Process.getModuleByName('libapp.so');
if (!libapp) {
  console.error('[OH_FLUTTER] libapp.so not loaded');
} else {
  const funcAddr = libapp.base.add(ptr(LIBAPP_FUNC_OFFSET));
  console.log('[OH_FLUTTER] hooking libapp.so+' + LIBAPP_FUNC_OFFSET + ' @ ' + funcAddr);

  Interceptor.attach(funcAddr, {
    onEnter: function (args) {
      console.log('[OH_FLUTTER] func enter, args[0]=' + args[0] +
        ' args[1]=' + args[1]);
      // Dart 对象通常以 tagged pointer 方式传递；打 hexdump 查看内存布局：
      // try { console.log(hexdump(args[0].add(-1), { length: 64 })); } catch(_) {}
    },
    onLeave: function (retval) {
      console.log('[OH_FLUTTER] func leave, retval=' + retval);
    },
  });
}
