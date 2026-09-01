import 'dart:async';
import 'dart:io';

import 'package:characters/characters.dart';

import 'text_clip.dart';
import 'text_normalization.dart';

const int kUserFailureMessageMaxCharacters = 400;

typedef UserFailureDetailResolver = String? Function(Object error);

String userFailureMessage(
  Object error, {
  required String fallback,
  UserFailureDetailResolver? detailResolver,
  int maxCharacters = kUserFailureMessageMaxCharacters,
}) {
  final customDetail = detailResolver?.call(error);
  final detail =
      customDetail ??
      switch (error) {
        FormatException(:final message) => message,
        StateError(:final message) => message,
        UnsupportedError(:final message) => '$message',
        FileSystemException(:final message) => message,
        TimeoutException(:final message) => message ?? '',
        _ => '',
      };
  final normalizedDetail = collapseInlineWhitespace(detail);
  final message = normalizedDetail.isEmpty
      ? collapseInlineWhitespace(fallback)
      : normalizedDetail;
  if (maxCharacters <= 0 || message.isEmpty) return '';
  if (message.characters.length <= maxCharacters) return message;
  return clipTextWithEllipsis(message, maxCharacters);
}
