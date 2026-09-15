import '../../../shared/market/market_provider.dart';
import '../../../shared/market/skillhub_provider_info.dart';
import '../model/skill_market_provider.dart';
import 'skillhub_skill_provider.dart';

final skillMarketProviders = MarketProviderRegistry<SkillMarketProvider>([
  const MarketProviderRegistration(
    info: skillHubProviderInfo,
    create: SkillHubSkillProvider.new,
  ),
]);
