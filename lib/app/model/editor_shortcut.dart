import 'package:flutter/services.dart';

import 'openhand_shortcut.dart';

enum EditorShortcutAction {
  saveFile,
  triggerCompletion,
  showSignatureHelp,
  find,
  replace,
  goToLine,
  showDocumentSymbols,
  showWorkspaceSymbols,
  goToDefinition,
  findReferences,
  goToImplementation,
  showHoverInfo,
  renameSymbol,
  showCodeActions,
  formatDocument,
}

Map<EditorShortcutAction, List<int>> defaultEditorShortcutBindings() {
  return <EditorShortcutAction, List<int>>{
    EditorShortcutAction.saveFile: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyS.keyId,
    ]),
    EditorShortcutAction.triggerCompletion: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.space.keyId,
    ]),
    EditorShortcutAction.showSignatureHelp: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyP.keyId,
    ]),
    EditorShortcutAction.find: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyF.keyId,
    ]),
    EditorShortcutAction.replace: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyH.keyId,
    ]),
    EditorShortcutAction.goToLine: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyG.keyId,
    ]),
    EditorShortcutAction.showDocumentSymbols: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.shift.keyId,
      LogicalKeyboardKey.keyO.keyId,
    ]),
    EditorShortcutAction.showWorkspaceSymbols: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyT.keyId,
    ]),
    EditorShortcutAction.goToDefinition: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyB.keyId,
    ]),
    EditorShortcutAction.findReferences: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.shift.keyId,
      LogicalKeyboardKey.keyB.keyId,
    ]),
    EditorShortcutAction.goToImplementation: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.alt.keyId,
      LogicalKeyboardKey.keyB.keyId,
    ]),
    EditorShortcutAction.showHoverInfo: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.keyI.keyId,
    ]),
    EditorShortcutAction.renameSymbol: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.f2.keyId,
    ]),
    EditorShortcutAction.showCodeActions: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.control.keyId,
      LogicalKeyboardKey.period.keyId,
    ]),
    EditorShortcutAction.formatDocument: normalizeShortcutKeyIds(<int>[
      LogicalKeyboardKey.shift.keyId,
      LogicalKeyboardKey.tab.keyId,
    ]),
  };
}

String editorShortcutActionStorageKey(EditorShortcutAction action) {
  return switch (action) {
    EditorShortcutAction.saveFile => 'save_file',
    EditorShortcutAction.triggerCompletion => 'trigger_completion',
    EditorShortcutAction.showSignatureHelp => 'show_signature_help',
    EditorShortcutAction.find => 'find',
    EditorShortcutAction.replace => 'replace',
    EditorShortcutAction.goToLine => 'go_to_line',
    EditorShortcutAction.showDocumentSymbols => 'show_document_symbols',
    EditorShortcutAction.showWorkspaceSymbols => 'show_workspace_symbols',
    EditorShortcutAction.goToDefinition => 'go_to_definition',
    EditorShortcutAction.findReferences => 'find_references',
    EditorShortcutAction.goToImplementation => 'go_to_implementation',
    EditorShortcutAction.showHoverInfo => 'show_hover_info',
    EditorShortcutAction.renameSymbol => 'rename_symbol',
    EditorShortcutAction.showCodeActions => 'show_code_actions',
    EditorShortcutAction.formatDocument => 'format_document',
  };
}

EditorShortcutAction? editorShortcutActionFromStorageKey(String rawValue) {
  return switch (rawValue.trim()) {
    'save_file' => EditorShortcutAction.saveFile,
    'trigger_completion' => EditorShortcutAction.triggerCompletion,
    'show_signature_help' => EditorShortcutAction.showSignatureHelp,
    'find' => EditorShortcutAction.find,
    'replace' => EditorShortcutAction.replace,
    'go_to_line' => EditorShortcutAction.goToLine,
    'show_document_symbols' => EditorShortcutAction.showDocumentSymbols,
    'show_workspace_symbols' => EditorShortcutAction.showWorkspaceSymbols,
    'go_to_definition' => EditorShortcutAction.goToDefinition,
    'find_references' => EditorShortcutAction.findReferences,
    'go_to_implementation' => EditorShortcutAction.goToImplementation,
    'show_hover_info' => EditorShortcutAction.showHoverInfo,
    'rename_symbol' => EditorShortcutAction.renameSymbol,
    'show_code_actions' => EditorShortcutAction.showCodeActions,
    'format_document' => EditorShortcutAction.formatDocument,
    _ => null,
  };
}
