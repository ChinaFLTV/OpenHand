import '../util/input_value_parsing.dart';

enum NativeAudioEffect {
  standard('standard', 1.0),
  spatial('spatial', 1.0),
  vocal('vocal', 1.0),
  warm('warm', 0.96);

  const NativeAudioEffect(this.storageValue, this.volumeScale);

  final String storageValue;
  final double volumeScale;

  static NativeAudioEffect fromStorage(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (effect) => effect.storageValue,
      fallback: NativeAudioEffect.standard,
    );
  }
}

class NativeAudioPlaybackSettings {
  const NativeAudioPlaybackSettings._({
    required this.volume,
    required this.effect,
  });

  factory NativeAudioPlaybackSettings({
    double volume = defaultVolume,
    NativeAudioEffect effect = NativeAudioEffect.standard,
  }) {
    return NativeAudioPlaybackSettings._(
      volume: normalizeVolume(volume),
      effect: effect,
    );
  }

  factory NativeAudioPlaybackSettings.defaults() {
    return const NativeAudioPlaybackSettings._(
      volume: defaultVolume,
      effect: NativeAudioEffect.standard,
    );
  }

  factory NativeAudioPlaybackSettings.fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return NativeAudioPlaybackSettings.defaults();
    return NativeAudioPlaybackSettings._(
      volume: volumeFromValue(json['volume']),
      effect: NativeAudioEffect.fromStorage(json['effect']),
    );
  }

  static const double defaultVolume = 0.86;

  final double volume;
  final NativeAudioEffect effect;

  static double normalizeVolume(double value) {
    return finiteUnitInterval(value, fallback: defaultVolume);
  }

  static double volumeFromValue(Object? value) {
    final parsed = optionalDoubleFromValue(value);
    return parsed == null ? defaultVolume : normalizeVolume(parsed);
  }

  NativeAudioPlaybackSettings normalized() {
    return NativeAudioPlaybackSettings(volume: volume, effect: effect);
  }

  NativeAudioPlaybackSettings copyWith({
    double? volume,
    NativeAudioEffect? effect,
  }) {
    return NativeAudioPlaybackSettings(
      volume: volume ?? this.volume,
      effect: effect ?? this.effect,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'volume': volume,
    'effect': effect.storageValue,
  };

  @override
  bool operator ==(Object other) {
    return other is NativeAudioPlaybackSettings &&
        other.volume == volume &&
        other.effect == effect;
  }

  @override
  int get hashCode => Object.hash(volume, effect);
}
