import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_pure_helpers.dart';

void main() {
  group('vlqDecode', () {
    test('空字符串返回空列表', () {
      expect(vlqDecode(''), <int>[]);
    });

    test('单字符 "A" 解码为 0', () {
      // Base64-VLQ 字母表 'A' 索引 0 → continuation=0, data=0,
      // 取出符号位后结果为 0。
      expect(vlqDecode('A'), [0]);
    });

    test('"AAAA" 解码为 [0,0,0,0] —— source-map segment 起点常见值', () {
      expect(vlqDecode('AAAA'), [0, 0, 0, 0]);
    });

    test('"C" 解码为 1（最小正数；数据位 1，符号位 0）', () {
      expect(vlqDecode('C'), [1]);
    });

    test('"D" 解码为 -1（数据位 1，符号位 1）', () {
      expect(vlqDecode('D'), [-1]);
    });

    test('"E" 解码为 2', () {
      expect(vlqDecode('E'), [2]);
    });

    test('多字节字段：超过 5 bit 需要 continuation', () {
      // 编码 32：先左移 1 位（符号）= 64 = 0b10_00000，
      //   低 5 bit = 0、设置 continuation → 'g'（索引 32）
      //   高位剩 2 → 'C'（索引 2）
      // 综合：'gC' 应该解码为 32。
      expect(vlqDecode('gC'), [32]);
      // 同理 'gB'（高位 1）解码为 16。
      expect(vlqDecode('gB'), [16]);
    });

    test('未知字符被跳过', () {
      // '!' 不在字母表 → 应被忽略，'A' 仍解码为 0。
      expect(vlqDecode('!A'), [0]);
    });
  });

  group('normalizeConsoleSignature', () {
    test('只取首行', () {
      expect(
        normalizeConsoleSignature('Uncaught Error\n    at foo (a.js:1:2)'),
        'Uncaught Error',
      );
    });

    test('ISO 时间戳 → <ts>', () {
      expect(
        normalizeConsoleSignature('2025-01-02T03:04:05.678Z fail'),
        '<ts> fail',
      );
    });

    test('十六进制 → <hex>', () {
      expect(
        normalizeConsoleSignature('addr=0xDEADBEEF crashed'),
        'addr=<hex> crashed',
      );
    });

    test('长数字 → <num>', () {
      expect(
        normalizeConsoleSignature('uid=987654 lost'),
        'uid=<num> lost',
      );
    });

    test('URL 路径中的哈希摘要 → /<hash>', () {
      expect(
        normalizeConsoleSignature('/static/abcdef0123456789/app.js miss'),
        '/static/<hash>/app.js miss',
      );
    });

    test('行列尾 :L:C) 占位（短行号不被 <num> 抢先匹配）', () {
      expect(
        normalizeConsoleSignature('boom (a.js:12:5)'),
        'boom (a.js:L:C)',
      );
    });

    test('连续空白压缩为单空格', () {
      expect(
        normalizeConsoleSignature('  spaced     out '),
        'spaced out',
      );
    });
  });
}
