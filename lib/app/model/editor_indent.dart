const int defaultEditorIndentSpaces = 4;
const int minEditorIndentSpaces = 1;
const int maxEditorIndentSpaces = 8;
const List<int> editorIndentSpaceOptions = <int>[1, 2, 3, 4, 5, 6, 7, 8];

int normalizeEditorIndentSpaces(int? value) {
  if (value == null) {
    return defaultEditorIndentSpaces;
  }
  if (value < minEditorIndentSpaces) {
    return minEditorIndentSpaces;
  }
  if (value > maxEditorIndentSpaces) {
    return maxEditorIndentSpaces;
  }
  return value;
}