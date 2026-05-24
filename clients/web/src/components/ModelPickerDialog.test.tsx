import { cleanup, render, screen } from '@testing-library/preact';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { ApiMetaModel } from '../api/meta';
import { ModelPickerDialog } from './ModelPickerDialog';

function model(
  key: string,
  provider: string,
  modelId: string,
  protocol = 'openai',
): ApiMetaModel {
  return {
    key,
    provider,
    provider_id: provider.toLowerCase(),
    protocol,
    model_id: modelId,
    label: modelId,
  };
}

describe('ModelPickerDialog', () => {
  afterEach(() => {
    cleanup();
    localStorage.clear();
  });

  it('prioritizes the active provider group and active model', () => {
    render(
      <ModelPickerDialog
        models={[
          model('anthropic:claude-sonnet-4', 'Anthropic', 'claude-sonnet-4'),
          model('openai:gpt-4.1', 'OpenAI', 'gpt-4.1'),
          model('openai:gpt-4o', 'OpenAI', 'gpt-4o'),
          model('deepseek:chat', 'DeepSeek', 'deepseek-chat'),
        ]}
        selectedKey="openai:gpt-4o"
        onSelect={vi.fn()}
        onClose={vi.fn()}
      />,
    );

    const modelKeys = [...document.querySelectorAll<HTMLButtonElement>('[data-model-key]')]
      .map((button) => button.dataset.modelKey);

    expect(modelKeys.slice(0, 2)).toEqual(['openai:gpt-4o', 'openai:gpt-4.1']);
    expect(screen.getByText(/^(当前默认|Current default)$/)).not.toBeNull();
    expect(screen.getByText(/^(当前提供商|Current provider)$/)).not.toBeNull();
  });
});