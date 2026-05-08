import { act, cleanup, render, screen, waitFor } from '@testing-library/preact';
import { afterEach, describe, expect, it } from 'vitest';
import { getOverlayPortalTarget, OverlayPortal } from './OverlayPortal';

function setFullscreenElement(element: Element | null): void {
  Object.defineProperty(document, 'fullscreenElement', {
    configurable: true,
    get: () => element,
  });
  document.dispatchEvent(new Event('fullscreenchange'));
}

afterEach(() => {
  setFullscreenElement(null);
  cleanup();
  document.body.innerHTML = '';
});

describe('OverlayPortal', () => {
  it('uses document.body when the page is not fullscreen', () => {
    expect(getOverlayPortalTarget()).toBe(document.body);
  });

  it('uses the active fullscreen element for overlays', () => {
    const fullscreenRoot = document.createElement('main');
    document.body.appendChild(fullscreenRoot);
    setFullscreenElement(fullscreenRoot);

    expect(getOverlayPortalTarget()).toBe(fullscreenRoot);
  });

  it('moves rendered overlay content when fullscreen target changes', async () => {
    const firstRoot = document.createElement('section');
    const secondRoot = document.createElement('section');
    document.body.append(firstRoot, secondRoot);
    setFullscreenElement(firstRoot);

    render(
      <OverlayPortal>
        <div data-testid="overlay-content">overlay</div>
      </OverlayPortal>,
    );

    const overlay = screen.getByTestId('overlay-content');
    expect(firstRoot.contains(overlay)).toBe(true);

    await act(async () => {
      await new Promise((resolve) => window.setTimeout(resolve, 0));
    });

    setFullscreenElement(secondRoot);

    await waitFor(() => {
      expect(secondRoot.contains(screen.getByTestId('overlay-content'))).toBe(true);
    });
  });
});
