part of 'web_reverse_dashboard_dialog.dart';

const int _kNetworkBatchReplayLimit = 20;
const int _kNetworkBatchCurlCopyLimit = 100;

extension _WebReverseDashboardToolbar on _WebReverseDashboardDialogState {
  Widget _buildToolbar(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
    bool reduceMotion,
  ) {
    // 两行工具栏分别承载标签页与操作控件，窄窗口下保持可用。
    const tabs = _Tab.values;
    final showNetworkControls = _tab == _Tab.network;
    final showSearch = _tab == _Tab.network || _tab == _Tab.console;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 窄屏（< 720）折叠为下拉，避免横向滚动条挤压控件；宽屏照旧
          // 渲染所有 tab 胶囊 + 横向滚动作为兜底。
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 720;
              if (narrow) {
                return SizedBox(
                  height: _kToolbarHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ToolbarTabDropdown(
                      current: _tab,
                      tabs: tabs,
                      label: _tabLabel(context, _tab),
                      icon: _tabIcon(_tab),
                      count: _tabBadgeCount(_tab),
                      isZh: isZh,
                      reduceMotion: reduceMotion,
                      onChanged: _setTab,
                      labelFor: (t) => _tabLabel(context, t),
                      iconFor: _tabIcon,
                      countFor: _tabBadgeCount,
                    ),
                  ),
                );
              }
              return SizedBox(
                height: _kToolbarHeight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++) ...[
                        _ToolbarTabPill(
                          label: _tabLabel(context, tabs[i]),
                          icon: _tabIcon(tabs[i]),
                          count: _tabBadgeCount(tabs[i]),
                          active: _tab == tabs[i],
                          onTap: () => _setTab(tabs[i]),
                          reduceMotion: reduceMotion,
                        ),
                        if (i != tabs.length - 1) kOpenHandHGap6,
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          if (showSearch || showNetworkControls) ...[
            kOpenHandGap8,
            SizedBox(
              height: _kToolbarHeight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  children: [
                    if (showSearch) ...[
                      _ToolbarSearchField(
                        controller: _filterCtrl,
                        hint: _tab == _Tab.network
                            ? openHandLocalizedText(
                                context,
                                zh: '搜索 URL / 文本',
                                zhHant: '搜尋 URL / 文字',
                                en: 'Search URL / text',
                                fr: 'Rechercher URL / texte',
                                de: 'URL / Text suchen',
                                ja: 'URL / テキストを検索',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '搜索控制台',
                                zhHant: '搜尋主控台',
                                en: 'Search console',
                                fr: 'Rechercher dans la console',
                                de: 'Konsole durchsuchen',
                                ja: 'コンソールを検索',
                              ),
                        onChanged: (v) => rebuildFromExternal(
                          () => _networkFilter = v.trim(),
                        ),
                      ),
                      kOpenHandHGap8,
                    ],
                    if (showNetworkControls) ...[
                      _ToolbarTogglePill(
                        label: openHandLocalizedText(
                          context,
                          zh: '禁用缓存',
                          zhHant: '停用快取',
                          en: 'Disable cache',
                          fr: 'Désactiver le cache',
                          de: 'Cache deaktivieren',
                          ja: 'キャッシュを無効化',
                        ),
                        icon: Icons.no_drinks_rounded,
                        selected: ctrl.cacheDisabled,
                        onChanged: (v) async {
                          await ctrl.setCacheDisabled(v);
                        },
                        reduceMotion: reduceMotion,
                      ),
                      kOpenHandHGap8,
                      _ToolbarTogglePill(
                        label: openHandLocalizedText(
                          context,
                          zh: '保留日志',
                          zhHant: '保留記錄',
                          en: 'Preserve log',
                          fr: 'Conserver les journaux',
                          de: 'Protokoll beibehalten',
                          ja: 'ログを保持',
                        ),
                        icon: Icons.history_toggle_off_rounded,
                        selected: ctrl.preserveLog,
                        onChanged: (v) => ctrl.preserveLog = v,
                        reduceMotion: reduceMotion,
                      ),
                      kOpenHandHGap8,
                      _ToolbarThrottleButton(
                        value: ctrl.networkThrottlePreset,
                        onChanged: (preset) async {
                          final ok = await ctrl.setNetworkThrottling(preset);
                          if (!ok && mounted) {
                            showOpenHandErrorSnack(
                              context,
                              openHandLocalizedText(
                                context,
                                zh: '节流设置失败',
                                zhHant: '節流設定失敗',
                                en: 'Failed to set throttling',
                                fr: 'Échec du réglage de limitation',
                                de: 'Drosselung konnte nicht gesetzt werden',
                                ja: 'スロットリング設定に失敗しました',
                              ),
                              duration: kOpenHandSnackBarBriefDuration,
                            );
                          }
                        },
                      ),
                      kOpenHandHGap8,
                    ],
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '清空当前缓冲',
                        zhHant: '清空目前緩衝',
                        en: 'Clear buffers',
                        fr: 'Vider les tampons',
                        de: 'Puffer leeren',
                        ja: 'バッファをクリア',
                      ),
                      icon: Icons.cleaning_services_rounded,
                      onPressed: () {
                        ctrl.clearBuffers();
                        final st = _networkListKey.currentState;
                        if (st != null) rebuildFromExternal(() {});
                      },
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '导出 HAR 到本地文件',
                        zhHant: '匯出 HAR 到本機檔案',
                        en: 'Save HAR to file',
                        fr: 'Enregistrer le HAR',
                        de: 'HAR in Datei speichern',
                        ja: 'HAR をファイルに保存',
                      ),
                      icon: Icons.archive_rounded,
                      onPressed: () => _saveHarToFile(ctrl, isZh),
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '导入 HAR 反向加载',
                        zhHant: '匯入 HAR 反向載入',
                        en: 'Load HAR file',
                        fr: 'Charger un fichier HAR',
                        de: 'HAR-Datei laden',
                        ja: 'HAR ファイルを読み込む',
                      ),
                      icon: Icons.unarchive_rounded,
                      onPressed: () => _loadHarFromFile(ctrl, isZh),
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '截图（当前可视区）',
                        zhHant: '截圖（目前可視區）',
                        en: 'Screenshot (viewport)',
                        fr: 'Capture (zone visible)',
                        de: 'Screenshot (Viewport)',
                        ja: 'スクリーンショット（表示領域）',
                      ),
                      icon: Icons.photo_camera_outlined,
                      onPressed: () =>
                          _saveScreenshot(ctrl, isZh, fullPage: false),
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '截图（整页滚动拼接）',
                        zhHant: '截圖（整頁捲動拼接）',
                        en: 'Screenshot (full page)',
                        fr: 'Capture (page entière)',
                        de: 'Screenshot (ganze Seite)',
                        ja: 'スクリーンショット（ページ全体）',
                      ),
                      icon: Icons.picture_in_picture_rounded,
                      onPressed: () =>
                          _saveScreenshot(ctrl, isZh, fullPage: true),
                    ),
                    kOpenHandHGap8,
                    _ToolbarTogglePill(
                      label: openHandLocalizedText(
                        context,
                        zh: '请求拦截',
                        zhHant: '請求攔截',
                        en: 'Intercept',
                        fr: 'Intercepter',
                        de: 'Abfangen',
                        ja: 'インターセプト',
                      ),
                      icon: Icons.block_rounded,
                      selected: ctrl.isFetchInterceptEnabled,
                      onChanged: (v) async {
                        await ctrl.setFetchInterceptEnabled(v);
                      },
                      reduceMotion: reduceMotion,
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '批量操作（按当前过滤结果）',
                        zhHant: '批次操作（依目前篩選結果）',
                        en: 'Batch (current filter)',
                        fr: 'Lot (filtre actuel)',
                        de: 'Batch (aktueller Filter)',
                        ja: '一括操作（現在のフィルタ）',
                      ),
                      icon: Icons.dynamic_form_rounded,
                      onPressed: () => _showBatchActions(context, ctrl, isZh),
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: _webReverseDashHarDiffLabel(context),
                      icon: Icons.difference_rounded,
                      onPressed: () => _showHarDiff(context, isZh),
                    ),
                    kOpenHandHGap8,
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: 'Headless 批量采集',
                        zhHant: 'Headless 批量採集',
                        en: 'Headless batch',
                        fr: 'Lot headless',
                        de: 'Headless-Batch',
                        ja: 'Headless バッチ',
                      ),
                      icon: Icons.dynamic_feed_rounded,
                      onPressed: () => showWebReverseHeadlessBatchDialog(
                        context,
                        controller: ctrl,
                      ),
                    ),
                    kOpenHandHGap8,
                    // 高级菜单：把"持久 Header / 体检报告 / 原生 CDP / 反向脚本"
                    // 等低频但威力强的功能合到一颗按钮，避免 Toolbar 二行膨胀。
                    _ToolbarIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '高级工具',
                        zhHant: '進階工具',
                        en: 'Advanced',
                        fr: 'Avancé',
                        de: 'Erweitert',
                        ja: '詳細ツール',
                      ),
                      icon: Icons.tune_rounded,
                      onPressed: () => _showAdvancedMenu(context, ctrl, isZh),
                    ),
                    kOpenHandHGap8,
                    _ToolbarPrimaryPill(
                      icon: Icons.open_in_new_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '打开官方 DevTools',
                        zhHant: '開啟官方 DevTools',
                        en: 'Open DevTools',
                        fr: 'Ouvrir DevTools',
                        de: 'DevTools öffnen',
                        ja: 'DevTools を開く',
                      ),
                      onPressed: () => _openOfficialDevTools(ctrl),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _tabLabel(BuildContext context, _Tab t) => switch (t) {
    _Tab.browser => openHandBrowserLabel(context),
    _Tab.overview => openHandOverviewLabel(context),
    _Tab.network => openHandNetworkLabel(context),
    _Tab.console => _wrConsoleLabel(context),
    _Tab.sources => openHandLocalizedText(
      context,
      zh: '源码',
      zhHant: '原始碼',
      en: 'Sources',
      fr: 'Sources',
      de: 'Quellen',
      ja: 'ソース',
    ),
    _Tab.snippets => openHandLocalizedText(
      context,
      zh: '脚本',
      zhHant: '腳本',
      en: 'Snippets',
      fr: 'Extraits',
      de: 'Snippets',
      ja: 'スニペット',
    ),
    _Tab.elements => openHandLocalizedText(
      context,
      zh: '元素',
      zhHant: '元素',
      en: 'Elements',
      fr: 'Éléments',
      de: 'Elemente',
      ja: '要素',
    ),
    _Tab.hooks => openHandLocalizedText(
      context,
      zh: 'Hook',
      zhHant: 'Hook',
      en: 'Hooks',
      fr: 'Hooks',
      de: 'Hooks',
      ja: 'Hooks',
    ),
    _Tab.crons => openHandLocalizedText(
      context,
      zh: '定时',
      zhHant: '定時',
      en: 'Crons',
      fr: 'Tâches',
      de: 'Zeitpläne',
      ja: '定期実行',
    ),
    _Tab.breakpoints => openHandLocalizedText(
      context,
      zh: '断点',
      zhHant: '中斷點',
      en: 'Breakpoints',
      fr: 'Points d’arrêt',
      de: 'Haltepunkte',
      ja: 'ブレークポイント',
    ),
    _Tab.realtime => openHandLocalizedText(
      context,
      zh: '实时',
      zhHant: '即時',
      en: 'Realtime',
      fr: 'Temps réel',
      de: 'Echtzeit',
      ja: 'リアルタイム',
    ),
    _Tab.crypto => openHandLocalizedText(
      context,
      zh: '工具',
      zhHant: '工具',
      en: 'Crypto',
      fr: 'Crypto',
      de: 'Krypto',
      ja: '暗号',
    ),
    _Tab.performance => openHandLocalizedText(
      context,
      zh: '性能',
      zhHant: '效能',
      en: 'Performance',
      fr: 'Performance',
      de: 'Leistung',
      ja: 'パフォーマンス',
    ),
    _Tab.memory => openHandLocalizedText(
      context,
      zh: '内存',
      zhHant: '記憶體',
      en: 'Memory',
      fr: 'Mémoire',
      de: 'Speicher',
      ja: 'メモリ',
    ),
    _Tab.application => openHandLocalizedText(
      context,
      zh: '应用',
      zhHant: '應用',
      en: 'Application',
      fr: 'Application',
      de: 'Anwendung',
      ja: 'アプリケーション',
    ),
    _Tab.security => openHandLocalizedText(
      context,
      zh: '安全',
      zhHant: '安全',
      en: 'Security',
      fr: 'Sécurité',
      de: 'Sicherheit',
      ja: 'セキュリティ',
    ),
    _Tab.recorder => openHandLocalizedText(
      context,
      zh: '记录器',
      zhHant: '記錄器',
      en: 'Recorder',
      fr: 'Enregistreur',
      de: 'Recorder',
      ja: 'レコーダー',
    ),
  };

  IconData _tabIcon(_Tab t) => switch (t) {
    _Tab.browser => Icons.public_rounded,
    _Tab.overview => Icons.dashboard_rounded,
    _Tab.network => Icons.swap_horiz_rounded,
    _Tab.console => Icons.terminal_rounded,
    _Tab.sources => Icons.source_rounded,
    _Tab.snippets => Icons.code_rounded,
    _Tab.elements => Icons.account_tree_rounded,
    _Tab.hooks => Icons.fingerprint_rounded,
    _Tab.crons => Icons.schedule_rounded,
    _Tab.breakpoints => Icons.bug_report_outlined,
    _Tab.realtime => Icons.bolt_rounded,
    _Tab.crypto => Icons.enhanced_encryption_rounded,
    _Tab.performance => Icons.speed_rounded,
    _Tab.memory => Icons.memory_rounded,
    _Tab.application => Icons.apps_rounded,
    _Tab.security => Icons.shield_outlined,
    _Tab.recorder => Icons.fiber_manual_record_rounded,
  };

  int? _tabBadgeCount(_Tab t) {
    final c = widget.controller;
    return switch (t) {
      _Tab.browser => null,
      _Tab.overview => null,
      _Tab.network => c.networkRequestCount,
      _Tab.console => c.consoleMessageCount,
      _Tab.sources => c.parsedScripts.isEmpty ? null : c.parsedScripts.length,
      _Tab.snippets => c.snippets.isEmpty ? null : c.snippets.length,
      _ => null,
    };
  }

  Future<void> _saveHarToFile(
    WebReverseSessionController ctrl,
    bool isZh,
  ) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const typeGroup = XTypeGroup(label: 'HAR', extensions: <String>['har']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'web-reverse-$ts.har',
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择 HAR 保存位置', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '打开保存对话框失败',
          zhHant: '開啟儲存對話框失敗',
          en: 'Failed to open save dialog',
          fr: 'Impossible d’ouvrir la fenêtre d’enregistrement',
          de: 'Speicherdialog konnte nicht geöffnet werden',
          ja: '保存ダイアログを開けませんでした',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    if (location == null) return; // 用户取消
    String? written;
    try {
      written = await ctrl
          .exportHarToPath(location.path)
          .timeout(const Duration(seconds: 10));
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '导出 HAR 到文件', error, stack);
    }
    if (!mounted) return;
    if (written == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'HAR 保存失败或超时',
          zhHant: 'HAR 儲存失敗或逾時',
          en: 'HAR save failed or timed out',
          fr: 'Échec ou expiration de l’enregistrement HAR',
          de: 'HAR-Speichern fehlgeschlagen oder abgelaufen',
          ja: 'HAR の保存に失敗またはタイムアウトしました',
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
    } else {
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'HAR 已保存到 $written',
          zhHant: 'HAR 已儲存到 $written',
          en: 'HAR saved to $written',
          fr: 'HAR enregistré dans $written',
          de: 'HAR gespeichert unter $written',
          ja: 'HAR を $written に保存しました',
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
    }
  }

  Future<void> _saveScreenshot(
    WebReverseSessionController ctrl,
    bool isZh, {
    required bool fullPage,
  }) async {
    final bytes = fullPage
        ? await ctrl.captureFullPageScreenshot()
        : await ctrl.captureScreenshot();
    if (!mounted) return;
    if (bytes == null) {
      showOpenHandErrorSnack(
        context,
        _wrScreenshotFailedLabel(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    // 让用户在导出前先标注（涂鸦 / 矩形 / 文字）。
    final marked = await showScreenshotMarkupDialog(context, image: bytes);
    if (!mounted || marked == null) return;
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    const typeGroup = XTypeGroup(label: 'PNG', extensions: <String>['png']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'screenshot-${fullPage ? "full" : "viewport"}-$ts.png',
        acceptedTypeGroups: const [typeGroup],
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '选择截图保存位置', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '打开保存对话框失败',
          zhHant: '開啟儲存對話框失敗',
          en: 'Failed to open save dialog',
          fr: 'Impossible d’ouvrir la fenêtre d’enregistrement',
          de: 'Speicherdialog konnte nicht geöffnet werden',
          ja: '保存ダイアログを開けませんでした',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    if (location == null) return;
    try {
      await writeBytesFileAtomically(File(location.path), marked);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        webReverseSavedToFileMessage(context, location.path),
        duration: kOpenHandSnackBarNormalDuration,
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '写入截图', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '截图保存失败',
          zhHant: '截圖儲存失敗',
          en: 'Screenshot save failed',
          fr: 'Échec de l’enregistrement de la capture',
          de: 'Screenshot konnte nicht gespeichert werden',
          ja: 'スクリーンショットの保存に失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  Future<void> _loadHarFromFile(
    WebReverseSessionController ctrl,
    bool isZh,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'HAR',
      extensions: <String>['har', 'json'],
    );
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '打开 HAR 文件', error, stack);
    }
    if (file == null) return;
    // 当前缓冲非空时让用户选「替换」or「合并」；否则直接替换。
    bool merge = false;
    if (ctrl.networkRequests.isNotEmpty) {
      if (!mounted) return;
      final mode = await webReverseToolDialogs.show<String>(
        context: context,
        builder: (dialogContext) => buildOpenHandAlertDialog(
          title: Text(
            openHandLocalizedText(
              context,
              zh: '加载 HAR',
              zhHant: '載入 HAR',
              en: 'Load HAR',
              fr: 'Charger le HAR',
              de: 'HAR laden',
              ja: 'HAR を読み込む',
            ),
          ),
          content: Text(
            openHandLocalizedText(
              context,
              zh: '当前网络列表已有 ${ctrl.networkRequestCount} 条记录，选择加载方式：',
              zhHant: '目前網路清單已有 ${ctrl.networkRequestCount} 筆記錄，請選擇載入方式：',
              en: 'Network list has ${ctrl.networkRequestCount} entries. Choose load mode:',
              fr: 'La liste réseau contient ${ctrl.networkRequestCount} entrées. Choisissez le mode de chargement :',
              de: 'Die Netzwerkliste enthält ${ctrl.networkRequestCount} Einträge. Wähle den Lademodus:',
              ja: 'ネットワークリストには ${ctrl.networkRequestCount} 件あります。読み込み方法を選択してください:',
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              label: openHandCancelLabel(context),
            ),
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop('merge'),
              label: openHandLocalizedText(
                context,
                zh: '合并',
                zhHant: '合併',
                en: 'Merge',
                fr: 'Fusionner',
                de: 'Zusammenführen',
                ja: 'マージ',
              ),
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop('replace'),
              label: openHandLocalizedText(
                context,
                zh: '替换',
                zhHant: '取代',
                en: 'Replace',
                fr: 'Remplacer',
                de: 'Ersetzen',
                ja: '置換',
              ),
            ),
          ],
        ),
      );
      if (mode == null || mode == 'cancel') return;
      merge = mode == 'merge';
    }
    try {
      final read = await readWebReverseHarFile(file);
      if (read.isTooLarge) {
        if (!mounted) return;
        showOpenHandErrorSnack(
          context,
          webReverseHarTooLargeMessage(
            read.tooLargeBytes!,
            context: context,
            isZh: isZh,
          ),
          duration: kOpenHandSnackBarNormalDuration,
        );
        return;
      }
      final bytes = read.bytes!;
      final r = ctrl.loadHarBytes(bytes, merge: merge);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '${merge ? "合并" : "替换"}加载 ${r.loaded} 条；跳过 ${r.skipped} 条无效条目',
          zhHant:
              '${merge ? "合併" : "取代"}載入 ${r.loaded} 筆；略過 ${r.skipped} 筆無效項目',
          en: '${merge ? "Merged" : "Replaced"}: ${r.loaded}; skipped ${r.skipped}',
          fr: '${merge ? "Fusionné" : "Remplacé"} : ${r.loaded} ; ${r.skipped} ignorées',
          de: '${merge ? "Zusammengeführt" : "Ersetzt"}: ${r.loaded}; ${r.skipped} übersprungen',
          ja: '${merge ? "マージ" : "置換"}: ${r.loaded} 件、無効な ${r.skipped} 件をスキップ',
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '解析 HAR', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        _webReverseDashHarParseFailedLabel(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
    }
  }

  /// HAR 对比：选两个本地 HAR 文件做请求级差分，并升级为 body / status 二
  /// 级 diff。集合分四桶：
  ///   ① only-A / only-B —— 一边有另一边无；
  ///   ② changed —— 两份都有同一 (method,url) 但 status / body 至少一项变了，
  ///      其中 status 不同高亮成色块（蓝→红橙），body 大小或文本不同时
  ///      给出 size delta + 内容预览片段；
  ///   ③ same —— 完全一致，仅出计数。
  Future<void> _showHarDiff(BuildContext context, bool isZh) async {
    const typeGroup = XTypeGroup(
      label: 'HAR',
      extensions: <String>['har', 'json'],
    );
    XFile? aRaw;
    XFile? bRaw;
    try {
      aRaw = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (aRaw == null) return;
      bRaw = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '打开 HAR 对比文件', error, stack);
    }
    if (aRaw == null || bRaw == null || !context.mounted) return;
    final a = aRaw;
    final b = bRaw;

    /// 把一份 HAR 解析成 method+url → _HarEntrySummary 的 map。同一 url
    /// 多次出现只保留首条（用户面板上很少有同 url 重放需求）。
    Future<
      ({
        Map<String, _HarEntrySummary> map,
        int total,
        int parsed,
        int? tooLargeBytes,
      })?
    >
    parse(XFile f) async {
      try {
        final raw = await readWebReverseHarFile(f);
        if (raw.isTooLarge) {
          return (
            map: <String, _HarEntrySummary>{},
            total: 0,
            parsed: 0,
            tooLargeBytes: raw.tooLargeBytes,
          );
        }
        final bytes = raw.bytes!;
        final decoded = jsonDecode(utf8.decode(bytes));
        final entries = (decoded as Map?)?['log']?['entries'];
        if (entries is! List) return null;
        final map = <String, _HarEntrySummary>{};
        final total = entries.length;
        final parsed = math.min(total, kWebReverseHarDiffEntryLimit);
        for (final e in entries.take(parsed).whereType<Map>()) {
          final req = stringKeyedMapFromValue(e['request']);
          final res = stringKeyedMapFromValue(e['response']);
          final method = '${req['method'] ?? ''}';
          final url = '${req['url'] ?? ''}';
          final status = intFromValue(res['status'], fallback: 0);
          final content = stringKeyedMapFromValue(res['content']);
          final size = nonNegativeIntFromValue(content['size'], fallback: 0);
          final mime = '${content['mimeType'] ?? ''}';
          final text = content['text'] is String
              ? content['text'] as String
              : '';
          final digest = crypto.sha256.convert(utf8.encode(text)).toString();
          final key = '$method $url';
          map.putIfAbsent(
            key,
            () => _HarEntrySummary(
              method: method,
              url: url,
              status: status,
              bodySize: size,
              mimeType: mime,
              bodyText: clipText(text, kWebReverseHarDiffBodyPreviewChars),
              bodyDigest: digest,
            ),
          );
        }
        return (map: map, total: total, parsed: parsed, tooLargeBytes: null);
      } catch (error, stack) {
        silentLog('web_reverse_dashboard_dialog', '解析 HAR 对比文件', error, stack);
        return null;
      }
    }

    final setA = await parse(a);
    final setB = await parse(b);
    if (!context.mounted) return;
    final tooLargeBytes = setA?.tooLargeBytes ?? setB?.tooLargeBytes;
    if (tooLargeBytes != null) {
      showOpenHandErrorSnack(
        context,
        webReverseHarTooLargeMessage(
          tooLargeBytes,
          context: context,
          isZh: isZh,
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
      return;
    }
    if (setA == null || setB == null) {
      showOpenHandErrorSnack(
        context,
        _webReverseDashHarParseFailedLabel(context),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    final mapA = setA.map;
    final mapB = setB.map;
    final onlyAKeys = mapA.keys.toSet().difference(mapB.keys.toSet()).toList()
      ..sort();
    final onlyBKeys = mapB.keys.toSet().difference(mapA.keys.toSet()).toList()
      ..sort();
    final shared = mapA.keys.toSet().intersection(mapB.keys.toSet()).toList()
      ..sort();
    final changed = <_HarChange>[];
    var sameCount = 0;
    for (final k in shared) {
      final ea = mapA[k]!;
      final eb = mapB[k]!;
      final statusChanged = ea.status != eb.status;
      final sizeChanged = ea.bodySize != eb.bodySize;
      final textChanged = ea.bodyDigest != eb.bodyDigest;
      if (!statusChanged && !sizeChanged && !textChanged) {
        sameCount++;
      } else {
        changed.add(
          _HarChange(
            a: ea,
            b: eb,
            statusChanged: statusChanged,
            sizeChanged: sizeChanged,
            textChanged: textChanged,
          ),
        );
      }
    }
    if (!context.mounted) return;
    final capped = setA.parsed < setA.total || setB.parsed < setB.total;
    await showOpenHandInfoDialog(
      context: context,
      title: _webReverseDashHarDiffLabel(context),
      closeLabel: openHandCloseLabel(context),
      content: SizedBox(
        width: 880,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              openHandLocalizedText(
                context,
                zh: '一致 $sameCount 条 · 变化 ${changed.length} · A 独有 ${onlyAKeys.length} · B 独有 ${onlyBKeys.length}',
                zhHant:
                    '一致 $sameCount 筆 · 變更 ${changed.length} · A 獨有 ${onlyAKeys.length} · B 獨有 ${onlyBKeys.length}',
                en: '$sameCount same · ${changed.length} changed · ${onlyAKeys.length} only-A · ${onlyBKeys.length} only-B',
                fr: '$sameCount identiques · ${changed.length} changées · ${onlyAKeys.length} A seules · ${onlyBKeys.length} B seules',
                de: '$sameCount gleich · ${changed.length} geändert · ${onlyAKeys.length} nur A · ${onlyBKeys.length} nur B',
                ja: '$sameCount 件一致 · ${changed.length} 件変更 · A のみ ${onlyAKeys.length} · B のみ ${onlyBKeys.length}',
              ),
            ),
            if (capped) ...[
              kOpenHandGap4,
              Text(
                '${webReverseHarDiffCappedMessage(setA.parsed, setA.total, context: context, isZh: isZh)} · '
                '${webReverseHarDiffCappedMessage(setB.parsed, setB.total, context: context, isZh: isZh)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            kOpenHandGap8,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 220,
                    child: _HarDiffColumn(
                      title: openHandLocalizedText(
                        context,
                        zh: 'A 独有',
                        zhHant: 'A 獨有',
                        en: 'Only A',
                        fr: 'A seul',
                        de: 'Nur A',
                        ja: 'A のみ',
                      ),
                      items: onlyAKeys,
                      accent: Colors.red,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 220,
                    child: _HarDiffColumn(
                      title: openHandLocalizedText(
                        context,
                        zh: 'B 独有',
                        zhHant: 'B 獨有',
                        en: 'Only B',
                        fr: 'B seul',
                        de: 'Nur B',
                        ja: 'B のみ',
                      ),
                      items: onlyBKeys,
                      accent: Colors.green,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _HarChangedColumn(
                      title: openHandLocalizedText(
                        context,
                        zh: '同 URL 已变',
                        zhHant: '同 URL 已變更',
                        en: 'Changed',
                        fr: 'Modifiées',
                        de: 'Geändert',
                        ja: '変更あり',
                      ),
                      changes: changed,
                      isZh: isZh,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 网络面板批量操作：基于当前过滤结果一次性 block / 批量重放 / 批量复制
  /// curl。固化当前过滤结果（避免点开后过滤变了对不上）。
  void _showBatchActions(
    BuildContext context,
    WebReverseSessionController ctrl,
    bool isZh,
  ) {
    final filtered = _filteredNetworkEntries(ctrl);
    webReverseToolDialogs.show<void>(
      context: context,
      builder: (dialogContext) => buildOpenHandAlertDialog(
        title: Text(
          openHandLocalizedText(
            context,
            zh: '批量操作（${filtered.length} 条）',
            zhHant: '批次操作（${filtered.length} 筆）',
            en: 'Batch (${filtered.length})',
            fr: 'Lot (${filtered.length})',
            de: 'Batch (${filtered.length})',
            ja: '一括操作（${filtered.length} 件）',
          ),
        ),
        content: Text(
          openHandLocalizedText(
            context,
            zh: '基于当前网络面板的过滤结果进行批量操作：可批量屏蔽所有 URL（精确匹配）、批量重放（上限 $_kNetworkBatchReplayLimit 条）或复制 curl 列表（上限 $_kNetworkBatchCurlCopyLimit 条）。',
            zhHant:
                '依目前網路面板的篩選結果進行批次操作：可批次封鎖所有 URL（精確匹配）、批次重放（上限 $_kNetworkBatchReplayLimit 筆）或複製 curl 清單（上限 $_kNetworkBatchCurlCopyLimit 筆）。',
            en: 'Operate on the currently filtered ${filtered.length} requests. Replay is capped at $_kNetworkBatchReplayLimit; curl copy is capped at $_kNetworkBatchCurlCopyLimit.',
            fr: 'Agit sur les ${filtered.length} requêtes filtrées. Relecture limitée à $_kNetworkBatchReplayLimit ; copie curl limitée à $_kNetworkBatchCurlCopyLimit.',
            de: 'Wirkt auf die aktuell gefilterten ${filtered.length} Anfragen. Replay ist auf $_kNetworkBatchReplayLimit begrenzt; curl-Kopie auf $_kNetworkBatchCurlCopyLimit.',
            ja: '現在フィルタされた ${filtered.length} 件のリクエストを操作します。リプレイ上限は $_kNetworkBatchReplayLimit、curl コピー上限は $_kNetworkBatchCurlCopyLimit です。',
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: openHandCancelLabel(context),
          ),
          OpenHandDialogActionButton.secondary(
            onPressed: filtered.isEmpty
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    for (final e in filtered) {
                      await ctrl.blockUrl(e.url);
                    }
                    if (!context.mounted) return;
                    showOpenHandInfoSnack(
                      context,
                      openHandLocalizedText(
                        context,
                        zh: '已屏蔽 ${filtered.length} 个 URL',
                        zhHant: '已封鎖 ${filtered.length} 個 URL',
                        en: 'Blocked ${filtered.length} URLs',
                        fr: '${filtered.length} URL bloquées',
                        de: '${filtered.length} URLs blockiert',
                        ja: '${filtered.length} 件の URL をブロックしました',
                      ),
                    );
                  },
            icon: Icons.block_rounded,
            label: openHandLocalizedText(
              context,
              zh: '批量屏蔽',
              zhHant: '批次封鎖',
              en: 'Block all',
              fr: 'Tout bloquer',
              de: 'Alle blockieren',
              ja: 'すべてブロック',
            ),
          ),
          OpenHandDialogActionButton.secondary(
            onPressed: filtered.isEmpty
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    var ok = 0;
                    final cap = math.min(
                      filtered.length,
                      _kNetworkBatchReplayLimit,
                    );
                    for (final e in filtered.take(cap)) {
                      final r = await ctrl.replayRequest(e);
                      if (r != null) ok++;
                    }
                    if (!context.mounted) return;
                    showOpenHandInfoSnack(
                      context,
                      openHandLocalizedText(
                        context,
                        zh: '批量重放：成功 $ok / 共 $cap（上限 $_kNetworkBatchReplayLimit）',
                        zhHant:
                            '批次重放：成功 $ok / 共 $cap（上限 $_kNetworkBatchReplayLimit）',
                        en: 'Replayed $ok of $cap (cap $_kNetworkBatchReplayLimit)',
                        fr: '$ok sur $cap rejouées (limite $_kNetworkBatchReplayLimit)',
                        de: '$ok von $cap erneut gesendet (Limit $_kNetworkBatchReplayLimit)',
                        ja: '$cap 件中 $ok 件をリプレイしました（上限 $_kNetworkBatchReplayLimit）',
                      ),
                    );
                  },
            icon: Icons.replay_rounded,
            label: openHandLocalizedText(
              context,
              zh: '批量重放（≤$_kNetworkBatchReplayLimit）',
              zhHant: '批次重放（≤$_kNetworkBatchReplayLimit）',
              en: 'Replay (≤$_kNetworkBatchReplayLimit)',
              fr: 'Rejouer (≤$_kNetworkBatchReplayLimit)',
              de: 'Replay (≤$_kNetworkBatchReplayLimit)',
              ja: 'リプレイ（≤$_kNetworkBatchReplayLimit）',
            ),
          ),
          OpenHandDialogActionButton.primary(
            onPressed: filtered.isEmpty
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    final buf = StringBuffer();
                    final copyCount = math.min(
                      filtered.length,
                      _kNetworkBatchCurlCopyLimit,
                    );
                    for (final e in filtered.take(copyCount)) {
                      buf.writeln('# ${e.method} ${e.url}');
                      buf.write('curl ');
                      if (e.method != 'GET') buf.write('-X ${e.method} ');
                      e.requestHeaders.forEach((k, v) {
                        buf.write(
                          "-H '${k.replaceAll("'", r"\'")}: "
                          "${v.replaceAll("'", r"\'")}' ",
                        );
                      });
                      if (e.requestPostData != null &&
                          e.requestPostData!.isNotEmpty) {
                        buf.write(
                          "--data-raw '"
                          "${e.requestPostData!.replaceAll("'", r"\'")}' ",
                        );
                      }
                      buf.writeln("'${e.url}'");
                      buf.writeln();
                    }
                    final copied = await copyWebReverseTextToClipboard(
                      context: context,
                      text: buf.toString(),
                      logTag: 'web_reverse_dashboard_dialog',
                      logAction: '复制批量 curl 命令',
                      showSuccess: false,
                    );
                    if (copied == null || !context.mounted) return;
                    final base = openHandLocalizedText(
                      context,
                      zh: '已复制 $copyCount 条 curl 到剪贴板${filtered.length > copyCount ? '（已按条目上限裁剪）' : ''}',
                      zhHant:
                          '已複製 $copyCount 筆 curl 到剪貼簿${filtered.length > copyCount ? '（已依項目上限裁剪）' : ''}',
                      en: 'Copied $copyCount curl entries${filtered.length > copyCount ? ' (entry capped)' : ''}',
                      fr: '$copyCount entrées curl copiées${filtered.length > copyCount ? ' (limite atteinte)' : ''}',
                      de: '$copyCount curl-Einträge kopiert${filtered.length > copyCount ? ' (begrenzte Einträge)' : ''}',
                      ja: '$copyCount 件の curl をコピーしました${filtered.length > copyCount ? '（件数上限で切り詰め）' : ''}',
                    );
                    showWebReverseClipboardSuccessSnack(
                      context: context,
                      base: base,
                      result: copied,
                    );
                  },
            icon: Icons.copy_all_rounded,
            label: openHandLocalizedText(
              context,
              zh: '复制 curl（≤$_kNetworkBatchCurlCopyLimit）',
              zhHant: '複製 curl（≤$_kNetworkBatchCurlCopyLimit）',
              en: 'Copy curl (≤$_kNetworkBatchCurlCopyLimit)',
              fr: 'Copier curl (≤$_kNetworkBatchCurlCopyLimit)',
              de: 'curl kopieren (≤$_kNetworkBatchCurlCopyLimit)',
              ja: 'curl をコピー（≤$_kNetworkBatchCurlCopyLimit）',
            ),
          ),
        ],
      ),
    );
  }

  List<CdpNetworkEntry> _filteredNetworkEntries(
    WebReverseSessionController ctrl,
  ) {
    final filter = _networkFilter.toLowerCase().trim();
    final type = _resourceFilter;
    return ctrl.networkRequests
        .where((e) {
          if (filter.isNotEmpty &&
              !e.url.toLowerCase().contains(filter) &&
              !e.responseHeaders.values.any(
                (v) => v.toLowerCase().contains(filter),
              )) {
            return false;
          }
          if (!type.matches(e)) return false;
          return true;
        })
        .toList(growable: false);
  }

  /// 高级工具菜单：聚合体检报告 / 持久化 Header / CDP 命令面板 /
  /// 反向脚本一键导出 / AI 接口分析。这些都是低频但杠杆很大的入口，
  /// 合成一颗 Toolbar 图标按钮的弹窗里，避免污染主 toolbar 视觉。
  void _showAdvancedMenu(
    BuildContext context,
    WebReverseSessionController ctrl,
    bool isZh,
  ) {
    webReverseToolDialogs.show<void>(
      context: context,
      builder: (_) => _AdvancedMenuDialog(
        controller: ctrl,
        isZh: isZh,
        hostContext: context,
      ),
    );
  }
}

/// 工具栏的 tab 胶囊：高度 36，圆角 999，激活态填 primary container。
/// 计数角标自动 cross-fade。
/// 纯文本分段药丸：网络面板的资源筛选与应用面板的页签共用。
///
/// 两处此前各写了一份完全相同的 Material + InkWell + 描边配色，只有内边距
/// 与字号档位不同；其中一处还把 theme / colorScheme 当构造参数传进来，父级
/// 主题一变就得手动同步。
class _TextTabPill extends StatelessWidget {
  const _TextTabPill({
    required this.label,
    required this.active,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// 紧凑档：用于横向滚动的筛选条。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = dense
        ? theme.textTheme.labelSmall
        : theme.textTheme.bodySmall;
    return Material(
      color: active ? cs.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kToolbarRadius),
        side: BorderSide(
          color: active ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_kToolbarRadius),
        child: Padding(
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: labelStyle?.copyWith(
              fontWeight: FontWeight.w700,
              color: active ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarTabPill extends StatelessWidget {
  const _ToolbarTabPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.reduceMotion,
    this.count,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool reduceMotion;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : kOpenHandMotion180,
        curve: kOpenHandSwitchInCurve,
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                  kOpenHandHGap6,
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: active ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  if (count != null) ...[
                    kOpenHandHGap6,
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : kOpenHandMotion200,
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: Container(
                        key: ValueKey<int>(count!),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: kOpenHandPillBorderRadius,
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 窄屏 (< 720) 时把 16 个顶部 tab 折叠为下拉胶囊，避免横向滚动条挤压
/// 第二行的搜索框 + 控件链。下拉里仍然带 icon + label + count badge，与
/// 宽屏 `_ToolbarTabPill` 视觉一致；当前激活项打勾。
class _ToolbarTabDropdown extends StatelessWidget {
  const _ToolbarTabDropdown({
    required this.current,
    required this.tabs,
    required this.label,
    required this.icon,
    required this.isZh,
    required this.reduceMotion,
    required this.onChanged,
    required this.labelFor,
    required this.iconFor,
    required this.countFor,
    this.count,
  });

  final _Tab current;
  final List<_Tab> tabs;
  final String label;
  final IconData icon;
  final int? count;
  final bool isZh;
  final bool reduceMotion;
  final ValueChanged<_Tab> onChanged;
  final String Function(_Tab) labelFor;
  final IconData Function(_Tab) iconFor;
  final int? Function(_Tab) countFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedPopupMenuButton<_Tab>(
      tooltip: openHandLocalizedText(
        context,
        zh: '切换面板',
        zhHant: '切換面板',
        en: 'Switch panel',
        fr: 'Changer de panneau',
        de: 'Panel wechseln',
        ja: 'パネルを切り替え',
      ),
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final t in tabs)
          PopupMenuItem<_Tab>(
            value: t,
            child: Row(
              children: [
                Icon(
                  iconFor(t),
                  size: 16,
                  color: t == current ? cs.primary : cs.onSurfaceVariant,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    labelFor(t),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: t == current
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: t == current ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                if (countFor(t) != null) ...[
                  kOpenHandHGap8,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: kOpenHandPillBorderRadius,
                    ),
                    child: Text(
                      '${countFor(t)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (t == current) ...[
                  kOpenHandHGap6,
                  Icon(Icons.check_rounded, size: 16, color: cs.primary),
                ],
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : kOpenHandMotion180,
        curve: kOpenHandSwitchInCurve,
        height: _kToolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.onPrimaryContainer),
            kOpenHandHGap6,
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onPrimaryContainer,
              ),
            ),
            if (count != null) ...[
              kOpenHandHGap6,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.4),
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            kOpenHandHGap6,
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: cs.onPrimaryContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarSearchField extends StatefulWidget {
  const _ToolbarSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_ToolbarSearchField> createState() => _ToolbarSearchFieldState();
}

class _ToolbarSearchFieldState extends State<_ToolbarSearchField> {
  late final FocusNode _focusNode;
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocus);
    widget.controller.addListener(_onText);
    _hasText = widget.controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  void _onText() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !_wrMotionEnabled(context);
    return SizedBox(
      width: 260,
      height: _kToolbarHeight,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : kOpenHandMotion180,
        curve: kOpenHandSwitchInCurve,
        decoration: BoxDecoration(
          color: _focused
              ? cs.surface
              : cs.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: _focused ? cs.primary : cs.outlineVariant,
            width: _focused ? 1.4 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.18),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : kOpenHandMotion180,
              curve: kOpenHandSwitchInCurve,
              child: Icon(
                Icons.search_rounded,
                size: 16,
                color: _focused ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                onChanged: widget.onChanged,
                cursorColor: cs.primary,
                cursorWidth: 1.4,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 12.5,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  // 全局 InputDecorationTheme 默认 filled:true
                  // 会让搜索胶囊内部再叠一层 fill，看起来像「胶囊里又套
                  // 一只胶囊」。这里强制 filled:false + border:none，让
                  // 文本输入区与外层 AnimatedContainer 的圆角胶囊融为一
                  // 体，视觉上只保留最外层一道边。
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : kOpenHandMotion200,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: a, child: c),
              ),
              child: _hasText
                  ? InkResponse(
                      key: const ValueKey('clear'),
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged('');
                      },
                      radius: 14,
                      // 用极简的圆形点击响应替代 IconButton：原 IconButton 自带
                      // 36×36 命中圈在胶囊里会形成"胶囊里又套一个圆"的视觉，
                      // 这里仅保留图标本体并通过 InkResponse 给一个无 fill 的
                      // 圆形 ripple，外形与外层胶囊浑然一体。
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarTogglePill extends StatelessWidget {
  const _ToolbarTogglePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onChanged,
    required this.reduceMotion,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : kOpenHandMotion180,
        curve: kOpenHandSwitchInCurve,
        decoration: BoxDecoration(
          // 与全局主色保持一致：选中态用 primaryContainer
          // (而不是 secondaryContainer)，避免和会话顶部胶囊 / 设置项中
          // "已启用并注入" 的绿调风格出现两套主题。
          color: selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.36)
                : cs.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(!selected),
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: selected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  kOpenHandHGap6,
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: _kToolbarHeight,
        width: _kToolbarHeight,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            child: Center(
              child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarPrimaryPill extends StatelessWidget {
  const _ToolbarPrimaryPill({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      height: _kToolbarHeight,
      child: Material(
        color: cs.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kToolbarRadius),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_kToolbarRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: cs.onPrimary),
                kOpenHandHGap6,
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarThrottleButton extends StatelessWidget {
  const _ToolbarThrottleButton({required this.value, required this.onChanged});

  final WebReverseThrottlePreset value;
  final ValueChanged<WebReverseThrottlePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locale = Localizations.localeOf(context);
    return SizedBox(
      height: _kToolbarHeight,
      child: AnimatedPopupMenuButton<WebReverseThrottlePreset>(
        tooltip: openHandLocalizedText(
          context,
          zh: '网络节流',
          zhHant: '網路節流',
          en: 'Throttling',
          fr: 'Limitation réseau',
          de: 'Netzwerkdrosselung',
          ja: 'ネットワークスロットリング',
        ),
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (context) => WebReverseThrottlePreset.values
            .where((p) => p.isSelectable)
            .map(
              (p) =>
                  PopupMenuItem(value: p, child: Text(p.displayLabel(locale))),
            )
            .toList(growable: false),
        child: Container(
          decoration: BoxDecoration(
            color: value == WebReverseThrottlePreset.none
                ? Colors.transparent
                : cs.primaryContainer,
            borderRadius: BorderRadius.circular(_kToolbarRadius),
            border: Border.all(
              color: value == WebReverseThrottlePreset.none
                  ? cs.outlineVariant
                  : cs.primary.withValues(alpha: 0.36),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_rounded,
                size: 14,
                color: value == WebReverseThrottlePreset.none
                    ? cs.onSurfaceVariant
                    : cs.onPrimaryContainer,
              ),
              kOpenHandHGap6,
              Text(
                value.displayLabel(locale),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: value == WebReverseThrottlePreset.none
                      ? cs.onSurface
                      : cs.onPrimaryContainer,
                ),
              ),
              kOpenHandHGap4,
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// HAR diff 弹窗里的"only A / only B"单列：标题 + 计数 + 滚动列表。
class _HarDiffColumn extends StatelessWidget {
  const _HarDiffColumn({
    required this.title,
    required this.items,
    required this.accent,
  });

  final String title;
  final List<String> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              kOpenHandHGap6,
              Text(
                '$title (${items.length})',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap4,
          Expanded(
            child: items.isEmpty
                ? Text(
                    '(empty)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        items[i],
                        maxLines: 2,
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// HAR 单条请求摘要：HAR diff 的最小比较单元。bodyDigest 用于判断正文
/// 是否变化，bodyText 只保留预览，避免大 HAR 在弹窗模型里长期驻留全文。
class _HarEntrySummary {
  const _HarEntrySummary({
    required this.method,
    required this.url,
    required this.status,
    required this.bodySize,
    required this.mimeType,
    required this.bodyText,
    required this.bodyDigest,
  });
  final String method;
  final String url;
  final int status;
  final int bodySize;
  final String mimeType;
  final String bodyText;
  final String bodyDigest;
}

/// 同 (method,url) 在两份 HAR 中的差异：status 不同 / body 大小不同 /
/// body 文本不同 至少一项为真。三个标志位决定渲染高亮区域。
class _HarChange {
  const _HarChange({
    required this.a,
    required this.b,
    required this.statusChanged,
    required this.sizeChanged,
    required this.textChanged,
  });
  final _HarEntrySummary a;
  final _HarEntrySummary b;
  final bool statusChanged;
  final bool sizeChanged;
  final bool textChanged;
}

/// 「同 URL 已变」列：每个 _HarChange 渲染一个 ExpansionTile，标题展示
/// status A→B 色块、body size delta；展开后展示两份 body 的截断预览。
class _HarChangedColumn extends StatelessWidget {
  const _HarChangedColumn({
    required this.title,
    required this.changes,
    required this.isZh,
  });

  final String title;
  final List<_HarChange> changes;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandHGap6,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: kOpenHandBorderRadius6,
                ),
                child: Text(
                  '${changes.length}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          Expanded(
            child: changes.isEmpty
                ? OpenHandInlineEmptyState(
                    message: openHandLocalizedText(
                      context,
                      zh: '同 URL 全部一致',
                      zhHant: '同 URL 全部一致',
                      en: 'All shared URLs are identical',
                      fr: 'Toutes les URL communes sont identiques',
                      de: 'Alle gemeinsamen URLs sind identisch',
                      ja: '共通 URL はすべて一致しています',
                    ),
                    dense: true,
                  )
                : ListView.builder(
                    itemCount: changes.length,
                    itemBuilder: (_, i) =>
                        _HarChangeRow(change: changes[i], isZh: isZh),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HarChangeRow extends StatelessWidget {
  const _HarChangeRow({required this.change, required this.isZh});

  final _HarChange change;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = change;
    final sizeDelta = c.b.bodySize - c.a.bodySize;
    final headerChips = <Widget>[
      _StatusChip(value: c.a.status, color: cs.primary),
      const Icon(Icons.arrow_forward_rounded, size: 14),
      _StatusChip(
        value: c.b.status,
        color: c.statusChanged ? cs.error : cs.primary,
        emphasised: c.statusChanged,
      ),
      if (c.sizeChanged)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (sizeDelta > 0 ? cs.error : Colors.green).withValues(
              alpha: 0.18,
            ),
            borderRadius: kOpenHandBorderRadius6,
          ),
          child: Text(
            formatSignedByteSize(sizeDelta),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: sizeDelta > 0 ? cs.error : Colors.green,
              fontFamily: kOpenHandMonospaceFontFamily,
            ),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OpenHandExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: headerChips,
        ),
        subtitle: SelectableText(
          '${c.a.method} ${c.a.url}',
          maxLines: 1,
          style: const TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 11,
          ),
        ),
        children: [
          // body 文本不同时走行级 unified diff（LCS-based），
          // 两份都为空 / 同时只有一边有内容 → 退化到双列截断预览。
          if (c.textChanged &&
              c.a.bodyText.isNotEmpty &&
              c.b.bodyText.isNotEmpty)
            _UnifiedBodyDiff(
              titleA: 'A · ${c.a.mimeType}',
              titleB: 'B · ${c.b.mimeType}',
              bodyA: c.a.bodyText,
              bodyB: c.b.bodyText,
              isZh: isZh,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BodyPreview(
                    title: 'A · ${c.a.mimeType}',
                    body: c.a.bodyText,
                  ),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: _BodyPreview(
                    title: 'B · ${c.b.mimeType}',
                    body: c.b.bodyText,
                    accentChanged: c.textChanged,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.value,
    required this.color,
    this.emphasised = false,
  });

  final int value;
  final Color color;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasised ? 0.28 : 0.16),
        borderRadius: kOpenHandBorderRadius6,
        border: Border.all(
          color: color.withValues(alpha: emphasised ? 0.7 : 0.35),
          width: emphasised ? 1.4 : 1,
        ),
      ),
      child: Text(
        '$value',
        style: theme.textTheme.labelSmall?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontWeight: emphasised ? FontWeight.w900 : FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _BodyPreview extends StatelessWidget {
  const _BodyPreview({
    required this.title,
    required this.body,
    this.accentChanged = false,
  });

  final String title;
  final String body;
  final bool accentChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = clipTextWithEllipsis(body, 800);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(
          color: accentChanged ? cs.error : cs.outlineVariant,
          width: accentChanged ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                preview.isEmpty ? '<empty>' : preview,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// HAR Diff 第三级：两份 body 行级 unified diff。基于 LCS 还原编辑序列，
/// 渲染时按 git unified-diff 风格 ` `（context）、`+`（B 新增）、`-`（A 删
/// 除）三色行；context 行折叠超过 ±3 行的连续相同段成 `… N lines …`，
/// 避免长 JSON 全展开撑爆面板。每边 body 截断 4000 字符上限以护性能。
class _UnifiedBodyDiff extends StatelessWidget {
  const _UnifiedBodyDiff({
    required this.titleA,
    required this.titleB,
    required this.bodyA,
    required this.bodyB,
    required this.isZh,
  });

  final String titleA;
  final String titleB;
  final String bodyA;
  final String bodyB;
  final bool isZh;

  static const int _kMaxBodyChars = 4000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final aTrim = bodyA.length > _kMaxBodyChars
        ? clipTextByCodeUnitsWithEllipsis(bodyA, _kMaxBodyChars)
        : bodyA;
    final bTrim = bodyB.length > _kMaxBodyChars
        ? clipTextByCodeUnitsWithEllipsis(bodyB, _kMaxBodyChars)
        : bodyB;
    final aLines = aTrim.split('\n');
    final bLines = bTrim.split('\n');
    final ops = _diffLines(aLines, bLines);
    final folded = _foldContext(ops);
    final stats = (
      added: ops.where((o) => o.kind == _HarUnifiedKind.added).length,
      removed: ops.where((o) => o.kind == _HarUnifiedKind.removed).length,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$titleA → $titleB',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandHGap8,
              _HarUnifiedStat(label: '+${stats.added}', color: Colors.green),
              kOpenHandHGap4,
              _HarUnifiedStat(label: '-${stats.removed}', color: cs.error),
            ],
          ),
          kOpenHandGap6,
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final row in folded) _renderRow(row, cs)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderRow(_HarUnifiedRow row, ColorScheme cs) {
    if (row.kind == _HarUnifiedKind.fold) {
      return Container(
        color: cs.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          isZh
              ? '… 折叠 ${row.foldedCount} 行 …'
              : '… ${row.foldedCount} hidden …',
          style: TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 10.5,
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final color = switch (row.kind) {
      _HarUnifiedKind.added => Colors.green.withValues(alpha: 0.16),
      _HarUnifiedKind.removed => cs.error.withValues(alpha: 0.16),
      _ => Colors.transparent,
    };
    final prefix = switch (row.kind) {
      _HarUnifiedKind.added => '+ ',
      _HarUnifiedKind.removed => '- ',
      _ => '  ',
    };
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: SelectableText(
        '$prefix${row.line}',
        style: const TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }

  /// LCS-based 行级 diff。返回的 `_HarUnifiedRow` 顺序与 unified diff 一致：
  /// context 出现在两边都有的位置；A 独有 → removed；B 独有 → added。
  /// 复杂度 O(N×M)，对默认 ≤4000 字符上限的 body 完全够用。
  static List<_HarUnifiedRow> _diffLines(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    // dp[i][j] = 前 i 行 a 与前 j 行 b 的 LCS 长度。
    final dp = List<List<int>>.generate(
      n + 1,
      (_) => List<int>.filled(m + 1, 0),
    );
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] >= dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    final out = <_HarUnifiedRow>[];
    var i = n, j = m;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        out.add(_HarUnifiedRow(line: a[i - 1], kind: _HarUnifiedKind.same));
        i--;
        j--;
      } else if (dp[i - 1][j] >= dp[i][j - 1]) {
        out.add(_HarUnifiedRow(line: a[i - 1], kind: _HarUnifiedKind.removed));
        i--;
      } else {
        out.add(_HarUnifiedRow(line: b[j - 1], kind: _HarUnifiedKind.added));
        j--;
      }
    }
    while (i > 0) {
      out.add(_HarUnifiedRow(line: a[i - 1], kind: _HarUnifiedKind.removed));
      i--;
    }
    while (j > 0) {
      out.add(_HarUnifiedRow(line: b[j - 1], kind: _HarUnifiedKind.added));
      j--;
    }
    return out.reversed.toList(growable: false);
  }

  /// 把超过 ±3 行的连续 context 段折叠成单行 fold 标识。差异行附近 3
  /// 行保留以便给 reader 当上下文锚点。
  static List<_HarUnifiedRow> _foldContext(List<_HarUnifiedRow> ops) {
    const ctx = 3;
    final result = <_HarUnifiedRow>[];
    final n = ops.length;
    final keep = List<bool>.filled(n, false);
    for (var i = 0; i < n; i++) {
      if (ops[i].kind == _HarUnifiedKind.same) continue;
      final lo = (i - ctx).clamp(0, n - 1);
      final hi = (i + ctx).clamp(0, n - 1);
      for (var k = lo; k <= hi; k++) {
        keep[k] = true;
      }
    }
    var foldStart = -1;
    for (var i = 0; i < n; i++) {
      if (ops[i].kind == _HarUnifiedKind.same && !keep[i]) {
        if (foldStart < 0) foldStart = i;
        continue;
      }
      if (foldStart >= 0) {
        result.add(
          _HarUnifiedRow(
            line: '',
            kind: _HarUnifiedKind.fold,
            foldedCount: i - foldStart,
          ),
        );
        foldStart = -1;
      }
      result.add(ops[i]);
    }
    if (foldStart >= 0) {
      result.add(
        _HarUnifiedRow(
          line: '',
          kind: _HarUnifiedKind.fold,
          foldedCount: n - foldStart,
        ),
      );
    }
    return result;
  }
}

enum _HarUnifiedKind { same, added, removed, fold }

class _HarUnifiedRow {
  const _HarUnifiedRow({
    required this.line,
    required this.kind,
    this.foldedCount = 0,
  });
  final String line;
  final _HarUnifiedKind kind;
  final int foldedCount;
}

class _HarUnifiedStat extends StatelessWidget {
  const _HarUnifiedStat({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: kOpenHandBorderRadius4,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _webReverseDashHarDiffLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'HAR 对比',
    zhHant: 'HAR 對比',
    en: 'HAR diff',
    fr: 'Diff HAR',
    de: 'HAR-Diff',
    ja: 'HAR 差分',
  );
}

String _webReverseDashHarParseFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'HAR 解析失败',
    zhHant: 'HAR 解析失敗',
    en: 'HAR parse failed',
    fr: 'Échec de l’analyse HAR',
    de: 'HAR konnte nicht geparst werden',
    ja: 'HAR の解析に失敗しました',
  );
}
