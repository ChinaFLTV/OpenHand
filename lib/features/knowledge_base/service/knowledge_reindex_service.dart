class KnowledgeReindexService {
  const KnowledgeReindexService();

  Future<void> scheduleFullReindex() async {
    // The controller currently reindexes source-by-source through ingestion.
    // This service is kept as the stable boundary for future background job
    // scheduling and consistency repair.
  }
}
