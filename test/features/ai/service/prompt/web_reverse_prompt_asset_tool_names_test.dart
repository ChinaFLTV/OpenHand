import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Web Reverse prompt assets do not hard-code unavailable cdp tool names',
    () {
      final files = <String>[
        'assets/prompts/web_reverse_expert/system_instructions.md',
        'assets/prompts/web_reverse_expert/developer_instructions.md',
        'assets/prompts/web_reverse_expert/snippets/hook_payload.js',
      ];
      const staleToolNames = <String>[
        'cdp_navigate',
        'cdp_list_network_requests',
        'cdp_get_network_request',
        'cdp_add_init_script',
        'cdp_evaluate',
        'cdp_get_console_messages',
        'cdp_export_har',
        'cdp_list_websocket_frames',
        'cdp_get_response_body',
        'cdp_close_pages',
      ];
      const ambiguousToolLikeNames = <String>[
        'OpenHand CDP Bridge',
        'CDP Bridge',
      ];

      for (final file in files) {
        final content = File(file).readAsStringSync();
        for (final name in staleToolNames) {
          expect(
            content,
            isNot(contains(name)),
            reason: '$file must not name $name',
          );
        }
        for (final name in ambiguousToolLikeNames) {
          expect(
            content,
            isNot(contains(name)),
            reason: '$file must not imply $name is callable',
          );
        }
      }
    },
  );
}
