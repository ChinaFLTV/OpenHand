import 'dart:convert';

const String kimiWebSearchEndpoint =
    'https://api.moonshot.cn/v1/chat/completions';
const String kimiWebSearchModel = 'kimi-latest';

String buildKimiWebSearchRequestBody(String prompt) {
  return jsonEncode({
    'model': kimiWebSearchModel,
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
    'tools': [
      {
        'type': 'builtin_function',
        'function': {'name': '\$web_search'},
      },
    ],
  });
}
