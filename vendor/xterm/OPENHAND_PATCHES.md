# OpenHand xterm Patch Notes

- Guard `BufferLine.getTrimmedLength` so a wide glyph at the last readable cell cannot report a length beyond the backing data.
- Guard `BufferLine.copyFrom` against overlong copy requests during terminal reflow.
- Clamp reflow builder copy ranges to logical line length and keep one-column wide-glyph shrink finite.
- Reset the circular-buffer origin before installing reflow results, preserving row order after scrollback overflow.

These changes keep bidirectional terminal reflow stable after scrollback overflow and prevent wide-character resize failures.
