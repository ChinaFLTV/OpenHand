import '../../../shared/market/market_provider.dart';
import '../../../shared/market/skillhub_provider_info.dart';
import '../model/instruction_market_provider.dart';
import 'instruction_market_catalog.dart';

final instructionMarketProviders =
    MarketProviderRegistry<InstructionMarketProvider>([
      const MarketProviderRegistration(
        info: skillHubProviderInfo,
        create: SkillHubInstructionProvider.new,
      ),
    ]);

class SkillHubInstructionProvider implements InstructionMarketProvider {
  @override
  Future<List<InstructionMarketEntry>> loadCatalog() async =>
      instructionMarketCatalog;
  @override
  void close() {}
}
