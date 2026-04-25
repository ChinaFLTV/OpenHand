enum AiLspManagedInstallKind {
  none,
  npmLocal,
  pythonVenv,
  gemLocal,
  goInstall,
  directDownload,
}

class AiLspManagedInstallRecipe {
  const AiLspManagedInstallRecipe.none({this.installDocUrl})
    : kind = AiLspManagedInstallKind.none,
      versionedPackages = const <String>[],
      additionalPackages = const <String>[];

  const AiLspManagedInstallRecipe.npmLocal({
    required this.versionedPackages,
    this.additionalPackages = const <String>[],
    this.installDocUrl,
  }) : kind = AiLspManagedInstallKind.npmLocal;

  const AiLspManagedInstallRecipe.pythonVenv({
    required this.versionedPackages,
    this.installDocUrl,
  }) : kind = AiLspManagedInstallKind.pythonVenv,
       additionalPackages = const <String>[];

  const AiLspManagedInstallRecipe.gemLocal({
    required this.versionedPackages,
    this.installDocUrl,
  }) : kind = AiLspManagedInstallKind.gemLocal,
       additionalPackages = const <String>[];

  const AiLspManagedInstallRecipe.goInstall({
    required this.versionedPackages,
    this.installDocUrl,
  }) : kind = AiLspManagedInstallKind.goInstall,
       additionalPackages = const <String>[];

  const AiLspManagedInstallRecipe.directDownload({this.installDocUrl})
    : kind = AiLspManagedInstallKind.directDownload,
      versionedPackages = const <String>[],
      additionalPackages = const <String>[];

  final AiLspManagedInstallKind kind;
  final List<String> versionedPackages;
  final List<String> additionalPackages;
  final String? installDocUrl;

  bool get supportsManagedInstall => kind != AiLspManagedInstallKind.none;
}

class AiLspBackendDescriptor {
  const AiLspBackendDescriptor({
    required this.id,
    required this.displayName,
    required this.languages,
    required this.executable,
    this.arguments = const <String>[],
    this.install = const AiLspManagedInstallRecipe.none(),
  });

  final String id;
  final String displayName;
  final Set<String> languages;
  final String executable;
  final List<String> arguments;
  final AiLspManagedInstallRecipe install;
}

String normalizeAiLspLanguage(String? language) {
  switch ((language ?? '').trim().toLowerCase()) {
    case 'bash':
    case 'shellscript':
      return 'shell';
    case 'c++':
      return 'cpp';
    case 'javascriptreact':
      return 'javascript';
    case 'typescriptreact':
      return 'typescript';
    case 'objective-c':
    case 'objc':
      return 'objectivec';
    case 'objective-cpp':
    case 'objcpp':
      return 'objectivecpp';
    case 'f#':
    case 'fsharp':
      return 'fsharp';
    case 'hcl':
      return 'terraform';
    case '':
      return 'plaintext';
    default:
      return language!.trim().toLowerCase();
  }
}

List<String> aiLspSupportedLanguages() {
  final ordered = <String>[];
  for (final backend in kAiLspBackendCatalog) {
    for (final language in backend.languages) {
      if (!ordered.contains(language)) {
        ordered.add(language);
      }
    }
  }
  return List<String>.unmodifiable(ordered);
}

AiLspBackendDescriptor? aiLspBackendById(String id) {
  final trimmedId = id.trim();
  if (trimmedId.isEmpty) {
    return null;
  }
  for (final backend in kAiLspBackendCatalog) {
    if (backend.id == trimmedId) {
      return backend;
    }
  }
  return null;
}

List<AiLspBackendDescriptor> aiLspBackendsForLanguage(String language) {
  final normalizedLanguage = normalizeAiLspLanguage(language);
  return List<AiLspBackendDescriptor>.unmodifiable(
    kAiLspBackendCatalog.where(
      (backend) => backend.languages.contains(normalizedLanguage),
    ),
  );
}

