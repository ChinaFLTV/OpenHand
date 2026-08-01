import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';

const double _kServiceCardRadius = 16;
const double _kServiceIconExtent = 60;
const double _kCompactCardBreakpoint = 760;
const double _kCompactCapabilitiesBreakpoint = 620;

enum _BuiltInService { aiInfrastructureExposureScan }

class ServicesView extends StatelessWidget {
  const ServicesView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FeaturePageShell(
      title: l10n.servicesTitle,
      subtitle: l10n.servicesSubtitle,
      body: ListView.separated(
        key: const ValueKey<String>('services-list'),
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
        itemCount: _BuiltInService.values.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final service = _BuiltInService.values[index];
          return SettingsAwareAppearOnce(
            key: ValueKey<String>('service-card-${service.name}'),
            child: RepaintBoundary(child: _ServiceCard(service: service)),
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final _BuiltInService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final name = switch (service) {
      _BuiltInService.aiInfrastructureExposureScan =>
        l10n.servicesAiInfrastructureExposureScanTitle,
    };
    final description = switch (service) {
      _BuiltInService.aiInfrastructureExposureScan =>
        l10n.servicesAiInfrastructureExposureScanDescription,
    };
    final capabilities = switch (service) {
      _BuiltInService.aiInfrastructureExposureScan =>
        <({IconData icon, String label})>[
          (
            icon: Icons.travel_explore_rounded,
            label: l10n.servicesAiInfrastructureExposureDiscover,
          ),
          (
            icon: Icons.key_rounded,
            label: l10n.servicesAiInfrastructureExposureCredentials,
          ),
          (
            icon: Icons.verified_user_rounded,
            label: l10n.servicesAiInfrastructureExposureAssess,
          ),
        ],
    };

    return Semantics(
      container: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_kServiceCardRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _kCompactCardBreakpoint;
              final identity = _ServiceIdentity(
                name: name,
                description: description,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact) ...[
                    identity,
                    const SizedBox(height: 18),
                    _ProprietaryBadge(label: l10n.servicesProprietaryBadge),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 24),
                        _ProprietaryBadge(label: l10n.servicesProprietaryBadge),
                      ],
                    ),
                  const SizedBox(height: 24),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.servicesCapabilitiesLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _CapabilitiesLayout(capabilities: capabilities),
                  const SizedBox(height: 22),
                  _AuthorizationNotice(label: l10n.servicesAuthorizationHint),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServiceIdentity extends StatelessWidget {
  const _ServiceIdentity({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: _kServiceIconExtent,
          height: _kServiceIconExtent,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.radar_rounded,
            size: 29,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProprietaryBadge extends StatelessWidget {
  const _ProprietaryBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            size: 17,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilitiesLayout extends StatelessWidget {
  const _CapabilitiesLayout({required this.capabilities});

  final List<({IconData icon, String label})> capabilities;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.62);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kCompactCapabilitiesBreakpoint) {
          return Column(
            children: [
              for (var index = 0; index < capabilities.length; index++) ...[
                if (index > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: dividerColor),
                  ),
                _CapabilityItem(
                  icon: capabilities[index].icon,
                  label: capabilities[index].label,
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < capabilities.length; index++) ...[
              if (index > 0) ...[
                const SizedBox(width: 18),
                SizedBox(
                  height: 40,
                  child: VerticalDivider(width: 1, color: dividerColor),
                ),
                const SizedBox(width: 18),
              ],
              Expanded(
                child: _CapabilityItem(
                  icon: capabilities[index].icon,
                  label: capabilities[index].label,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CapabilityItem extends StatelessWidget {
  const _CapabilityItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthorizationNotice extends StatelessWidget {
  const _AuthorizationNotice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onTertiaryContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
