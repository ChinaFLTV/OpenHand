import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/collision_safe_animated_switcher.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/mcp_server.dart';
import '../service/mcp_oauth_callback_page.dart';
import '../service/mcp_oauth_service.dart';
import '../service/mcp_tool_discovery_exception.dart';

class McpOAuthPanel extends StatefulWidget {
  const McpOAuthPanel({
    super.key,
    required this.server,
    this.onAuthorized,
    this.service,
  });
  final McpServer server;
  final VoidCallback? onAuthorized;
  final McpOAuthService? service;

  @override
  State<McpOAuthPanel> createState() => _McpOAuthPanelState();
}

class _McpOAuthPanelState extends State<McpOAuthPanel> {
  late final _oauth = widget.service ?? McpOAuthService.instance;
  String? _error;
  bool _loading = true;
  bool _ownsAuthorization = false;
  final _loadDebouncer = OpenHandDebouncer(
    delay: const Duration(milliseconds: 250),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(McpOAuthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server.oauthKey != widget.server.oauthKey ||
        oldWidget.server.usesOAuth != widget.server.usesOAuth) {
      if (_ownsAuthorization) _oauth.cancel(oldWidget.server);
      _ownsAuthorization = false;
      _error = null;
      _loading = true;
      _loadDebouncer.schedule(_load);
    }
  }

  Future<void> _load() async {
    if (!widget.server.usesOAuth) return;
    final key = widget.server.oauthKey;
    try {
      await _oauth.load(widget.server);
    } catch (_) {
      if (mounted && key == widget.server.oauthKey) _error = '无法读取本机授权凭证，请重试。';
    }
    if (mounted && key == widget.server.oauthKey) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _loadDebouncer.dispose();
    if (_ownsAuthorization) _oauth.cancel(widget.server);
    super.dispose();
  }

  Future<void> _authorize() async {
    final server = widget.server;
    setState(() {
      _error = null;
      _ownsAuthorization = true;
    });
    try {
      await _oauth.authorize(
        server,
        callbackPage: McpOAuthCallbackPage(
          colors: Theme.of(context).colorScheme,
          animation: openHandMotionSettingsOf(
            context,
            OpenHandMotionSettingsScope.dialog,
          ),
        ),
      );
      if (mounted && server.oauthKey == widget.server.oauthKey) {
        widget.onAuthorized?.call();
      }
    } catch (error) {
      if (mounted && server.oauthKey == widget.server.oauthKey) {
        setState(
          () => _error = error is McpToolDiscoveryException
              ? error.message
              : '授权连接失败，请检查网络后重试。',
        );
      }
    } finally {
      if (mounted && server.oauthKey == widget.server.oauthKey) {
        setState(() => _ownsAuthorization = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _oauth,
    builder: (context, _) {
      final status = _oauth.status(widget.server);
      final busy = status == McpOAuthStatus.authorizing;
      final authorized = status == McpOAuthStatus.authorized;
      final color = authorized
          ? OpenHandStatusColors.success
          : busy
          ? OpenHandStatusColors.info
          : OpenHandStatusColors.warning;
      final label = _loading
          ? '读取授权状态'
          : switch (status) {
              McpOAuthStatus.required => '等待授权',
              McpOAuthStatus.authorizing => '等待浏览器授权',
              McpOAuthStatus.authorized => '授权有效',
              McpOAuthStatus.expired => '授权过期或失效',
            };
      final colors = Theme.of(context).colorScheme;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final actionWidth = 140.0 * (scale < 1 ? 1.0 : scale);
      ButtonStyle actionStyle(Color tone) => FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        shape: const StadiumBorder(),
        side: BorderSide(color: tone.withValues(alpha: 0.32)),
        backgroundColor: tone.withValues(alpha: 0.12),
        foregroundColor: tone,
        iconSize: 16,
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      );
      final actions = Wrap(
        runSpacing: 10,
        children: [
          _OAuthActionTransition(
            child: SizedBox(
              key: ValueKey((_loading, status)),
              width: actionWidth,
              child: FilledButton.icon(
                style: actionStyle(colors.primary),
                onPressed: _loading || busy ? null : _authorize,
                icon: Icon(
                  busy
                      ? Icons.hourglass_top_rounded
                      : Icons.open_in_browser_rounded,
                ),
                label: Text(
                  busy
                      ? '授权进行中'
                      : authorized || status == McpOAuthStatus.expired
                      ? '重新授权'
                      : '浏览器授权',
                ),
              ),
            ),
          ),
          _OAuthActionTransition(
            child: !busy && !authorized
                ? null
                : Padding(
                    key: ValueKey(busy),
                    padding: const EdgeInsetsDirectional.only(start: 10),
                    child: SizedBox(
                      width: actionWidth,
                      child: FilledButton.icon(
                        style: actionStyle(colors.secondary),
                        onPressed: busy
                            ? () => _oauth.cancel(widget.server)
                            : () async {
                                try {
                                  await _oauth.forget(widget.server);
                                } catch (_) {
                                  if (mounted) {
                                    setState(() => _error = '清除本机授权失败，请重试。');
                                  }
                                }
                              },
                        icon: Icon(
                          busy ? Icons.close_rounded : Icons.link_off_rounded,
                        ),
                        label: Text(busy ? '取消授权' : '清除本机授权'),
                      ),
                    ),
                  ),
          ),
        ],
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final inline =
              constraints.maxWidth >= 720.0 * (scale < 1 ? 1.0 : scale);
          return OpenHandAnimatedDialogSize(
            child: OpenHandDialogSectionCard(
              icon: authorized
                  ? Icons.verified_user_rounded
                  : Icons.fingerprint_rounded,
              accent: color,
              title: 'OAuth · $label',
              subtitle: busy
                  ? '请在系统浏览器中完成授权，完成后自动连接。'
                  : '使用浏览器安全授权，访问令牌到期时自动尝试刷新。',
              trailing: inline ? actions : null,
              contentSpacing: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!inline)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: actions,
                    ),
                  OpenHandVerticalRevealSwitcher(
                    child: _error == null
                        ? null
                        : Padding(
                            key: ValueKey(_error),
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 操作切换沿用全局进退场设置，退场内容保留绘制但不再接收点击。
class _OAuthActionTransition extends StatelessWidget {
  const _OAuthActionTransition({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return OpenHandAnimatedDialogSize(
      child: AnimatedSwitcher(
        duration: settings.entranceDisabled
            ? Duration.zero
            : settings.entranceDuration,
        reverseDuration: settings.exitDisabled
            ? Duration.zero
            : settings.exitDuration,
        layoutBuilder: (current, previous) =>
            buildCollisionSafeAnimatedSwitcherLayout(
              current,
              previous,
              alignment: AlignmentDirectional.centerStart,
            ),
        transitionBuilder: (child, animation) => buildAnimationStyleTransition(
          animation: animation,
          settings: settings,
          profile: kOpenHandLayoutSafeTransitionProfile,
          child: child,
        ),
        child: child ?? const SizedBox.shrink(key: ValueKey('隐藏')),
      ),
    );
  }
}