const List<AiLspBackendDescriptor>
kAiLspBackendCatalog = <AiLspBackendDescriptor>[
  AiLspBackendDescriptor(
    id: 'dart-analysis-server',
    displayName: 'Dart Analysis Server',
    languages: <String>{'dart'},
    executable: 'dart',
    arguments: <String>['language-server', '--lsp'],
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://dart.dev/tools/dart-tool',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'basedpyright',
    displayName: 'BasedPyright',
    languages: <String>{'python'},
    executable: 'basedpyright-langserver',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['basedpyright'],
      installDocUrl: 'https://docs.basedpyright.com/latest/',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'pyright',
    displayName: 'Pyright',
    languages: <String>{'python'},
    executable: 'pyright-langserver',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['pyright'],
      installDocUrl: 'https://github.com/microsoft/pyright',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'python-lsp-server',
    displayName: 'Python LSP Server',
    languages: <String>{'python'},
    executable: 'pylsp',
    install: AiLspManagedInstallRecipe.pythonVenv(
      versionedPackages: <String>['python-lsp-server'],
      installDocUrl: 'https://github.com/python-lsp/python-lsp-server',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'typescript-language-server',
    displayName: 'TypeScript Language Server',
    languages: <String>{'javascript', 'typescript'},
    executable: 'typescript-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['typescript-language-server'],
      additionalPackages: <String>['typescript'],
      installDocUrl:
          'https://github.com/typescript-language-server/typescript-language-server',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'gopls',
    displayName: 'gopls',
    languages: <String>{'go'},
    executable: 'gopls',
    install: AiLspManagedInstallRecipe.goInstall(
      versionedPackages: <String>['golang.org/x/tools/gopls'],
      installDocUrl: 'https://pkg.go.dev/golang.org/x/tools/gopls',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'rust-analyzer',
    displayName: 'rust-analyzer',
    languages: <String>{'rust'},
    executable: 'rust-analyzer',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://rust-analyzer.github.io/book/',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'jdtls',
    displayName: 'JDT Language Server',
    languages: <String>{'java'},
    executable: 'jdtls',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/eclipse-jdtls/eclipse.jdt.ls',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'kotlin-lsp',
    displayName: 'Kotlin LSP',
    languages: <String>{'kotlin'},
    executable: 'kotlin-lsp',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/fwcd/kotlin-language-server',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'clangd',
    displayName: 'clangd',
    languages: <String>{'c', 'cpp'},
    executable: 'clangd',
    arguments: <String>['--background-index'],
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://clangd.llvm.org/installation',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'sourcekit-lsp',
    displayName: 'SourceKit-LSP',
    languages: <String>{'swift'},
    executable: 'sourcekit-lsp',
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/swiftlang/sourcekit-lsp',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'omnisharp',
    displayName: 'OmniSharp',
    languages: <String>{'csharp'},
    executable: 'OmniSharp',
    arguments: <String>['--languageserver'],
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/OmniSharp/omnisharp-roslyn',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'omnisharp-lowercase',
    displayName: 'OmniSharp',
    languages: <String>{'csharp'},
    executable: 'omnisharp',
    arguments: <String>['--languageserver'],
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/OmniSharp/omnisharp-roslyn',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'intelephense',
    displayName: 'Intelephense',
    languages: <String>{'php'},
    executable: 'intelephense',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['intelephense'],
      installDocUrl: 'https://intelephense.com/',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'solargraph',
    displayName: 'Solargraph',
    languages: <String>{'ruby'},
    executable: 'solargraph',
    arguments: <String>['stdio'],
    install: AiLspManagedInstallRecipe.gemLocal(
      versionedPackages: <String>['solargraph'],
      installDocUrl: 'https://solargraph.org/guides/getting-started',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'bash-language-server',
    displayName: 'Bash Language Server',
    languages: <String>{'shell'},
    executable: 'bash-language-server',
    arguments: <String>['start'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['bash-language-server'],
      installDocUrl: 'https://github.com/bash-lsp/bash-language-server',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'yaml-language-server',
    displayName: 'YAML Language Server',
    languages: <String>{'yaml'},
    executable: 'yaml-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['yaml-language-server'],
      installDocUrl: 'https://github.com/redhat-developer/yaml-language-server',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'vscode-json-language-server',
    displayName: 'JSON Language Server',
    languages: <String>{'json'},
    executable: 'vscode-json-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['vscode-langservers-extracted'],
      installDocUrl: 'https://github.com/hrsh7th/vscode-langservers-extracted',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'vscode-html-language-server',
    displayName: 'HTML Language Server',
    languages: <String>{'html'},
    executable: 'vscode-html-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['vscode-langservers-extracted'],
      installDocUrl: 'https://github.com/hrsh7th/vscode-langservers-extracted',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'vscode-css-language-server',
    displayName: 'CSS Language Server',
    languages: <String>{'css'},
    executable: 'vscode-css-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['vscode-langservers-extracted'],
      installDocUrl: 'https://github.com/hrsh7th/vscode-langservers-extracted',
    ),
  ),

  // ── Vue / Svelte / Astro (npm-based frontend LSPs) ──
  AiLspBackendDescriptor(
    id: 'vue-language-server',
    displayName: 'Vue Language Server',
    languages: <String>{'vue'},
    executable: 'vue-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['@vue/language-server'],
      installDocUrl: 'https://github.com/vuejs/language-tools',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'svelte-language-server',
    displayName: 'Svelte Language Server',
    languages: <String>{'svelte'},
    executable: 'svelteserver',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['svelte-language-server'],
      installDocUrl: 'https://github.com/sveltejs/language-tools',
    ),
  ),
  AiLspBackendDescriptor(
    id: 'astro-language-server',
    displayName: 'Astro Language Server',
    languages: <String>{'astro'},
    executable: 'astro-ls',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['@astrojs/language-server'],
      installDocUrl: 'https://github.com/withastro/language-tools',
    ),
  ),

  // ── Lua ──
  AiLspBackendDescriptor(
    id: 'lua-language-server',
    displayName: 'Lua Language Server',
    languages: <String>{'lua'},
    executable: 'lua-language-server',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/LuaLS/lua-language-server',
    ),
  ),

  // ── Zig ──
  AiLspBackendDescriptor(
    id: 'zls',
    displayName: 'ZLS',
    languages: <String>{'zig'},
    executable: 'zls',
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/zigtools/zls',
    ),
  ),

  // ── Elixir ──
  AiLspBackendDescriptor(
    id: 'elixir-ls',
    displayName: 'ElixirLS',
    languages: <String>{'elixir'},
    executable: 'elixir-ls',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/elixir-lsp/elixir-ls',
    ),
  ),

  // ── Terraform ──
  AiLspBackendDescriptor(
    id: 'terraform-ls',
    displayName: 'Terraform LS',
    languages: <String>{'terraform'},
    executable: 'terraform-ls',
    arguments: <String>['serve'],
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/hashicorp/terraform-ls',
    ),
  ),

  // ── Typst ──
  AiLspBackendDescriptor(
    id: 'tinymist',
    displayName: 'Tinymist',
    languages: <String>{'typst'},
    executable: 'tinymist',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://github.com/Myriad-Dreamin/tinymist',
    ),
  ),

  // ── Clojure ──
  AiLspBackendDescriptor(
    id: 'clojure-lsp',
    displayName: 'Clojure LSP',
    languages: <String>{'clojure'},
    executable: 'clojure-lsp',
    install: AiLspManagedInstallRecipe.directDownload(
      installDocUrl: 'https://clojure-lsp.io/',
    ),
  ),

  // ── Ruby LSP (alternative to Solargraph) ──
  AiLspBackendDescriptor(
    id: 'ruby-lsp',
    displayName: 'Ruby LSP',
    languages: <String>{'ruby'},
    executable: 'ruby-lsp',
    install: AiLspManagedInstallRecipe.gemLocal(
      versionedPackages: <String>['ruby-lsp'],
      installDocUrl: 'https://github.com/Shopify/ruby-lsp',
    ),
  ),

  // ── F# ──
  AiLspBackendDescriptor(
    id: 'fsautocomplete',
    displayName: 'FsAutoComplete',
    languages: <String>{'fsharp'},
    executable: 'fsautocomplete',
    arguments: <String>['--adaptive-lsp-server-enabled'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/fsharp/FsAutoComplete',
    ),
  ),

  // ── Haskell ──
  AiLspBackendDescriptor(
    id: 'haskell-language-server',
    displayName: 'HLS',
    languages: <String>{'haskell'},
    executable: 'haskell-language-server-wrapper',
    arguments: <String>['--lsp'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/haskell/haskell-language-server',
    ),
  ),

  // ── OCaml ──
  AiLspBackendDescriptor(
    id: 'ocamllsp',
    displayName: 'OCaml LSP',
    languages: <String>{'ocaml'},
    executable: 'ocamllsp',
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/ocaml/ocaml-lsp',
    ),
  ),

  // ── Deno (built-in LSP) ──
  AiLspBackendDescriptor(
    id: 'deno-lsp',
    displayName: 'Deno LSP',
    languages: <String>{'javascript', 'typescript'},
    executable: 'deno',
    arguments: <String>['lsp'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://docs.deno.com/runtime/',
    ),
  ),

  // ── Gleam ──
  AiLspBackendDescriptor(
    id: 'gleam-lsp',
    displayName: 'Gleam LSP',
    languages: <String>{'gleam'},
    executable: 'gleam',
    arguments: <String>['lsp'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://gleam.run/',
    ),
  ),

  // ── Markdown ──
  AiLspBackendDescriptor(
    id: 'marksman',
    displayName: 'Marksman',
    languages: <String>{'markdown'},
    executable: 'marksman',
    arguments: <String>['server'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/artempyanykh/marksman',
    ),
  ),

  // ── Erlang ──
  AiLspBackendDescriptor(
    id: 'erlang-ls',
    displayName: 'Erlang LS',
    languages: <String>{'erlang'},
    executable: 'erlang_ls',
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/erlang-ls/erlang_ls',
    ),
  ),

  // ── Scala ──
  AiLspBackendDescriptor(
    id: 'metals',
    displayName: 'Metals',
    languages: <String>{'scala'},
    executable: 'metals',
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://scalameta.org/metals/',
    ),
  ),

  // ── R ──
  AiLspBackendDescriptor(
    id: 'r-languageserver',
    displayName: 'R Language Server',
    languages: <String>{'r'},
    executable: 'R',
    arguments: <String>['--slave', '-e', 'languageserver::run()'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/REditorSupport/languageserver',
    ),
  ),

  // ── Julia ──
  AiLspBackendDescriptor(
    id: 'julia-ls',
    displayName: 'Julia LanguageServer',
    languages: <String>{'julia'},
    executable: 'julia',
    arguments: <String>[
      '--startup-file=no',
      '--history-file=no',
      '-e',
      'using LanguageServer; runserver()',
    ],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://github.com/julia-vscode/LanguageServer.jl',
    ),
  ),

  // ── Perl ──
  AiLspBackendDescriptor(
    id: 'perlnavigator',
    displayName: 'PerlNavigator',
    languages: <String>{'perl'},
    executable: 'perlnavigator',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['perlnavigator-server'],
      installDocUrl: 'https://github.com/bscan/PerlNavigator',
    ),
  ),

  // ── TOML ──
  AiLspBackendDescriptor(
    id: 'taplo-lsp',
    displayName: 'Taplo',
    languages: <String>{'toml'},
    executable: 'taplo',
    arguments: <String>['lsp', 'stdio'],
    install: AiLspManagedInstallRecipe.none(
      installDocUrl: 'https://taplo.tamasfe.dev/',
    ),
  ),

  // ── GraphQL ──
  AiLspBackendDescriptor(
    id: 'graphql-language-server',
    displayName: 'GraphQL Language Server',
    languages: <String>{'graphql'},
    executable: 'graphql-lsp',
    arguments: <String>['server', '-m', 'stream'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['graphql-language-service-cli'],
      additionalPackages: <String>['graphql'],
      installDocUrl: 'https://github.com/graphql/graphiql',
    ),
  ),

  // ── Prisma ──
  AiLspBackendDescriptor(
    id: 'prisma-language-server',
    displayName: 'Prisma Language Server',
    languages: <String>{'prisma'},
    executable: 'prisma-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['@prisma/language-server'],
      installDocUrl: 'https://www.prisma.io/',
    ),
  ),

  // ── Dockerfile ──
  AiLspBackendDescriptor(
    id: 'docker-langserver',
    displayName: 'Docker Language Server',
    languages: <String>{'dockerfile'},
    executable: 'docker-langserver',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['dockerfile-language-server-nodejs'],
      installDocUrl:
          'https://github.com/rcjsuen/dockerfile-language-server-nodejs',
    ),
  ),

  // ── SQL ──
  AiLspBackendDescriptor(
    id: 'sqls',
    displayName: 'sqls',
    languages: <String>{'sql'},
    executable: 'sqls',
    install: AiLspManagedInstallRecipe.goInstall(
      versionedPackages: <String>['github.com/sqls-server/sqls'],
      installDocUrl: 'https://github.com/sqls-server/sqls',
    ),
  ),

  // ── Tailwind CSS ──
  AiLspBackendDescriptor(
    id: 'tailwindcss-language-server',
    displayName: 'Tailwind CSS IntelliSense',
    languages: <String>{
      'css',
      'html',
      'javascript',
      'typescript',
      'vue',
      'svelte',
    },
    executable: 'tailwindcss-language-server',
    arguments: <String>['--stdio'],
    install: AiLspManagedInstallRecipe.npmLocal(
      versionedPackages: <String>['@tailwindcss/language-server'],
      installDocUrl: 'https://github.com/tailwindlabs/tailwindcss-intellisense',
    ),
  ),
];
