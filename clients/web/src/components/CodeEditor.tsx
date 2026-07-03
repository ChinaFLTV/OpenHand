// 基于 Monaco Editor 的代码编辑器, 通过 jsDelivr CDN 加载
// (~3 MB AMD 包, 不计入主 bundle)。
//
// 用法:
//   <CodeEditor value={content} onChange={setContent}
//               filename="src/main.dart" readOnly={false}/>
//
// 设计:
// - 单例 loader, 多次挂载不会重复 fetch
// - filename 决定语法高亮 (Monaco 内置 languages)
// - readOnly 切换走 updateOptions, 不重建实例
// - 监听 onDidChangeModelContent 回吐外部
// - 外部 value prop 变化时, 仅当与编辑器内值不同才 setValue
//   (避免输入同步过程中游标抖动)
// - 主题随 prefers-color-scheme 切换 vs / vs-dark

import { useEffect, useRef } from 'preact/hooks';

interface MonacoStub {
  editor: {
    create(el: HTMLElement, opts: Record<string, unknown>): MonacoEditor;
    setTheme(name: string): void;
  };
}

interface MonacoEditor {
  dispose(): void;
  getValue(): string;
  setValue(v: string): void;
  updateOptions(opts: Record<string, unknown>): void;
  onDidChangeModelContent(cb: () => void): { dispose(): void };
}

let monacoLoadPromise: Promise<MonacoStub> | null = null;

const MONACO_VERSION = '0.52.2';
const MONACO_BASE = `https://cdn.jsdelivr.net/npm/monaco-editor@${MONACO_VERSION}/min/vs`;
const LANGUAGE_SUFFIX_RULES: ReadonlyArray<{
  suffixes: readonly string[];
  language: string;
}> = [
  { suffixes: ['.dart'], language: 'dart' },
  { suffixes: ['.ts', '.tsx'], language: 'typescript' },
  { suffixes: ['.js', '.mjs', '.cjs', '.jsx'], language: 'javascript' },
  { suffixes: ['.json'], language: 'json' },
  { suffixes: ['.html', '.htm'], language: 'html' },
  { suffixes: ['.css'], language: 'css' },
  { suffixes: ['.scss'], language: 'scss' },
  { suffixes: ['.md', '.markdown'], language: 'markdown' },
  { suffixes: ['.py'], language: 'python' },
  { suffixes: ['.go'], language: 'go' },
  { suffixes: ['.rs'], language: 'rust' },
  { suffixes: ['.java'], language: 'java' },
  { suffixes: ['.kt', '.kts'], language: 'kotlin' },
  { suffixes: ['.swift'], language: 'swift' },
  { suffixes: ['.c', '.h'], language: 'c' },
  { suffixes: ['.cc', '.cpp', '.hpp', '.hxx'], language: 'cpp' },
  { suffixes: ['.cs'], language: 'csharp' },
  { suffixes: ['.rb'], language: 'ruby' },
  { suffixes: ['.php'], language: 'php' },
  { suffixes: ['.sh', '.bash', '.zsh'], language: 'shell' },
  { suffixes: ['.yml', '.yaml'], language: 'yaml' },
  { suffixes: ['.toml', '.ini', '.conf'], language: 'ini' },
  { suffixes: ['.xml', '.svg'], language: 'xml' },
  { suffixes: ['.sql'], language: 'sql' },
  { suffixes: ['.dockerfile', 'dockerfile'], language: 'dockerfile' },
];

