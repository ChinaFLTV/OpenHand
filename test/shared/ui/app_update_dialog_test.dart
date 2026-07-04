import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/support/app_update_checker.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/app_update_dialog.dart';

void main() {
  Widget host({
    bool tickerEnabled = true,
    bool disableAnimations = false,
    AppUpdateDataSource dataSource = const _NotAvailableUpdateDataSource(),
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: TickerMode(enabled: tickerEnabled, child: child!),
        );
      },
      home: Builder(
        builder: (context) {
          return TextButton(
            onPressed: () {
              showAppUpdateDialog(
                context: context,
                appInfo: AppInfo.fallback(),
                dataSource: dataSource,
              );
            },
            child: const Text('open'),
          );
        },
      ),
    );
  }

  Finder appUpdatePhaseSwitcher() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is AnimatedSwitcher &&
          widget.switchInCurve == Curves.easeOutCubic &&
          widget.switchOutCurve == Curves.easeInCubic,
    );
  }

  testWidgets('App update dialog disables phase motion with ticker off', (
    tester,
  ) async {
    await tester.pumpWidget(host(tickerEnabled: false));
    await tester.tap(find.text('open'));
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      appUpdatePhaseSwitcher().first,
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });

  testWidgets(
    'App update dialog disables phase motion when animations are off',
    (tester) async {
      await tester.pumpWidget(host(disableAnimations: true));
      await tester.tap(find.text('open'));
      await tester.pump();

      final switcher = tester.widget<AnimatedSwitcher>(
        appUpdatePhaseSwitcher().first,
      );
      expect(switcher.duration, Duration.zero);
      expect(switcher.reverseDuration, Duration.zero);
    },
  );

  testWidgets('App update dialog settles progress without motion', (
    tester,
  ) async {
    final dataSource = _ProgressUpdateDataSource();
    await tester.pumpWidget(
      host(disableAnimations: true, dataSource: dataSource),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final downloadButton = find.ancestor(
      of: find.byIcon(Icons.download_rounded),
      matching: find.byType(FilledButton),
    );
    tester.widget<FilledButton>(downloadButton).onPressed!();
    await tester.pump();

    expect(find.text('42.0%'), findsOneWidget);

    dataSource.completeDownload();
    await tester.pump();
  });
}

class _NotAvailableUpdateDataSource implements AppUpdateDataSource {
  const _NotAvailableUpdateDataSource();

  @override
  Future<AppUpdateCheckResult> checkForUpdate(String currentVersion) async {
    return AppUpdateNotAvailable();
  }

  @override
  Future<void> downloadUpdate(
    AppReleaseInfo release, {
    required ValueChanged<double> onProgress,
    required ValueChanged<String> onFilePath,
  }) async {}
}

class _ProgressUpdateDataSource implements AppUpdateDataSource {
  final Completer<void> _downloadCompleter = Completer<void>();

  @override
  Future<AppUpdateCheckResult> checkForUpdate(String currentVersion) async {
    return AppUpdateAvailable(
      release: AppReleaseInfo(
        version: '9.9.9',
        tagName: 'v9.9.9',
        releaseName: 'OpenHand 9.9.9',
        releaseNotes: '',
        publishedAt: DateTime(2026),
        downloadUrl: 'https://example.com/openhand.zip',
        downloadSize: 1024,
      ),
    );
  }

  @override
  Future<void> downloadUpdate(
    AppReleaseInfo release, {
    required ValueChanged<double> onProgress,
    required ValueChanged<String> onFilePath,
  }) {
    onProgress(0.42);
    return _downloadCompleter.future;
  }

  void completeDownload() {
    if (!_downloadCompleter.isCompleted) {
      _downloadCompleter.complete();
    }
  }
}
