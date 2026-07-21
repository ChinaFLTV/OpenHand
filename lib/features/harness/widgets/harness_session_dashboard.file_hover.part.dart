part of 'harness_session_dashboard.dart';

Future<void> _heOpenPathInFileBrowser(BuildContext context, String path) async {
  try {
    final launched = await revealLocalPathInSystemFileManager(
      path,
      tag: 'harness_session_dashboard.file_hover.reveal',
    );
    if (launched) return;
    throw const FileSystemException('Unable to open file location.');
  } catch (error) {
    if (!context.mounted) return;
    showFriendlyErrorSnackBar(
      context,
      message: '$error',
      fallback: openHandLocalizedText(
        context,
        zh: '打开文件位置失败',
        en: 'Failed to open file location',
        zhHant: '打開檔案位置失敗',
        fr: 'Impossible d’ouvrir l’emplacement du fichier',
        de: 'Dateispeicherort konnte nicht geöffnet werden',
        ja: 'ファイルの場所を開けませんでした',
      ),
    );
  }
}
