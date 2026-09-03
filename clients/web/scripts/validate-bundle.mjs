#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const outDir = path.resolve(process.argv[2] ?? '../../assets/web');
const errors = [];
const exportCache = new Map();
const MAX_EAGER_JS_BYTES = 512 * 1024;
const MAX_SESSIONS_LIST_ROUTE_BYTES = 128 * 1024;

function walkJsFiles(dir) {
  const files = [];
  for (const name of readdirSync(dir)) {
    const fullPath = path.join(dir, name);
    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      files.push(...walkJsFiles(fullPath));
    } else if (name.endsWith('.js')) {
      files.push(fullPath);
    }
  }
  return files;
}

function splitSpecList(value) {
  return value
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

function importedName(spec) {
  const match = /^(.+?)\s+as\s+.+$/.exec(spec);
  return (match ? match[1] : spec).trim();
}

function exportedName(spec) {
  const match = /^.+?\s+as\s+(.+)$/.exec(spec);
  return (match ? match[1] : spec).trim();
}

function resolveRelativeModule(fromFile, specifier) {
  if (!specifier.startsWith('.')) return null;
  const cleanSpecifier = specifier.split(/[?#]/, 1)[0];
  return path.resolve(path.dirname(fromFile), cleanSpecifier);
}

function validateRelativeModuleExists(fromFile, specifier) {
  const target = resolveRelativeModule(fromFile, specifier);
  if (target && !existsSync(target)) {
    errors.push(
      `${path.relative(outDir, fromFile)} 缺少引用模块 ${specifier}`,
    );
  }
}

function readExports(file) {
  if (exportCache.has(file)) return exportCache.get(file);
  const source = readFileSync(file, 'utf8');
  const names = new Set();

  for (const match of source.matchAll(/export\s*\{([^}]+)\}/g)) {
    for (const spec of splitSpecList(match[1])) {
      names.add(exportedName(spec));
    }
  }
  for (const match of source.matchAll(/export\s+(?:const|let|var|function|class)\s+([A-Za-z_$][\w$]*)/g)) {
    names.add(match[1]);
  }
  if (/export\s+default\b/.test(source)) {
    names.add('default');
  }

  exportCache.set(file, names);
  return names;
}

function validateNamedModuleReference(fromFile, specList, specifier, kind) {
  const target = resolveRelativeModule(fromFile, specifier);
  if (!target) return;
  if (!existsSync(target)) {
    errors.push(`${path.relative(outDir, fromFile)} 的${kind}缺少模块 ${specifier}`);
    return;
  }

  const exports = readExports(target);
  for (const spec of splitSpecList(specList)) {
    const name = importedName(spec);
    if (!exports.has(name)) {
      const relFrom = path.relative(outDir, fromFile);
      const relTarget = path.relative(outDir, target);
      errors.push(`${relFrom} 从 ${relTarget} ${kind} ${name}，但目标未导出该名称`);
    }
  }
}

if (!existsSync(outDir)) {
  console.error(`[产物校验] 找不到输出目录：${outDir}`);
  process.exit(1);
}

for (const file of walkJsFiles(outDir)) {
  const source = readFileSync(file, 'utf8');
  for (const match of source.matchAll(/\b(?:from|import)\s*(?:\(\s*)?["'`]([^"'`]+)["'`]\s*\)?/g)) {
    validateRelativeModuleExists(file, match[1]);
  }
  for (const match of source.matchAll(/import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)) {
    validateNamedModuleReference(file, match[1], match[2], '导入');
  }
  for (const match of source.matchAll(/export\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)) {
    validateNamedModuleReference(file, match[1], match[2], '重新导出');
  }
}

const indexFile = path.join(outDir, 'index.html');
const entryFile = path.join(outDir, 'app.js');
if (!existsSync(indexFile) || !existsSync(entryFile)) {
  errors.push('缺少 Web 入口产物 index.html 或 app.js');
} else {
  const indexSource = readFileSync(indexFile, 'utf8');
  const entrySource = readFileSync(entryFile, 'utf8');
  const eagerFiles = new Set([entryFile]);
  for (const match of indexSource.matchAll(
    /<link\b[^>]*\brel=["']modulepreload["'][^>]*\bhref=["']([^"']+)["'][^>]*>/g,
  )) {
    const target = path.resolve(outDir, match[1].replace(/^\/+/, ''));
    if (!existsSync(target)) {
      errors.push(`入口预加载资源不存在：${match[1]}`);
      continue;
    }
    eagerFiles.add(target);
  }
  const eagerBytes = [...eagerFiles].reduce(
    (total, file) => total + statSync(file).size,
    0,
  );
  if (eagerBytes > MAX_EAGER_JS_BYTES) {
    errors.push(
      `首屏 JavaScript 共 ${eagerBytes} 字节，超过 ${MAX_EAGER_JS_BYTES} 字节上限`,
    );
  }

  // 会话详情体积较大，禁止再次通过列表 barrel 合入列表路由。
  const sessionListChunks = new Set(
    [...entrySource.matchAll(/chunks\/(sessions-[A-Za-z0-9_-]+\.js)/g)]
      .map((match) => path.join(outDir, 'chunks', match[1])),
  );
  if (sessionListChunks.size !== 1) {
    errors.push(`无法唯一识别会话列表路由产物：${sessionListChunks.size} 个`);
  } else {
    const [sessionListChunk] = sessionListChunks;
    const sessionListBytes = existsSync(sessionListChunk)
      ? statSync(sessionListChunk).size
      : 0;
    if (sessionListBytes > MAX_SESSIONS_LIST_ROUTE_BYTES) {
      errors.push(
        `会话列表路由共 ${sessionListBytes} 字节，超过 ${MAX_SESSIONS_LIST_ROUTE_BYTES} 字节上限`,
      );
    }
  }
}

if (errors.length > 0) {
  console.error('[产物校验] 检测到构建产物错误：');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}
