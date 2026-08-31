import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/csv_encoding.dart';

void main() {
  test('普通值保持紧凑，特殊字符按 CSV 规则转义', () {
    expect(encodeCsvCell('plain'), 'plain');
    expect(encodeCsvCell('a,b'), '"a,b"');
    expect(encodeCsvCell('a"b'), '"a""b"');
    expect(encodeCsvCell('a\r\nb'), '"a\r\nb"');
    expect(encodeCsvCell(null), '');
  });

  test('字符串公式统一转为纯文本且不影响负数', () {
    expect(encodeCsvCell('=1+1'), "'=1+1");
    expect(encodeCsvCell('  @SUM(A1:A2)'), "'  @SUM(A1:A2)");
    expect(encodeCsvCell('\t=1+1'), "'\t=1+1");
    expect(encodeCsvCell(-5), '-5');
  });

  test('行与文档编码复用相同规则', () {
    expect(encodeCsvRow(<Object?>['a', 'b,c']), 'a,"b,c"');
    expect(
      encodeCsvRows(<List<Object?>>[
        <Object?>['name', 'value'],
        <Object?>['示例', '+cmd'],
      ]),
      "name,value\r\n示例,'+cmd",
    );
    expect(encodeCsvRow(<Object?>['a', 'b'], alwaysQuote: true), '"a","b"');
  });
}
