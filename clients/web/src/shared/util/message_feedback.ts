import type {
  SessionMessage,
  SessionMessageFeedback,
} from '../../api/sessions';
import { normalizeInteger } from './number';
import {
  finiteNumberOrNullFromUnknown,
  recordOrNullFromUnknown,
} from './value';

export function normalizeMessageFeedback(
  value: unknown,
): SessionMessageFeedback | null {
  return value === 'liked' || value === 'needs_improvement' ? value : null;
}

export function messageFeedbackValue(
  message: SessionMessage,
): SessionMessageFeedback | null {
  const direct = normalizeMessageFeedback(message.feedback);
  if (direct) return direct;

  const meta = recordOrNullFromUnknown(message.metadata);
  if (!meta) return null;

  const legacy = normalizeMessageFeedback(meta['message_feedback']);
  if (legacy) return legacy;

  const variants = meta['response_variants'];
  if (!Array.isArray(variants) || variants.length === 0) return null;

  const index = normalizeInteger(
    finiteNumberOrNullFromUnknown(meta['response_variant_index']),
    {
      fallback: 0,
      min: 0,
      max: variants.length - 1,
    },
  );
  return normalizeMessageFeedback(
    recordOrNullFromUnknown(variants[index])?.['message_feedback'],
  );
}
