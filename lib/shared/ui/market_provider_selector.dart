import 'package:flutter/material.dart';

import '../market/market_provider.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'openhand_spacing.dart';

String marketProviderName(BuildContext context, MarketProviderInfo info) =>
    Localizations.localeOf(context).languageCode == 'zh'
    ? info.name
    : info.internationalName ?? info.name;

String marketProviderUnavailable(BuildContext context) => openHandLocalizedText(
  context,
  zh: '暂无可用数据提供商',
  zhHant: '暫無可用資料提供商',
  en: 'No providers available',
  fr: 'Aucun fournisseur disponible',
  de: 'Keine Anbieter verfügbar',
  ja: '利用可能なプロバイダーがありません',
);

class MarketProviderSelector extends StatelessWidget {
  const MarketProviderSelector({
    super.key,
    required this.providers,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final List<MarketProviderInfo> providers;
  final MarketProviderInfo? selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact =
        MediaQuery.sizeOf(context).width < 668 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final label = selected == null
        ? marketProviderUnavailable(context)
        : marketProviderName(context, selected!);
    final title = openHandLocalizedText(
      context,
      zh: '数据提供商',
      zhHant: '資料提供商',
      en: 'Data provider',
      fr: 'Fournisseur de données',
      de: 'Datenanbieter',
      ja: 'データ提供元',
    );
    return AnimatedPopupMenuButton<String>(
      tooltip: '$title：$label',
      enabled: enabled && providers.isNotEmpty,
      initialValue: selected?.id,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
      ),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final info in providers)
          PopupMenuItem<String>(
            value: info.id,
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, color: colors.primary),
                kOpenHandHGap12,
                Expanded(child: Text(marketProviderName(context, info))),
                if (info.id == selected?.id) ...[
                  kOpenHandHGap8,
                  Icon(Icons.check_circle_rounded, color: colors.primary),
                ],
              ],
            ),
          ),
      ],
      style: TextButton.styleFrom(
        foregroundColor: colors.primary,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 12,
        ),
        backgroundColor: colors.primaryContainer.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandRadius18),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.24)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            const Icon(Icons.cloud_outlined, size: 20),
            kOpenHandHGap8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            kOpenHandHGap8,
          ],
          const Icon(Icons.expand_more_rounded, size: 22),
        ],
      ),
    );
  }
}
