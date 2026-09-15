import '../../../shared/market/market_provider.dart';
import '../../../shared/market/skillhub_provider_info.dart';
import '../model/mcp_market_provider.dart';
import 'skillhub_mcp_provider.dart';

final mcpMarketProviders = MarketProviderRegistry<McpMarketProvider>([
  const MarketProviderRegistration(
    info: skillHubProviderInfo,
    create: SkillHubMcpProvider.new,
  ),
]);
