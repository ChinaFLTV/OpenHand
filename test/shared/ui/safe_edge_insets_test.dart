import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/safe_edge_insets.dart';

void main() {
  test('openHandNonNegativeInsets clamps invalid sides independently', () {
    expect(
      openHandNonNegativeInsets(
        const EdgeInsets.fromLTRB(-1, double.nan, 4, 0),
      ),
      const EdgeInsets.fromLTRB(0, 0, 4, 0),
    );
  });

  testWidgets(
    'openHandResolvedInsetsOrFallback uses fallback for any bad side',
    (tester) async {
      late EdgeInsets resolved;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              resolved = openHandResolvedInsetsOrFallback(
                context,
                const EdgeInsetsDirectional.fromSTEB(8, -1, 12, 4),
                const EdgeInsets.all(6),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, const EdgeInsets.all(6));
    },
  );
}
