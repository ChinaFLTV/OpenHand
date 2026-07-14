/**
 * Unit tests for shipped virtual_message_list_math helpers.
 * Run: node --experimental-strip-types clients/web/scripts/virtual-message-list-math.test.mjs
 * (or via package.json "test:virtual-list")
 */
import assert from 'node:assert/strict';
import {
  MESSAGE_LIST_VIRTUALIZATION_THRESHOLD,
  boundLiveMessageWindow,
  buildHeightPrefix,
  clampMessageRowHeight,
  firstVirtualMessageAfter,
  firstVirtualMessageIntersecting,
  initialVirtualMessageRange,
  resolveVirtualMessageRange,
  remainingNewerMessageCount,
  shouldVirtualizeMessageList,
  virtualMessageTop,
  virtualMessageTotalHeight,
} from '../src/shared/util/virtual_message_list_math.ts';

function test(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    console.error(error);
    process.exitCode = 1;
  }
}

test('shouldVirtualize only after threshold', () => {
  assert.equal(shouldVirtualizeMessageList(MESSAGE_LIST_VIRTUALIZATION_THRESHOLD), false);
  assert.equal(shouldVirtualizeMessageList(MESSAGE_LIST_VIRTUALIZATION_THRESHOLD + 1), true);
});

test('live window stays bounded while retaining the latest tail', () => {
  const underLimit = [1, 2, 3];
  const unchanged = boundLiveMessageWindow(underLimit, 7, 3);
  assert.equal(unchanged.items, underLimit);
  assert.equal(unchanged.offset, 7);
  assert.deepEqual(
    boundLiveMessageWindow([1, 2, 3, 4, 5], 7, 3),
    { items: [3, 4, 5], offset: 9 },
  );
  assert.equal(remainingNewerMessageCount(100, 20, 50), 30);
  assert.equal(remainingNewerMessageCount(10, 0, 20), 0);
});

test('initial range mounts full list below threshold', () => {
  const range = initialVirtualMessageRange(20);
  assert.deepEqual(range, { start: 0, end: 20 });
});

test('initial range for large N is a bounded latest tail', () => {
  const n = 1000;
  const range = initialVirtualMessageRange(n);
  assert.ok(range.end === n);
  assert.ok(range.start > 0);
  assert.ok(range.end - range.start <= 20);
  assert.ok(range.end - range.start >= 8);
});

test('clampMessageRowHeight bounds and fallbacks', () => {
  assert.equal(clampMessageRowHeight(Number.NaN), 188);
  assert.equal(clampMessageRowHeight(-10), 188);
  assert.equal(clampMessageRowHeight(10), 44);
  assert.equal(clampMessageRowHeight(99999), 1400);
  assert.equal(clampMessageRowHeight(200.4), 200);
});

test('height prefix and total height math for N=500', () => {
  const n = 500;
  const heights = Array.from({ length: n }, () => 100);
  const prefix = buildHeightPrefix(heights);
  assert.equal(prefix.length, n + 1);
  assert.equal(prefix[0], 0);
  assert.equal(prefix[n], n * 100);
  assert.equal(virtualMessageTop(prefix, 0), 0);
  assert.equal(virtualMessageTop(prefix, 2, 12), 200 + 24);
  const total = virtualMessageTotalHeight(prefix, n, 12);
  assert.equal(total, n * 100 + (n - 1) * 12);
});

test('binary search range resolves a bounded visible window', () => {
  const n = 400;
  const heights = Array.from({ length: n }, () => 120);
  const prefix = buildHeightPrefix(heights);
  const viewportTop = 20_000;
  const viewportBottom = 20_000 + 800;
  const range = resolveVirtualMessageRange({
    messageCount: n,
    prefix,
    heights,
    viewportTop,
    viewportBottom,
    overscanPx: 560,
    virtualized: true,
  });
  assert.ok(range.start >= 0);
  assert.ok(range.end <= n);
  assert.ok(range.end > range.start);
  assert.ok(range.end - range.start < n);
  assert.ok(range.end - range.start < 30);

  const mid = firstVirtualMessageIntersecting(prefix, heights, viewportTop);
  const after = firstVirtualMessageAfter(prefix, heights, viewportBottom);
  assert.ok(mid <= after);
});

test('non-virtualized resolve returns full span', () => {
  const heights = [100, 100, 100];
  const prefix = buildHeightPrefix(heights);
  const range = resolveVirtualMessageRange({
    messageCount: 3,
    prefix,
    heights,
    viewportTop: 0,
    viewportBottom: 100,
    virtualized: false,
  });
  assert.deepEqual(range, { start: 0, end: 3 });
});

if (process.exitCode) {
  console.error('virtual_message_list_math tests failed');
  process.exit(process.exitCode);
}
console.log('all virtual_message_list_math tests passed');
