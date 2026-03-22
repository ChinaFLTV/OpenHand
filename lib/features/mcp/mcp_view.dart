import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../l10n/app_localizations.dart';
import 'data/mcp_store.dart';
import 'mcp_controller.dart';
import 'model/mcp_server.dart';

enum _McpCardAction { edit, delete }

class McpView extends StatelessWidget {
  const McpView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mcpController = context.watch<McpController>();
    final settingsController = context.watch<SettingsController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 980;
            final actions = Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: mcpController.isLoading
                      ? null
                      : () => mcpController.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.mcpRefresh),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openDirectory(context),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(l10n.mcpOpenDirectory),
                ),
                FilledButton.icon(
                  onPressed: () => _showServerDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.mcpNewServer),
                ),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _McpPageHeader(
                    title: l10n.mcpPageTitle,
                    subtitle: l10n.mcpPageSubtitle,
                  ),
                  const SizedBox(height: 20),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _McpPageHeader(
                    title: l10n.mcpPageTitle,
                    subtitle: l10n.mcpPageSubtitle,
                  ),
                ),
                const SizedBox(width: 20),
                Flexible(child: actions),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (!settingsController.mcpEnabled) ...[
          _McpInfoCard(
            icon: Icons.toggle_off_rounded,
            title: l10n.mcpDisabledTitle,
            body: l10n.mcpDisabledBody,
          ),
          const SizedBox(height: 16),
        ],
        if (mcpController.persistenceIssue != null) ...[
          _McpPersistenceIssueCard(
            issue: mcpController.persistenceIssue!,
            onDismiss: mcpController.clearPersistenceIssue,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _buildBody(context, mcpController),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, McpController mcpController) {
    final l10n = AppLocalizations.of(context)!;
    if (mcpController.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (mcpController.errorMessage != null) {
      return _McpStateCard(
        key: const ValueKey<String>('mcp-error'),
        icon: Icons.error_outline_rounded,
        title: l10n.mcpLoadFailedTitle,
        body: mcpController.errorMessage!,
        primaryActionLabel: l10n.mcpRefresh,
        onPrimaryAction: () => mcpController.refresh(),
      );
    }
    if (mcpController.servers.isEmpty) {
      return _McpStateCard(
        key: const ValueKey<String>('mcp-empty'),
        icon: Icons.hub_outlined,
        title: l10n.mcpEmptyTitle,
        body: l10n.mcpEmptyBody,
      );
    }

    return ListView.separated(
      key: const ValueKey<String>('mcp-list'),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: mcpController.servers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final server = mcpController.servers[index];
        return _McpServerCard(
          server: server,
          onTap: () => _showServerDialog(context, initialServer: server),
          onToggleEnabled: (enabled) =>
              _updateServerEnabled(context, server.name, enabled),
          onActionSelected: (action) {
            switch (action) {
              case _McpCardAction.edit:
                _showServerDialog(context, initialServer: server);
              case _McpCardAction.delete:
                _confirmDeleteServer(context, server);
            }
          },
        );
      },
    );
  }

  Future<void> _openDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<McpController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.mcpOperationFailed);
    }
  }

  Future<void> _showServerDialog(
    BuildContext context, {
    McpServer? initialServer,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<McpController>();
    final existingNames = controller.servers
        .where((item) => item.name != initialServer?.name)
        .map((item) => item.name.toLowerCase())
        .toSet();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _McpServerEditorDialog(
          initialServer: initialServer,
          existingNames: existingNames,
        );
      },
    );

    if (!context.mounted || submitted != true) {
      return;
    }
    _showSnackBar(
      context,
      initialServer == null ? l10n.mcpServerCreated : l10n.mcpServerUpdated,
    );
  }

  Future<void> _confirmDeleteServer(
    BuildContext context,
    McpServer server,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.mcpDeleteConfirmTitle),
          content: Text('${l10n.mcpDeleteConfirmBody}\n\n${server.name}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final deleted = await context.read<McpController>().deleteServer(server);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showSnackBar(context, l10n.mcpOperationFailed);
      return;
    }
    _showSnackBar(context, l10n.mcpServerDeleted);
  }

  Future<void> _updateServerEnabled(
    BuildContext context,
    String name,
    bool enabled,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final saved = await context.read<McpController>().updateServerEnabled(
      name,
      enabled,
    );
    if (!context.mounted || saved) {
      return;
    }
    _showSnackBar(context, l10n.mcpOperationFailed);
  }

  void _showSnackBar(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    });
  }
}

class _McpServerEditorDialog extends StatefulWidget {
  const _McpServerEditorDialog({
    required this.existingNames,
    this.initialServer,
  });

  final McpServer? initialServer;
  final Set<String> existingNames;

  @override
  State<_McpServerEditorDialog> createState() => _McpServerEditorDialogState();
}

