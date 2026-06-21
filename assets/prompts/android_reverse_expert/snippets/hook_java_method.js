/**
 * hook_java_method.js
 * Hook 指定 Java 类方法的入参、返回值和调用栈。
 * 使用方式：替换 TARGET_CLASS / TARGET_METHOD，通过 Frida attach/spawn 注入。
 */
const TARGET_CLASS = 'com.example.TargetClass';
const TARGET_METHOD = 'targetMethod';

Java.perform(function () {
  const Cls = Java.use(TARGET_CLASS);
  const overloads = Cls[TARGET_METHOD].overloads;
  overloads.forEach(function (overload) {
    overload.implementation = function () {
      const args = Array.prototype.slice.call(arguments);
      const argsStr = args.map(function (a) {
        return JSON.stringify(a != null ? a.toString() : null);
      }).join(', ');
      console.log('[OH_JAVA] ' + TARGET_CLASS + '.' + TARGET_METHOD +
        '(' + argsStr + ')');
      const ret = overload.apply(this, arguments);
      console.log('[OH_JAVA] => ' + (ret != null ? ret.toString() : 'null'));
      const stack = Java.use('android.util.Log')
        .getStackTraceString(Java.use('java.lang.Exception').$new());
      console.log('[OH_JAVA] stack:\n' + stack);
      return ret;
    };
  });
});
