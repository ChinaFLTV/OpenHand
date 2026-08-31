import 'package:flutter/services.dart';

/// 工作流整数输入格式化器，只允许可编辑的整数文本。
class WorkflowIntegerInputFormatter extends TextInputFormatter {
  const WorkflowIntegerInputFormatter();

  static final RegExp _pattern = RegExp(r'^-?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// 工作流浮点输入格式化器，只允许可编辑的十进制数字文本。
class WorkflowDecimalInputFormatter extends TextInputFormatter {
  const WorkflowDecimalInputFormatter();

  static final RegExp _pattern = RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d*)?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
