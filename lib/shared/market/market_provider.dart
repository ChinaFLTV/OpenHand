/// 提供商会话拥有自己的请求和缓存，关闭时必须取消请求并释放资源。
abstract interface class MarketProvider {
  void close();
}

class MarketProviderInfo {
  const MarketProviderInfo({
    required this.id,
    required this.name,
    this.internationalName,
  });
  final String id;
  final String name;
  final String? internationalName;
}

class MarketProviderRegistration<T extends MarketProvider> {
  const MarketProviderRegistration({required this.info, required this.create});
  final MarketProviderInfo info;

  /// 每次返回独立会话；构造时不发起网络请求。
  final T Function() create;
}

/// 注册表只保存工厂和本次应用运行中的选择，不共享请求或缓存。
class MarketProviderRegistry<T extends MarketProvider> {
  MarketProviderRegistry(
    Iterable<MarketProviderRegistration<T>> providers, {
    String? selectedId,
  }) : providers = List.unmodifiable(providers) {
    _selectedId = selectedId;
    final ids = this.providers.map((entry) => entry.info.id).toSet();
    if (ids.length != this.providers.length || ids.contains('')) {
      throw ArgumentError('市场提供商标识不能为空或重复。');
    }
  }
  final List<MarketProviderRegistration<T>> providers;
  String? _selectedId;

  MarketProviderRegistration<T>? get selected =>
      providers.where((entry) => entry.info.id == _selectedId).firstOrNull ??
      providers.firstOrNull;
}

class MarketProviderSession<T extends MarketProvider> {
  MarketProviderSession(this.registry) {
    final selected = registry.selected;
    if (selected != null) {
      _provider = selected.create();
      _info = selected.info;
    }
  }
  final MarketProviderRegistry<T> registry;
  T? _provider;
  MarketProviderInfo? _info;
  bool _closed = false;
  T? get provider => _provider;
  MarketProviderInfo? get info => _info;

  bool select(String id) {
    if (_closed || id == _info?.id) return false;
    final entry = registry.providers
        .where((entry) => entry.info.id == id)
        .firstOrNull;
    if (entry == null) return false;
    final next = entry.create();
    _provider?.close();
    _provider = next;
    _info = entry.info;
    registry._selectedId = id;
    return true;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _provider?.close();
    _provider = null;
  }
}
