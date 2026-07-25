#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const outDir = path.resolve(process.argv[2] ?? '../../assets/web');
const errors = [];
const exportCache = new Map();

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
  for (const match of source.matchAll(/import\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)) {
    validateNamedModuleReference(file, match[1], match[2], '导入');
  }
  for (const match of source.matchAll(/export\s*\{([^}]+)\}\s*from\s*["']([^"']+)["']/g)) {
    validateNamedModuleReference(file, match[1], match[2], '重新导出');
  }
}

if (errors.length > 0) {
  console.error('[产物校验] 检测到 ESM 导入与导出不匹配：');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}
