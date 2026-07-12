import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/service/web_fetch/web_fetch_http_utils.dart';

void main() {
  test('bounded WebFetch responses cancel oversized streams', () async {
    final cancelled = Completer<void>();
    final controller = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    );
    final response = http.StreamedResponse(controller.stream, 200);
    final collected = collectBoundedWebFetchResponse(
      response,
      responseTimeout: const Duration(seconds: 1),
      maxBytes: 4,
    );

    controller.add(const <int>[1, 2, 3, 4, 5]);

    await expectLater(collected, throwsA(isA<HttpException>()));
    await cancelled.future.timeout(const Duration(seconds: 1));
    await controller.close();
  });

  test('error previews stay compact', () {
    final response = BoundedWebFetchHttpResponse(
      statusCode: 500,
      headers: const <String, String>{},
      bodyBytes: Uint8List.fromList(List<int>.filled(5000, 0x61)),
      requestUrl: null,
    );

    expect(response.errorPreview(), endsWith('…'));
    expect(response.errorPreview().length, lessThanOrEqualTo(2000));
  });
}
