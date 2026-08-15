import '../../model/ai_api_dialect.dart';
import '../../model/ai_attachment.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_protocol_adapter.dart';

class AiAttachmentInputCapabilities {
  const AiAttachmentInputCapabilities({
    required this.supportsImageInput,
    required this.supportsVideoInput,
    required this.supportsAudioInput,
    required this.supportsFileInput,
    this.allowedExtensions,
  });

  static const disabled = AiAttachmentInputCapabilities(
    supportsImageInput: false,
    supportsVideoInput: false,
    supportsAudioInput: false,
    supportsFileInput: false,
  );

  final bool supportsImageInput;
  final bool supportsVideoInput;
  final bool supportsAudioInput;
  final bool supportsFileInput;
  final Set<String>? allowedExtensions;

  bool get supportsAny =>
      supportsImageInput ||
      supportsVideoInput ||
      supportsAudioInput ||
      supportsFileInput;

  bool supportsKind(AiAttachmentKind kind) {
    return switch (kind) {
      AiAttachmentKind.image => supportsImageInput,
      AiAttachmentKind.video => supportsVideoInput,
      AiAttachmentKind.audio => supportsAudioInput,
      AiAttachmentKind.text ||
      AiAttachmentKind.spreadsheet ||
      AiAttachmentKind.pdf => supportsFileInput,
      AiAttachmentKind.binary => false,
    };
  }

  bool supportsPath(String path) {
    if (!supportsKind(aiAttachmentKindForPath(path))) return false;
    final restrictions = allowedExtensions;
    if (restrictions == null) return true;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return restrictions.contains(path.substring(dot + 1).toLowerCase());
  }
}

AiAttachmentInputCapabilities resolveAiAttachmentInputCapabilities(
  AiModelConfig? model,
) {
  if (model == null || !model.resolvedSupportsAttachments) {
    return AiAttachmentInputCapabilities.disabled;
  }
  final profile = model.profileFor(model.modelId);
  return AiAttachmentInputCapabilities(
    supportsImageInput: _supportsImageInput(model, profile),
    supportsVideoInput: _supportsModalityInput(
      model,
      profile,
      AiModelModality.video,
    ),
    supportsAudioInput: _supportsModalityInput(
      model,
      profile,
      AiModelModality.audio,
    ),
    supportsFileInput:
        !(model.protocolType == AiProtocolType.dots &&
            model.apiDialect == AiApiDialect.anthropicNative) &&
        (model.protocolType != AiProtocolType.mimo ||
            profile.supportedModalities.contains(AiModelModality.file)),
    allowedExtensions: model.protocolType == AiProtocolType.mimo
        ? _mimoAllowedExtensions(model)
        : null,
  );
}

List<String> aiAttachmentPickerExtensionsForCapabilities(
  AiAttachmentInputCapabilities capabilities,
) {
  return aiAttachmentPickerExtensions()
      .where((extension) => capabilities.supportsPath('attachment.$extension'))
      .toList(growable: false);
}

bool _supportsImageInput(AiModelConfig model, AiModelProfile profile) {
  if (profile.supportsAttachments == false) {
    return false;
  }
  if (profile.isMultimodal == false) {
    return false;
  }
  if (profile.supportedModalities.isNotEmpty) {
    return profile.supportedModalities.contains(AiModelModality.image);
  }
  if (profile.isMultimodal == true) {
    return true;
  }
  return AiProtocolRegistry.supportsInlineImages(model);
}

Set<String> _mimoAllowedExtensions(AiModelConfig model) {
  if (model.modelId.trim().toLowerCase() == 'mimo-v2.5-asr') {
    return const <String>{'mp3', 'wav'};
  }
  if (model.apiDialect == AiApiDialect.anthropicNative) {
    return const <String>{'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
  }
  return const <String>{
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'mp3',
    'wav',
    'flac',
    'm4a',
    'ogg',
    'mp4',
    'mov',
    'avi',
    'wmv',
  };
}

bool _supportsModalityInput(
  AiModelConfig model,
  AiModelProfile profile,
  AiModelModality modality,
) {
  if (model.protocolType == AiProtocolType.dots &&
      model.apiDialect == AiApiDialect.anthropicNative &&
      modality != AiModelModality.image) {
    return false;
  }
  if (model.protocolType == AiProtocolType.mimo &&
      model.apiDialect == AiApiDialect.anthropicNative) {
    return false;
  }
  if (profile.supportsAttachments == false || profile.isMultimodal == false) {
    return false;
  }
  return profile.supportedModalities.contains(modality);
}
