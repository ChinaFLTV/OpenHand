import '../../model/ai_attachment.dart';
import '../../model/ai_model_config.dart';
import '../chat/ai_protocol_adapter.dart';

class AiAttachmentInputCapabilities {
  const AiAttachmentInputCapabilities({
    required this.supportsImageInput,
    required this.supportsFileInput,
  });

  static const disabled = AiAttachmentInputCapabilities(
    supportsImageInput: false,
    supportsFileInput: false,
  );

  final bool supportsImageInput;
  final bool supportsFileInput;

  bool get supportsAny => supportsImageInput || supportsFileInput;

  bool supportsKind(AiAttachmentKind kind) {
    return switch (kind) {
      AiAttachmentKind.image => supportsImageInput,
      AiAttachmentKind.text ||
      AiAttachmentKind.spreadsheet ||
      AiAttachmentKind.pdf => supportsFileInput,
      AiAttachmentKind.binary => false,
    };
  }
}

AiAttachmentInputCapabilities resolveAiAttachmentInputCapabilities(
  AiModelConfig? model,
) {
  if (model == null || !model.resolvedSupportsAttachments) {
    return AiAttachmentInputCapabilities.disabled;
  }
  return AiAttachmentInputCapabilities(
    supportsImageInput: _supportsImageInput(model),
    supportsFileInput: true,
  );
}

List<String> aiAttachmentPickerExtensionsForCapabilities(
  AiAttachmentInputCapabilities capabilities,
) {
  return aiAttachmentPickerExtensions()
      .where(
        (extension) => capabilities.supportsKind(
          aiAttachmentKindForPath('attachment.$extension'),
        ),
      )
      .toList(growable: false);
}

bool _supportsImageInput(AiModelConfig model) {
  final profile = model.profileFor(model.modelId);
  if (profile.supportsAttachments == false) {
    return false;
  }
  if (profile.isMultimodal == false) {
    return false;
  }
  if (profile.supportedModalities.contains(AiModelModality.image)) {
    return true;
  }
  if (profile.isMultimodal == true) {
    return true;
  }
  return AiProtocolRegistry.supportsInlineImages(model);
}