function loadMonaco(): Promise<MonacoStub> {
  if (monacoLoadPromise) return monacoLoadPromise;
  monacoLoadPromise = new Promise((resolve, reject) => {
    // 已加载?
    const existing = (window as unknown as { monaco?: MonacoStub }).monaco;
    if (existing) {
      resolve(existing);
      return;
    }
    // 注入 AMD loader
    const loaderScript = document.createElement('script');
    loaderScript.src = `${MONACO_BASE}/loader.js`;
    loaderScript.async = true;
    const cleanupLoaderScript = () => {
      loaderScript.onerror = null;
      loaderScript.onload = null;
    };
    const rejectLoader = (error: Error) => {
      cleanupLoaderScript();
      monacoLoadPromise = null;
      reject(error);
    };
    loaderScript.onerror = () => {
      loaderScript.remove();
      rejectLoader(new Error('failed to load Monaco loader'));
    };
    loaderScript.onload = () => {
      cleanupLoaderScript();
      const w = window as unknown as {
        require?: {
          config(opts: { paths: Record<string, string> }): void;
          (modules: string[], cb: (m: MonacoStub) => void, err?: (e: Error) => void): void;
        };
        monaco?: MonacoStub;
      };
      const requireFn = w.require;
      if (!requireFn) {
        rejectLoader(new Error('AMD require not present after loader.js'));
        return;
      }
      requireFn.config({ paths: { vs: MONACO_BASE } });
      requireFn(['vs/editor/editor.main'], () => {
        const m = w.monaco;
        if (!m) {
          rejectLoader(new Error('window.monaco missing after editor.main load'));
          return;
        }
        resolve(m);
      }, (e) => rejectLoader(e));
    };
    document.head.appendChild(loaderScript);
  });
  return monacoLoadPromise;
}

function languageFromFilename(name: string): string {
  const lower = name.toLowerCase();
  for (const rule of LANGUAGE_SUFFIX_RULES) {
    if (rule.suffixes.some((suffix) => lower.endsWith(suffix))) {
      return rule.language;
    }
  }
  return 'plaintext';
}

export interface CodeEditorProps {
  value: string;
  onChange?(next: string): void;
  filename?: string;
  readOnly?: boolean;
  /// 像素高度; 不传则走 100% (要求父容器有高度)
  height?: number | string;
}

export function CodeEditor({
  value,
  onChange,
  filename = '',
  readOnly = false,
  height,
}: CodeEditorProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const editorRef = useRef<MonacoEditor | null>(null);
  const valueRef = useRef<string>(value);
  const onChangeRef = useRef<typeof onChange>(onChange);
  onChangeRef.current = onChange;

  // 初始化
  useEffect(() => {
    let disposed = false;
    let subscription: { dispose(): void } | null = null;
    void loadMonaco().then((monaco) => {
      if (disposed || !containerRef.current) return;
      const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const editor = monaco.editor.create(containerRef.current, {
        value,
        language: languageFromFilename(filename),
        readOnly,
        theme: isDark ? 'vs-dark' : 'vs',
        automaticLayout: true,
        fontSize: 13,
        minimap: { enabled: false },
        scrollBeyondLastLine: false,
        smoothScrolling: true,
        wordWrap: 'off',
        renderWhitespace: 'selection',
        tabSize: 2,
      });
      editorRef.current = editor;
      subscription = editor.onDidChangeModelContent(() => {
        const v = editor.getValue();
        valueRef.current = v;
        onChangeRef.current?.(v);
      });
    }).catch((e) => {
      if (containerRef.current) {
        containerRef.current.innerText =
          'Failed to load Monaco: ' + (e instanceof Error ? e.message : String(e));
      }
    });
    return () => {
      disposed = true;
      subscription?.dispose();
      editorRef.current?.dispose();
      editorRef.current = null;
    };
  }, []);

  // 外部 value 同步
  useEffect(() => {
    const ed = editorRef.current;
    if (!ed) return;
    if (value !== valueRef.current) {
      valueRef.current = value;
      ed.setValue(value);
    }
  }, [value]);

  useEffect(() => {
    const ed = editorRef.current;
    if (!ed) return;
    ed.updateOptions({ readOnly });
  }, [readOnly]);

  return (
    <div
      ref={containerRef}
      style={{
        width: '100%',
        height: typeof height === 'number' ? `${height}px` : height ?? '100%',
        minHeight: '50vh',
        border: '1px solid var(--m3-outline)',
        borderRadius: '6px',
        overflow: 'hidden',
        background: 'var(--m3-surface)',
      }}
    />
  );
}
