import 'dart:async';

import '../../../shared/util/input_value_parsing.dart';

enum KnowledgeIndexingPhase {
  preparing,
  parsing,
  storing,
  chunking,
  ensuringCollection,
  embedding,
  upserting,
  finalizing,
  completed,
  cancelling,
  cancelled,
}

class KnowledgeIndexingProgress {
  const KnowledgeIndexingProgress({
    this.phase = KnowledgeIndexingPhase.preparing,
    this.sourceTitle = '',
    this.processedChunks = 0,
    this.totalChunks = 0,
    this.detail = '',
  });

  final KnowledgeIndexingPhase phase;
  final String sourceTitle;
  final int processedChunks;
  final int totalChunks;
  final String detail;

  bool get hasChunkProgress => totalChunks > 0;

  int get clampedProcessedChunks {
    if (totalChunks <= 0) return 0;
    return processedChunks.clamp(0, totalChunks);
  }

  double? get fraction {
    if (!hasChunkProgress) return null;
    return unitRatio(clampedProcessedChunks, totalChunks);
  }

  KnowledgeIndexingProgress copyWith({
    KnowledgeIndexingPhase? phase,
    String? sourceTitle,
    int? processedChunks,
    int? totalChunks,
    String? detail,
  }) {
    return KnowledgeIndexingProgress(
      phase: phase ?? this.phase,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      processedChunks: processedChunks ?? this.processedChunks,
      totalChunks: totalChunks ?? this.totalChunks,
      detail: detail ?? this.detail,
    );
  }
}

typedef KnowledgeIndexingProgressCallback =
    void Function(KnowledgeIndexingProgress progress);

class KnowledgeIndexingCancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_cancelled.isCompleted) return;
    _cancelled.complete();
  }

  void throwIfCancelled() {
    if (!isCancelled) return;
    throw const KnowledgeIndexingCancelledException();
  }
}

class KnowledgeIndexingCancelledException implements Exception {
  const KnowledgeIndexingCancelledException([this.message = '知识库向量构建已停止。']);

  final String message;

  @override
  String toString() => message;
}
