import 'package:flutter/material.dart';

import '../market/market_provider.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'openhand_dialog_action_button.dart';
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

class MarketProviderSelector extends StatefulWidget {
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
  State<MarketProviderSelector> createState() => _MarketProviderSelectorState();
}

class _MarketProviderSelectorState extends State<MarketProviderSelector> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = widget.selected == null
        ? marketProviderUnavailable(context)
        : marketProviderName(context, widget.selected!);
    final title = openHandLocalizedText(
      context,
      zh: '数据提供商',
      zhHant: '資料提供商',
      en: 'Data provider',
      fr: 'Fournisseur de données',
      de: 'Datenanbieter',
      ja: 'データ提供元',
    );
    return Tooltip(
      message: '$title：$label',
      child: OpenHandDialogActionButton.primary(
        label: label,
        onPressed: !widget.enabled || widget.providers.isEmpty
            ? null
            : () async {
                if (_menuOpen) return;
                _menuOpen = true;
                try {
                  final value = await showAnimatedAnchoredPopupMenu<String>(
                    context: context,
                    initialValue: widget.selected?.id,
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kOpenHandRadius18),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 220,
                      maxWidth: 320,
                    ),
                    items: [
                      for (final info in widget.providers)
                        PopupMenuItem<String>(
                          value: info.id,
                          child: Semantics(
                            selected: info.id == widget.selected?.id,
                            child: Text(
                              marketProviderName(context, info),
                              style: info.id == widget.selected?.id
                                  ? TextStyle(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  );
                  if (mounted && widget.enabled && value != null) {
                    widget.onSelected(value);
                  }
                } finally {
                  _menuOpen = false;
                }
              },
      ),
    );
  }
}
