import '../../../shared/market/market_provider.dart';
import 'mcp_market.dart';

abstract interface class McpMarketProvider implements MarketProvider {
  static const defaultPageSize = 24;
  Future<List<(String, int)>> categories();
  Future<McpMarketPage> search({
    required int page,
    required int pageSize,
    required String keyword,
    required String category,
  });
  Future<McpMarketServer> detail(String slug);
  Future<String> readme(String slug);
  void cancel(String scope);
}
