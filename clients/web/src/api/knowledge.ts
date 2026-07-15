import { LONG_API_REQUEST_TIMEOUT_MS, apiRequest, type ApiRequestSignalOptions } from './client';
import { normalizeInteger } from '../shared/util/number';

export const KNOWLEDGE_VECTOR_DEFAULT_MAX_POINTS = 600;
const KNOWLEDGE_VECTOR_MIN_POINTS = 1;
const KNOWLEDGE_VECTOR_MAX_POINTS = 2000;

type KnowledgeVectorPointKind = 'corpus' | 'match' | 'query';

interface KnowledgeVectorDistributionPointDto {
  id: string;
  kind: KnowledgeVectorPointKind;
  title?: string;
  preview?: string;
  x: number;
  y: number;
  z: number;
  score?: number;
  rerank_score?: number;
}

export interface KnowledgeVectorDistributionDto {
  algorithm?: string;
  original_dimensions?: number;
  sampled_count?: number;
  has_more?: boolean;
  duration_ms?: number;
  generated_at?: string;
  points?: KnowledgeVectorDistributionPointDto[];
}

interface KnowledgeVectorDistributionResponse {
  distribution?: KnowledgeVectorDistributionDto;
}

export interface KnowledgeSourceDto {
  id: string;
  title?: string;
  kind?: string;
  original_path?: string;
  stored_path?: string;
  mime_type?: string;
  size_bytes?: number;
  content_hash?: string;
  status?: string;
  error_message?: string;
  document_time?: string | null;
  imported_at?: string;
  indexed_at?: string | null;
  created_at?: string;
  updated_at?: string;
  metadata?: Record<string, unknown>;
}

export interface KnowledgeChunkDto {
  id: string;
  source_id: string;
  chunk_index?: number;
  parent_chunk_id?: string | null;
  title?: string;
  heading_path?: string;
  content?: string;
  content_hash?: string;
  char_count?: number;
  token_estimate?: number;
  start_offset?: number | null;
  end_offset?: number | null;
  page_number?: number | null;
  document_time?: string | null;
  created_at?: string;
  updated_at?: string;
  metadata?: Record<string, unknown>;
  tags?: string[];
}

interface KnowledgeHitDetailResponse {
  source?: KnowledgeSourceDto;
  chunk?: KnowledgeChunkDto;
}

export function fetchKnowledgeVectorDistribution(
  maxPoints = KNOWLEDGE_VECTOR_DEFAULT_MAX_POINTS,
  options: ApiRequestSignalOptions = {},
): Promise<KnowledgeVectorDistributionResponse> {
  const params = new URLSearchParams();
  const safeMaxPoints = normalizeInteger(maxPoints, {
    fallback: KNOWLEDGE_VECTOR_DEFAULT_MAX_POINTS,
    min: KNOWLEDGE_VECTOR_MIN_POINTS,
    max: KNOWLEDGE_VECTOR_MAX_POINTS,
  });
  params.set('max_points', String(safeMaxPoints));
  return apiRequest<KnowledgeVectorDistributionResponse>(
    `/api/knowledge/vector-distribution?${params.toString()}`,
    {
      signal: options.signal,
      timeoutMs: options.timeoutMs ?? LONG_API_REQUEST_TIMEOUT_MS,
    },
  );
}

export function fetchKnowledgeHitDetail(
  sourceId: string,
  chunkId: string,
  options: ApiRequestSignalOptions = {},
): Promise<KnowledgeHitDetailResponse> {
  const params = new URLSearchParams();
  params.set('source_id', sourceId);
  params.set('chunk_id', chunkId);
  return apiRequest<KnowledgeHitDetailResponse>(
    `/api/knowledge/hit-detail?${params.toString()}`,
    {
      signal: options.signal,
      timeoutMs: options.timeoutMs,
    },
  );
}
