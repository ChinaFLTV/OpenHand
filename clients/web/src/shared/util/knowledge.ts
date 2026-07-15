import { basenameFromPath } from './path';
import { truncateEndText } from './text';
import {
  roundedNonNegativeIntegerFromUnknown,
  stringFromUnknown,
} from './value';

interface KnowledgeBaseUsageMatchOptions {
  hitKey?: (hit: Record<string, unknown>) => string;
  coerceValues?: boolean;
}

const KNOWLEDGE_GENERIC_TERMS = new Set([
  'knowledgebase',
  'knowledge',
  'document',
  'documents',
  'chunk',
  'chunks',
  '知识库',
  '文档',
  '资料',
  '片段',
]);

const KNOWLEDGE_USAGE_TERM_KEYS = [
  'source_title',
  'title',
  'path',
  'chunk_id',
  'source_id',
  'heading_path',
] as const;

const KNOWLEDGE_USAGE_TEXT_KEYS = ['preview', 'content'] as const;

export function knowledgeBaseResultsUsedByAnswer(
  results: Record<string, unknown>[],
  answerText: string,
  { hitKey, coerceValues = false }: KnowledgeBaseUsageMatchOptions = {},
): Record<string, unknown>[] {
  const normalizedAnswer = knowledgeUsageNormalize(answerText);
  if (!normalizedAnswer) return [];
  const used: Record<string, unknown>[] = [];
  const seen = new Set<string>();
  for (const result of results) {
    if (!knowledgeBaseHitUsedByAnswer(result, normalizedAnswer, coerceValues)) {
      continue;
    }
    const key = hitKey?.(result) ?? defaultKnowledgeBaseHitKey(result);
    if (seen.has(key)) continue;
    seen.add(key);
    used.push(result);
  }
  return used;
}

function knowledgeBaseHitTokenEstimate(hit: Record<string, unknown>): number {
  return roundedNonNegativeIntegerFromUnknown(hit['token_estimate']);
}

export function knowledgeBaseHitTokenEstimateTotal(
  hits: Iterable<Record<string, unknown>>,
): number {
  let total = 0;
  for (const hit of hits) {
    total += knowledgeBaseHitTokenEstimate(hit);
  }
  return total;
}

function knowledgeBaseHitUsedByAnswer(
  hit: Record<string, unknown>,
  normalizedAnswer: string,
  coerceValues: boolean,
): boolean {
  for (const term of knowledgeBaseHitUsageTerms(hit, coerceValues)) {
    const normalizedTerm = knowledgeUsageNormalize(term);
    if (!knowledgeUsageTermWorthMatching(term, normalizedTerm)) continue;
    if (normalizedAnswer.includes(normalizedTerm)) return true;
  }
  return false;
}

function knowledgeBaseHitUsageTerms(
  hit: Record<string, unknown>,
  coerceValues: boolean,
): string[] {
  const terms: string[] = [];
  for (const key of KNOWLEDGE_USAGE_TERM_KEYS) {
    const value = knowledgeValueString(hit[key], coerceValues);
    if (!value) continue;
    terms.push(value);
    if (key === 'path') {
      const basename = basenameFromPath(value);
      if (basename) terms.push(basename);
    }
    if (key === 'heading_path') {
      for (const part of value.split(/[>/\\|]+/g)) {
        const trimmed = part.trim();
        if (trimmed) terms.push(trimmed);
      }
    }
  }
  for (const key of KNOWLEDGE_USAGE_TEXT_KEYS) {
    const value = knowledgeValueString(hit[key], coerceValues);
    if (!value) continue;
    terms.push(...knowledgeStableTextFragments(value));
  }
  return terms;
}

function knowledgeStableTextFragments(text: string): string[] {
  return text
    .split(/[\r\n。！？!?；;]+/g)
    .map((part) => part.trim())
    .filter((part) => part.length >= 12)
    .map((part) => truncateEndText(part, 90, { ellipsis: '' }));
}

function knowledgeUsageTermWorthMatching(raw: string, normalized: string): boolean {
  if (!normalized) return false;
  const hasCjk = /[\u4e00-\u9fff]/.test(raw);
  if (normalized.length < (hasCjk ? 4 : 8)) return false;
  return !KNOWLEDGE_GENERIC_TERMS.has(normalized);
}

function knowledgeUsageNormalize(value: string): string {
  return value
    .toLowerCase()
    .replace(/[\s`~!@#$%^&*()_\-+={}\[\]|\\:;"'<>,.?/，。、《》？；：‘’“”【】（）！￥…—·、]+/g, '')
    .trim();
}

function knowledgeValueString(value: unknown, coerce: boolean): string {
  return stringFromUnknown(value, { coerce });
}

function defaultKnowledgeBaseHitKey(hit: Record<string, unknown>): string {
  const sourceId = knowledgeValueString(hit['source_id'], false);
  if (sourceId) return `source:${sourceId}`;
  const path =
    knowledgeValueString(hit['path'], false) ||
    knowledgeValueString(hit['original_path'], false);
  if (path) return `path:${path}`;
  const chunkId =
    knowledgeValueString(hit['chunk_id'], false) ||
    knowledgeValueString(hit['id'], false);
  if (chunkId) return `chunk:${chunkId}`;
  const label =
    knowledgeValueString(hit['source_title'], false) ||
    knowledgeValueString(hit['title'], false);
  return `label:${label}`;
}
