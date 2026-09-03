#!/usr/bin/env node
import { createHash } from 'node:crypto';
import {
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const BUILD_ID_PLACEHOLDER = '__OPENHAND_BUILD_ID__';
const BUILD_ID_LENGTH = 16;
const outDir = path.resolve(process.argv[2] ?? '../../assets/web');
const serviceWorkerFile = path.join(outDir, 'sw.js');

function outputFiles(directory) {
  const files = [];
  for (const name of readdirSync(directory).sort()) {
    const file = path.join(directory, name);
    if (statSync(file).isDirectory()) {
      files.push(...outputFiles(file));
    } else {
      files.push(file);
    }
  }
  return files;
}

const serviceWorkerSource = readFileSync(serviceWorkerFile, 'utf8');
if (!serviceWorkerSource.includes(BUILD_ID_PLACEHOLDER)) {
  console.error('[Service Worker] 构建产物缺少缓存版本占位符。');
  process.exit(1);
}

const hash = createHash('sha256');
for (const file of outputFiles(outDir)) {
  hash.update(path.relative(outDir, file));
  hash.update('\0');
  hash.update(readFileSync(file));
  hash.update('\0');
}
const buildId = hash.digest('hex').slice(0, BUILD_ID_LENGTH);
writeFileSync(
  serviceWorkerFile,
  serviceWorkerSource.replaceAll(BUILD_ID_PLACEHOLDER, buildId),
);
console.log(`[Service Worker] 缓存版本已更新：${buildId}`);
