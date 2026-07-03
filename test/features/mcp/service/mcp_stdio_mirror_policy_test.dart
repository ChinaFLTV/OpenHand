import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_stdio_mirror_mode.dart';
import 'package:openhand/features/mcp/service/mcp_stdio_mirror_policy.dart';

void main() {
  group('resolveMcpMirrorEffectiveSourceFromValues', () {
    test('uses shared boolean parsing for environment override aliases', () {
      expect(
        resolveMcpMirrorEffectiveSourceFromValues(
          environmentOverride: 'enabled',
          modeOverride: McpStdioMirrorMode.forceOff,
          localeName: 'en_US',
        ),
        McpMirrorEffectiveSource.envOn,
      );
      expect(
        resolveMcpMirrorEffectiveSourceFromValues(
          environmentOverride: 'no',
          modeOverride: McpStdioMirrorMode.forceOn,
          localeName: 'zh_CN',
        ),
        McpMirrorEffectiveSource.envOff,
      );
    });

    test(
      'falls back to setting override when environment override is invalid',
      () {
        expect(
          resolveMcpMirrorEffectiveSourceFromValues(
            environmentOverride: 'auto',
            modeOverride: McpStdioMirrorMode.forceOn,
            localeName: 'en_US',
          ),
          McpMirrorEffectiveSource.settingForceOn,
        );
        expect(
          resolveMcpMirrorEffectiveSourceFromValues(
            environmentOverride: '',
            modeOverride: McpStdioMirrorMode.forceOff,
            localeName: 'zh_CN',
          ),
          McpMirrorEffectiveSource.settingForceOff,
        );
      },
    );

    test('uses locale when setting is auto or not yet available', () {
      expect(
        resolveMcpMirrorEffectiveSourceFromValues(
          environmentOverride: null,
          modeOverride: McpStdioMirrorMode.auto,
          localeName: 'zh_Hans_CN',
        ),
        McpMirrorEffectiveSource.autoLocaleZh,
      );
      expect(
        resolveMcpMirrorEffectiveSourceFromValues(
          environmentOverride: null,
          modeOverride: null,
          localeName: 'en_US',
        ),
        McpMirrorEffectiveSource.autoLocaleOther,
      );
    });
  });
}
