// 加密哈希快牌 (Crypto Quick Pad)
// 逆向常用的编解码 / 哈希工具集中在一处，避免每次切到外部网页。
// 全部纯客户端计算，不走 CDP；无副作用，不持久化（每次重启清空）。
// 工具单元：
//   - 编解码：Base64 / URL / Hex
//   - 哈希：MD5 / SHA-1 / SHA-256 / SHA-512
//   - JWT 解码（header / payload / signature 三段拆分）
//   - 时间戳 ↔ ISO-8601（秒 / 毫秒）
//   - UUID v4 生成器
//   - 字符串长度 / 字节计数

part of 'web_reverse_dashboard_dialog.dart';

const int _kCryptoPadMaxDecodedBytes = 8 * kBytesPerMiB;

class _CryptoPadBody extends StatefulWidget {
  const _CryptoPadBody({required this.reduceMotion});
  final bool reduceMotion;

  @override
  State<_CryptoPadBody> createState() => _CryptoPadBodyState();
}

class _CryptoPadBodyState extends State<_CryptoPadBody> {
  late final TextEditingController _input;
  int _section = 0; // 0=编解码 1=哈希 2=JWT 3=时间戳 4=UUID

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _setInput(String s) {
    _input.text = s;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    setState(() {});
  }

  Future<void> _copy(String text, String label) async {
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: text,
      successBase: loc?.webReverseCryptoCopied(label) ?? '$label copied',
      logTag: 'web_reverse_crypto_pad',
      successDuration: const Duration(seconds: 1),
    );
  }

  // ─── 计算函数 ────────────────────────────────────────────────────────
  String _b64Encode(String s) {
    try {
      return base64Encode(utf8.encode(s));
    } catch (e) {
      return '! $e';
    }
  }

  String _b64Decode(String s) {
    try {
      return utf8.decode(
        decodeFlexibleBase64Bounded(
          s,
          maxDecodedBytes: _kCryptoPadMaxDecodedBytes,
        ),
        allowMalformed: true,
      );
    } catch (e) {
      return '! $e';
    }
  }

  String _urlEncode(String s) => Uri.encodeComponent(s);
  String _urlDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (e) {
      return '! $e';
    }
  }

  String _hexEncode(String s) {
    return bytesToHex(utf8.encode(s));
  }

  String _hexDecode(String s) {
    final t = s.trim().replaceAll(kInlineWhitespacePattern, '');
    if (t.isEmpty) return '';
    if (t.length.isOdd) return '! odd length';
    final bytes = hexToBytes(t);
    if (bytes == null) return '! invalid hex';
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _hashStr(crypto.Hash algo, String s) {
    return algo.convert(utf8.encode(s)).toString();
  }

  /// JWT：用 `.` 切 3 段，前两段 base64url 解码为 JSON 美化，第 3 段
  /// 保持原签名串。失败回退原始片段。
  Map<String, String> _jwtSplit(String s) {
    final parts = s.trim().split('.');
    if (parts.length < 2) {
      return {'header': '!', 'payload': '!', 'signature': ''};
    }
    String pretty(String b) {
      final raw = _b64Decode(b);
      try {
        final v = jsonDecode(raw);
        return prettyPrintJson(v);
      } catch (_) {
        return raw;
      }
    }

    return {
      'header': pretty(parts[0]),
      'payload': pretty(parts[1]),
      'signature': parts.length >= 3 ? parts[2] : '',
    };
  }

  String _tsToIso(String s) {
    final raw = s.trim();
    if (raw.isEmpty) return '';
    final n = optionalIntFromValue(raw);
    if (n == null) return '! not a number';
    final ms = raw.length <= 10 ? n * 1000 : n;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();
    } catch (e) {
      return '! $e';
    }
  }

  String _isoToTs(String s) {
    final raw = s.trim();
    if (raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return 'sec=${(d.millisecondsSinceEpoch / 1000).floor()}\n'
          'ms=${d.millisecondsSinceEpoch}';
    } catch (e) {
      return '! $e';
    }
  }

  String _genUuidV4() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final s = bytesToHex(bytes);
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: [
              _sectionBtn(cs, 0, loc?.webReverseCryptoSecEncode ?? 'Encode'),
              _sectionBtn(cs, 1, loc?.webReverseCryptoSecHash ?? 'Hash'),
              _sectionBtn(cs, 2, 'JWT'),
              _sectionBtn(cs, 3, loc?.webReverseCryptoSecTime ?? 'Time'),
              _sectionBtn(cs, 4, 'UUID'),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _setInput(''),
                icon: const Icon(Icons.clear_rounded, size: 14),
                label: Text(loc?.webReverseCryptoClear ?? 'Clear'),
              ),
            ],
          ),
        ),
        if (_section != 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: TextField(
              controller: _input,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: loc?.webReverseCryptoInputHint ?? 'Paste here…',
                labelText: loc?.webReverseCryptoInputLabel ?? 'Input',
              ),
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: widget.reduceMotion ? Duration.zero : kOpenHandMotion200,
            switchInCurve: kOpenHandSwitchInCurve,
            child: switch (_section) {
              0 => _encodingPanel(theme, cs, loc),
              1 => _hashPanel(theme, cs, loc),
              2 => _jwtPanel(theme, cs, loc),
              3 => _timePanel(theme, cs, loc),
              _ => _uuidPanel(theme, cs, loc),
            },
          ),
        ),
      ],
    );
  }

  Widget _sectionBtn(ColorScheme cs, int idx, String label) {
    final on = _section == idx;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        onPressed: () => setState(() => _section = idx),
        style: TextButton.styleFrom(
          foregroundColor: on ? cs.primary : cs.onSurfaceVariant,
          backgroundColor: on ? cs.primary.withValues(alpha: 0.1) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        child: Text(label),
      ),
    );
  }

  // ─── 结果卡片 ────────────────────────────────────────────────────────
  Widget _resultCard(
    ThemeData theme,
    ColorScheme cs,
    String label,
    String value, {
    AppLocalizations? loc,
  }) {
    return Container(
      key: ValueKey('rc-$label'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: webReverseSurfaceCardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: loc?.webReverseCryptoCopy ?? 'Copy',
                icon: const Icon(Icons.content_copy_rounded, size: 14),
                onPressed: value.isEmpty || value.startsWith('!')
                    ? null
                    : () => _copy(value, label),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              if (label == 'Output' || label == 'Decoded' || label == 'Encoded')
                IconButton(
                  tooltip: loc?.webReverseCryptoUseAsInput ?? 'Use as input',
                  icon: const Icon(Icons.north_west_rounded, size: 14),
                  onPressed: value.isEmpty || value.startsWith('!')
                      ? null
                      : () => _setInput(value),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
            ],
          ),
          kOpenHandGap4,
          SelectableText(
            value.isEmpty ? '—' : value,
            style: TextStyle(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 12,
              color: value.startsWith('!') ? cs.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _encodingPanel(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
  ) {
    final t = _input.text;
    return ListView(
      key: const ValueKey('enc'),
      children: [
        _resultCard(theme, cs, 'Base64 Encode', _b64Encode(t), loc: loc),
        _resultCard(theme, cs, 'Base64 Decode', _b64Decode(t), loc: loc),
        _resultCard(theme, cs, 'URL Encode', _urlEncode(t), loc: loc),
        _resultCard(theme, cs, 'URL Decode', _urlDecode(t), loc: loc),
        _resultCard(theme, cs, 'Hex Encode', _hexEncode(t), loc: loc),
        _resultCard(theme, cs, 'Hex Decode', _hexDecode(t), loc: loc),
        _resultCard(
          theme,
          cs,
          loc?.webReverseCryptoLengthLabel ?? 'Length',
          loc?.webReverseCryptoLengthValue(t.length, utf8.encode(t).length) ??
              'chars ${t.length} / bytes ${utf8.encode(t).length}',
          loc: loc,
        ),
      ],
    );
  }

  Widget _hashPanel(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final t = _input.text;
    return ListView(
      key: const ValueKey('hash'),
      children: [
        _resultCard(theme, cs, 'MD5', _hashStr(crypto.md5, t), loc: loc),
        _resultCard(theme, cs, 'SHA-1', _hashStr(crypto.sha1, t), loc: loc),
        _resultCard(theme, cs, 'SHA-256', _hashStr(crypto.sha256, t), loc: loc),
        _resultCard(theme, cs, 'SHA-512', _hashStr(crypto.sha512, t), loc: loc),
      ],
    );
  }

  Widget _jwtPanel(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final parts = _jwtSplit(_input.text);
    return ListView(
      key: const ValueKey('jwt'),
      children: [
        _resultCard(theme, cs, 'Header', parts['header'] ?? '', loc: loc),
        _resultCard(theme, cs, 'Payload', parts['payload'] ?? '', loc: loc),
        _resultCard(theme, cs, 'Signature', parts['signature'] ?? '', loc: loc),
      ],
    );
  }

  Widget _timePanel(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final t = _input.text;
    final now = DateTime.now();
    return ListView(
      key: const ValueKey('time'),
      children: [
        _resultCard(
          theme,
          cs,
          loc?.webReverseCryptoTsToIso ?? 'Timestamp → ISO',
          _tsToIso(t),
          loc: loc,
        ),
        _resultCard(
          theme,
          cs,
          loc?.webReverseCryptoIsoToTs ?? 'ISO → Timestamp',
          _isoToTs(t),
          loc: loc,
        ),
        _resultCard(
          theme,
          cs,
          loc?.webReverseCryptoNow ?? 'Now',
          'sec=${(now.millisecondsSinceEpoch / 1000).floor()}\n'
          'ms=${now.millisecondsSinceEpoch}\n'
          'iso=${now.toIso8601String()}',
          loc: loc,
        ),
      ],
    );
  }

  Widget _uuidPanel(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    final samples = List<String>.generate(8, (_) => _genUuidV4());
    return ListView(
      key: const ValueKey('uuid'),
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                loc?.webReverseCryptoUuidHint ?? 'Random UUID v4 (tap to copy)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: Text(loc?.webReverseCryptoRegenerate ?? 'Regenerate'),
              ),
            ],
          ),
        ),
        for (final s in samples)
          InkWell(
            onTap: () => _copy(s, 'UUID'),
            borderRadius: kOpenHandBorderRadius8,
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: webReverseSurfaceCardDecoration(cs, radius: 8),
              child: Text(
                s,
                style: const TextStyle(
                  fontFamily: kOpenHandMonospaceFontFamily,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
