# OpenHand xterm Patch Notes

- Guard `BufferLine.getTrimmedLength` so a wide glyph at the last readable cell cannot report a length beyond the backing data.
- Guard `BufferLine.copyFrom` against overlong copy requests during terminal reflow.
- Clamp reflow builder copy ranges to logical line length and keep one-column wide-glyph shrink finite.

This prevents `RangeError: Invalid value ... 256` during `TerminalView` layout resize while keeping xterm reflow enabled.