class _McpServerEditorDialogState extends State<_McpServerEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _commandController;
  late final TextEditingController _argsController;
  late McpServerType _type;
  late bool _enabled;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialServer?.name ?? '',
    );
    _urlController = TextEditingController(
      text: widget.initialServer?.url ?? '',
    );
    _commandController = TextEditingController(
      text: widget.initialServer?.command ?? '',
    );
    _argsController = TextEditingController(
      text: widget.initialServer == null
          ? ''
          : widget.initialServer!.args.join('\n'),
    );
    _type = widget.initialServer?.type ?? McpServerType.streamableHttp;
    _enabled = widget.initialServer?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final useUrlField =
        _type == McpServerType.streamableHttp || _type == McpServerType.sse;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialServer == null
                      ? l10n.mcpDialogCreateTitle
                      : l10n.mcpDialogEditTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.mcpNameField,
                            ),
                            validator: (value) {
                              final name = value?.trim() ?? '';
                              if (name.isEmpty) {
                                return l10n.mcpNameRequired;
                              }
                              if (widget.existingNames.contains(
                                name.toLowerCase(),
                              )) {
                                return l10n.mcpNameDuplicate;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 320,
                            child: DropdownButtonFormField<McpServerType>(
                              initialValue: _type,
                              decoration: InputDecoration(
                                labelText: l10n.mcpTypeField,
                              ),
                              items: McpServerType.values
                                  .map(
                                    (item) => DropdownMenuItem<McpServerType>(
                                      value: item,
                                      child: Text(item.label(l10n)),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _isSaving
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setState(() {
                                        _type = value;
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.mcpServerEnabledLabel),
                            subtitle: Text(l10n.mcpServerEnabledBody),
                            value: _enabled,
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    setState(() {
                                      _enabled = value;
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          if (useUrlField) ...[
                            TextFormField(
                              controller: _urlController,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: l10n.mcpUrlField,
                              ),
                              validator: (value) {
                                final rawValue = value?.trim() ?? '';
                                if (rawValue.isEmpty) {
                                  return l10n.mcpUrlRequired;
                                }
                                final parsed = Uri.tryParse(rawValue);
                                if (parsed == null ||
                                    (!parsed.hasScheme &&
                                        !rawValue.startsWith('http'))) {
                                  return l10n.mcpUrlInvalid;
                                }
                                return null;
                              },
                            ),
                          ] else ...[
                            TextFormField(
                              controller: _commandController,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: l10n.mcpCommandField,
                              ),
                              validator: (value) {
                                if ((value?.trim() ?? '').isEmpty) {
                                  return l10n.mcpCommandRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _argsController,
                              enabled: !_isSaving,
                              minLines: 4,
                              maxLines: 8,
                              decoration: InputDecoration(
                                labelText: l10n.mcpArgsField,
                                hintText: l10n.mcpArgsHint,
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: Text(l10n.commonSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final server = McpServer(
      name: _nameController.text.trim(),
      type: _type,
      enabled: _enabled,
      url: _urlController.text.trim(),
      command: _commandController.text.trim(),
      args: _argsController.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    late final bool saved;
    try {
      saved = await context.read<McpController>().saveServer(
        server,
        previousName: widget.initialServer?.name,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.mcpOperationFailed;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.mcpOperationFailed;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }
}

extension on McpServerType {
  String label(AppLocalizations l10n) {
    return switch (this) {
      McpServerType.streamableHttp => l10n.mcpTransportStreamableHttp,
      McpServerType.sse => l10n.mcpTransportSse,
      McpServerType.stdio => l10n.mcpTransportStdio,
    };
  }
}

class _McpPageHeader extends StatelessWidget {
  const _McpPageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _McpServerCard extends StatelessWidget {
  const _McpServerCard({
    required this.server,
    required this.onTap,
    required this.onToggleEnabled,
    required this.onActionSelected,
  });

  final McpServer server;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<_McpCardAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      server.initials,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(server.name, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          server.type.label(l10n),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          server.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(value: server.enabled, onChanged: onToggleEnabled),
                  PopupMenuButton<_McpCardAction>(
                    onSelected: onActionSelected,
                    itemBuilder: (context) {
                      return [
                        PopupMenuItem<_McpCardAction>(
                          value: _McpCardAction.edit,
                          child: Text(l10n.commonEdit),
                        ),
                        PopupMenuItem<_McpCardAction>(
                          value: _McpCardAction.delete,
                          child: Text(l10n.commonDelete),
                        ),
                      ];
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(
                    server.enabled
                        ? Icons.check_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    server.enabled
                        ? l10n.mcpServerStatusEnabled
                        : l10n.mcpServerStatusDisabled,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _McpStateCard extends StatelessWidget {
  const _McpStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (primaryActionLabel != null && onPrimaryAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onPrimaryAction,
                    child: Text(primaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _McpInfoCard extends StatelessWidget {
  const _McpInfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
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
}

class _McpPersistenceIssueCard extends StatelessWidget {
  const _McpPersistenceIssueCard({
    required this.issue,
    required this.onDismiss,
  });

  final McpPersistenceIssue issue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final (title, body) = switch (issue.kind) {
      McpPersistenceIssueKind.recoveredInvalidFile => (
        l10n.mcpPersistenceRecoveredTitle,
        '${l10n.mcpPersistenceRecoveredBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      McpPersistenceIssueKind.sanitizedInvalidContent => (
        l10n.mcpPersistenceSanitizedTitle,
        '${l10n.mcpPersistenceSanitizedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      McpPersistenceIssueKind.saveFailed => (
        l10n.mcpPersistenceSaveFailedTitle,
        '${l10n.mcpPersistenceSaveFailedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
    };

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onDismiss,
              child: Text(
                l10n.settingsPersistenceDismiss,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
