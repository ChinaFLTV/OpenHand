import '../../../shared/market/market_provider.dart';
import 'instruction_market.dart';

abstract interface class InstructionMarketProvider implements MarketProvider {
  Future<List<InstructionMarketEntry>> loadCatalog();
}
