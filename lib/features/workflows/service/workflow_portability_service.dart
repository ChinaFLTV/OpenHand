import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:yaml/yaml.dart';

import '../../../app/theme/openhand_theme_preset.dart';
import '../../../shared/util/hex_encoding.dart';
import '../../../shared/util/xml_escape.dart';
import '../model/workflow_definition.dart';
import '../workflow_node_presentation.dart';
import 'workflow_auto_layout.dart';

const int _kMaxYamlDepth = 64;
const int _kMaxYamlValues = 100000;
const double _kNodeWidth = kWorkflowNodeWidth;
const double _kNodeHeight = kWorkflowNodeHeight;
const double _kExportPadding = 72;
const double _kGridSpacing = 24;
const double _kGridMajorSpacing = 120;
const double _kGridDotRadius = 0.8;
const double _kGridMajorDotRadius = 1.45;
const double _kNodePadding = 14;
const double _kNodeIconSize = 34;
const double _kNodeIconRadius = 10;
const double _kNodeCornerRadius = 18;
const double _kNodePortRadius = 4;
const double _kConnectionStroke = 2.4;
const double _kConnectionHalo = 7;

/// 普通画布按 3 倍逻辑尺寸导出；超大画布仍受边长与像素上限保护。
const double _kPreferredExportScale = 3.0;
const double _kMaxRasterSide = 8192;
const int _kMaxRasterPixels = 16 * 1024 * 1024;
const double _kMaxLogicalSpan = 100000;
const String _kWorkflowFormat = 'openhand-workflow';
const int _kWorkflowFormatVersion = 1;

enum WorkflowExportFormat {
  yaml('YAML 配置文件', 'yaml', 'YAML'),
  png('PNG 图片', 'png', 'PNG'),
  jpeg('JPEG 图片', 'jpeg', 'JPEG'),
  svg('SVG 矢量图', 'svg', 'SVG');

  const WorkflowExportFormat(this.label, this.extension, this.typeLabel);

  final String label;
  final String extension;
  final String typeLabel;
}

class WorkflowExportArtifact {
  const WorkflowExportArtifact({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final WorkflowExportFormat format;
  final int? width;
  final int? height;
}

class WorkflowPortabilityException implements Exception {
  const WorkflowPortabilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

WorkflowDefinition decodeWorkflowYaml(String source) {
  if (source.trim().isEmpty) {
    throw const WorkflowPortabilityException('配置文件内容为空。');
  }
  Object? loaded;
  try {
    loaded = loadYaml(source);
  } on YamlException catch (error) {
    throw WorkflowPortabilityException('YAML 语法无效：${error.message}');
  } catch (error) {
    throw WorkflowPortabilityException('无法解析 YAML：$error');
  }

  var valueCount = 0;
  Object? toPlain(Object? value, int depth) {
    if (depth > _kMaxYamlDepth) {
      throw const WorkflowPortabilityException('YAML 嵌套层级过深。');
    }
    valueCount += 1;
    if (valueCount > _kMaxYamlValues) {
      throw const WorkflowPortabilityException('YAML 包含的配置项过多。');
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': toPlain(entry.value, depth + 1),
      };
    }
    if (value is List) {
      return value
          .map((item) => toPlain(item, depth + 1))
          .toList(growable: false);
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw WorkflowPortabilityException('YAML 包含不支持的数据类型：${value.runtimeType}。');
  }

  final plain = toPlain(loaded, 0);
  if (plain is! Map<String, Object?>) {
    throw const WorkflowPortabilityException('YAML 根节点必须是对象。');
  }
  if ('${plain['format'] ?? ''}'.trim() != _kWorkflowFormat) {
    throw const WorkflowPortabilityException(
      '配置格式无效，仅支持由 OpenHand 导出的工作流 YAML。',
    );
  }
  final version = plain['version'];
  if (version is! num || version.toInt() != _kWorkflowFormatVersion) {
    throw WorkflowPortabilityException('不支持的工作流配置版本：${version ?? '缺失'}。');
  }
  final workflow = plain['workflow'];
  if (workflow is! Map<String, Object?>) {
    throw const WorkflowPortabilityException('配置中缺少 workflow 对象。');
  }
  final nodes = workflow['nodes'];
  final connections = workflow['connections'];
  final annotations = workflow['annotations'];
  if (nodes is List && nodes.length > maxWorkflowNodeCount) {
    throw const WorkflowPortabilityException(
      '工作流节点数量超过 $maxWorkflowNodeCount 个安全上限。',
    );
  }
  if (connections is List && connections.length > maxWorkflowConnectionCount) {
    throw const WorkflowPortabilityException(
      '工作流连线数量超过 $maxWorkflowConnectionCount 条安全上限。',
    );
  }
  if (annotations is List && annotations.length > maxWorkflowAnnotationCount) {
    throw const WorkflowPortabilityException(
      '工作流注释数量超过 $maxWorkflowAnnotationCount 个安全上限。',
    );
  }
  try {
    final definition = WorkflowDefinition.fromJson(workflow);
    if (utf8.encode(definition.encode()).length > maxWorkflowEncodedBytes) {
      throw const WorkflowPortabilityException('工作流解码后的数据超过 4 MiB 安全上限。');
    }
    return definition;
  } on WorkflowPortabilityException {
    rethrow;
  } on FormatException catch (error) {
    throw WorkflowPortabilityException('工作流数据无效：${error.message}');
  } catch (error) {
    throw WorkflowPortabilityException('工作流数据解析失败：$error');
  }
}

/// 在隔离区解析 YAML，避免把 Flutter 页面状态或渲染对象带入后台任务。
Future<WorkflowDefinition> decodeWorkflowYamlInIsolate(String source) {
  return Isolate.run<WorkflowDefinition>(() => decodeWorkflowYaml(source));
}

String encodeWorkflowYaml(WorkflowDefinition workflow) {
  final buffer = StringBuffer()
    ..writeln('format: $_kWorkflowFormat')
    ..writeln('version: $_kWorkflowFormatVersion')
    ..writeln('workflow:');
  _writeYamlValue(buffer, workflow.toJson(), 1);
  return buffer.toString();
}

String workflowExportFileName(
  WorkflowDefinition workflow,
  WorkflowExportFormat format,
) {
  final stem = workflow.name
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final safeStem = stem.isEmpty ? 'workflow' : stem;
  final clipped = safeStem.length > 80 ? safeStem.substring(0, 80) : safeStem;
  return '$clipped.${format.extension}';
}

Future<WorkflowExportArtifact> buildWorkflowExportArtifact(
  WorkflowDefinition workflow,
  WorkflowExportFormat format, {
  void Function(double progress, String message)? onProgress,
}) async {
  onProgress?.call(0.12, '正在检查工作流结构…');
  if (workflow.nodes.length > maxWorkflowNodeCount ||
      workflow.connections.length > maxWorkflowConnectionCount ||
      workflow.annotations.length > maxWorkflowAnnotationCount) {
    throw const WorkflowPortabilityException('工作流规模超过导出安全上限。');
  }
  if (format == WorkflowExportFormat.yaml) {
    onProgress?.call(0.62, '正在生成 YAML 配置…');
    final encoded = await Isolate.run(() => encodeWorkflowYaml(workflow));
    final bytes = Uint8List.fromList(utf8.encode(encoded));
    onProgress?.call(0.84, '配置文件已生成，正在写入磁盘…');
    return WorkflowExportArtifact(
      bytes: bytes,
      format: format,
      width: null,
      height: null,
    );
  }

  final layout = _WorkflowExportLayout.from(workflow);
  onProgress?.call(0.32, '正在计算完整画布边界…');
  if (format == WorkflowExportFormat.svg) {
    onProgress?.call(0.62, '正在绘制 SVG 矢量图…');
    final bytes = Uint8List.fromList(utf8.encode(_renderSvg(workflow, layout)));
    onProgress?.call(0.84, '矢量图已生成，正在写入磁盘…');
    return WorkflowExportArtifact(
      bytes: bytes,
      format: format,
      width: layout.outputWidth,
      height: layout.outputHeight,
    );
  }

  onProgress?.call(0.54, '正在绘制全部节点、注释和连线…');
  final raster = await _renderRaster(workflow, layout);
  if (format == WorkflowExportFormat.png) {
    onProgress?.call(0.76, '正在编码 PNG 图片…');
    final byteData = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    if (byteData == null) {
      throw const WorkflowPortabilityException('PNG 编码器未返回有效数据。');
    }
    onProgress?.call(0.84, '图片已生成，正在写入磁盘…');
    return WorkflowExportArtifact(
      bytes: byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      format: format,
      width: layout.outputWidth,
      height: layout.outputHeight,
    );
  }

  onProgress?.call(0.74, '正在编码 JPEG 图片…');
  final byteData = await raster.toByteData();
  raster.dispose();
  if (byteData == null) {
    throw const WorkflowPortabilityException('JPEG 编码器未返回有效数据。');
  }
  final rgbaBytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  final outputWidth = layout.outputWidth;
  final outputHeight = layout.outputHeight;
  final bytes = await Isolate.run(() {
    final decoded = image.Image.fromBytes(
      width: outputWidth,
      height: outputHeight,
      bytes: rgbaBytes.buffer,
      bytesOffset: rgbaBytes.offsetInBytes,
      numChannels: 4,
      order: image.ChannelOrder.rgba,
    );
    return Uint8List.fromList(image.encodeJpg(decoded));
  });
  onProgress?.call(0.84, '图片已生成，正在写入磁盘…');
  return WorkflowExportArtifact(
    bytes: bytes,
    format: format,
    width: layout.outputWidth,
    height: layout.outputHeight,
  );
}

void _writeYamlValue(StringBuffer buffer, Object? value, int depth) {
  final indent = '  ' * depth;
  if (value is Map) {
    if (value.isEmpty) {
      buffer.writeln('$indent{}');
      return;
    }
    for (final entry in value.entries) {
      final key = _yamlScalar('${entry.key}');
      if (_isYamlCollection(entry.value)) {
        if ((entry.value is Map && (entry.value as Map).isEmpty) ||
            (entry.value is List && (entry.value as List).isEmpty)) {
          buffer.writeln('$indent$key: ${entry.value is Map ? '{}' : '[]'}');
        } else {
          buffer.writeln('$indent$key:');
          _writeYamlValue(buffer, entry.value, depth + 1);
        }
      } else {
        buffer.writeln('$indent$key: ${_yamlScalar(entry.value)}');
      }
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      buffer.writeln('$indent[]');
      return;
    }
    for (final item in value) {
      if (_isYamlCollection(item)) {
        if ((item is Map && item.isEmpty) || (item is List && item.isEmpty)) {
          buffer.writeln('$indent- ${item is Map ? '{}' : '[]'}');
        } else {
          buffer.writeln('$indent-');
          _writeYamlValue(buffer, item, depth + 1);
        }
      } else {
        buffer.writeln('$indent- ${_yamlScalar(item)}');
      }
    }
    return;
  }
  buffer.writeln('$indent${_yamlScalar(value)}');
}

bool _isYamlCollection(Object? value) => value is Map || value is List;

String _yamlScalar(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is int) return '$value';
  if (value is double) {
    if (!value.isFinite) {
      throw const WorkflowPortabilityException('工作流包含无法导出的非有限数值。');
    }
    return value.toString();
  }
  if (value is num) return value.toString();
  if (value is String) return jsonEncode(value);
  throw WorkflowPortabilityException('工作流包含无法导出的数据类型：${value.runtimeType}。');
}

class _WorkflowExportLayout {
  const _WorkflowExportLayout({
    required this.bounds,
    required this.scale,
    required this.outputWidth,
    required this.outputHeight,
  });

  factory _WorkflowExportLayout.from(WorkflowDefinition workflow) {
    if (workflow.nodes.isEmpty && workflow.annotations.isEmpty) {
      return const _WorkflowExportLayout(
        bounds: Rect.fromLTWH(0, 0, 816, 396),
        scale: _kPreferredExportScale,
        outputWidth: 1920,
        outputHeight: 1080,
      );
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final node in workflow.nodes) {
      final size = _nodeSize(node);
      left = math.min(left, node.x);
      top = math.min(top, node.y);
      right = math.max(right, node.x + size.width);
      bottom = math.max(bottom, node.y + size.height);
    }
    for (final annotation in workflow.annotations) {
      left = math.min(left, annotation.x);
      top = math.min(top, annotation.y);
      right = math.max(right, annotation.x + annotation.width);
      bottom = math.max(bottom, annotation.y + annotation.height);
    }
    final contentWidth = right - left;
    final contentHeight = bottom - top;
    if (!contentWidth.isFinite ||
        !contentHeight.isFinite ||
        contentWidth > _kMaxLogicalSpan ||
        contentHeight > _kMaxLogicalSpan) {
      throw const WorkflowPortabilityException('工作流画布范围过大，无法安全导出。');
    }
    final logicalWidth = math.max(360, contentWidth + _kExportPadding * 2);
    final logicalHeight = math.max(240, contentHeight + _kExportPadding * 2);
    var scale = math.min(
      _kPreferredExportScale,
      math.min(_kMaxRasterSide / logicalWidth, _kMaxRasterSide / logicalHeight),
    );
    final pixels = logicalWidth * logicalHeight * scale * scale;
    if (pixels > _kMaxRasterPixels) {
      scale *= math.sqrt(_kMaxRasterPixels / pixels);
    }
    final outputWidth = math.max(1, (logicalWidth * scale).ceil());
    final outputHeight = math.max(1, (logicalHeight * scale).ceil());
    return _WorkflowExportLayout(
      bounds: Rect.fromLTRB(left, top, right, bottom),
      scale: scale,
      outputWidth: outputWidth,
      outputHeight: outputHeight,
    );
  }

  final Rect bounds;
  final double scale;
  final int outputWidth;
  final int outputHeight;

  Offset position(Offset source) => Offset(
    (source.dx - bounds.left + _kExportPadding) * scale,
    (source.dy - bounds.top + _kExportPadding) * scale,
  );
}

Size _nodeSize(WorkflowNode node) {
  if (!node.isContainer) return const Size(_kNodeWidth, _kNodeHeight);
  double safeExtent(String key, double fallback) {
    final value = node.doubleSetting(key, fallback);
    return value.isFinite ? value.clamp(fallback, 4096).toDouble() : fallback;
  }

  return Size(
    safeExtent(WorkflowSettingKeys.containerWidth, _kNodeWidth),
    safeExtent(WorkflowSettingKeys.containerHeight, _kNodeHeight),
  );
}

typedef _ConnectionGeometry = ({
  Offset start,
  Offset end,
  Offset control1,
  Offset control2,
});

_ConnectionGeometry _connectionGeometry(
  WorkflowNode source,
  WorkflowNode target,
  _WorkflowExportLayout layout,
) {
  final sourceSize = _nodeSize(source);
  final targetSize = _nodeSize(target);
  final start = layout.position(
    Offset(source.x + sourceSize.width, source.y + sourceSize.height / 2),
  );
  final end = layout.position(
    Offset(target.x, target.y + targetSize.height / 2),
  );
  final distance = math.max(
    48 * layout.scale,
    (end.dx - start.dx).abs() * 0.46,
  );
  final delta = end - start;
  final magnitude = math.sqrt(delta.dx * delta.dx + delta.dy * delta.dy);
  final direction = magnitude > 0.0001
      ? Offset(delta.dx / magnitude, delta.dy / magnitude)
      : const Offset(1, 0);
  return (
    start: start,
    end: end,
    control1: Offset(start.dx + distance, start.dy),
    control2: end - direction * distance,
  );
}

Path _connectionPath(_ConnectionGeometry geometry) {
  return Path()
    ..moveTo(geometry.start.dx, geometry.start.dy)
    ..cubicTo(
      geometry.control1.dx,
      geometry.control1.dy,
      geometry.control2.dx,
      geometry.control2.dy,
      geometry.end.dx,
      geometry.end.dy,
    );
}

({Offset left, Offset right}) _connectionArrowBase(
  Offset end,
  Offset control2,
  double length,
  double halfWidth,
) {
  final tangent = end - control2;
  final magnitude = math.sqrt(
    tangent.dx * tangent.dx + tangent.dy * tangent.dy,
  );
  final direction = magnitude > 0.0001
      ? Offset(tangent.dx / magnitude, tangent.dy / magnitude)
      : const Offset(1, 0);
  final perpendicular = Offset(-direction.dy, direction.dx);
  final baseCenter = end - direction * length;
  return (
    left: baseCenter + perpendicular * halfWidth,
    right: baseCenter - perpendicular * halfWidth,
  );
}

/// 导出图使用默认主题 seed，保证与编辑器语义色一致且不依赖运行时 Theme。
final ColorScheme kWorkflowExportColorScheme = ColorScheme.fromSeed(
  seedColor: OpenHandThemePreset.duskMountainGreen.seedColor,
  dynamicSchemeVariant: DynamicSchemeVariant.expressive,
  contrastLevel: 0.12,
);

class _WorkflowExportNodeContent {
  const _WorkflowExportNodeContent({
    required this.typeLabel,
    required this.title,
    required this.summary,
    required this.accent,
    required this.icon,
    required this.controlFlow,
  });

  final String typeLabel;
  final String title;
  final String summary;
  final Color accent;
  final IconData icon;
  final bool controlFlow;
}

_WorkflowExportNodeContent _nodeContent(WorkflowNode node, ColorScheme colors) {
  final descriptor = workflowNodeDescriptor(node.kind, colors);
  final title = node.title.trim();
  return _WorkflowExportNodeContent(
    typeLabel: descriptor.label,
    title: title.isEmpty ? descriptor.label : title,
    summary: workflowNodeSummary(node),
    accent: descriptor.color,
    icon: descriptor.icon,
    controlFlow: isWorkflowControlFlowKind(node.kind),
  );
}

({Color accent, Color soft}) _annotationStyle(WorkflowAnnotationTheme theme) =>
    (accent: Color(theme.accentColorValue), soft: Color(theme.softColorValue));

Future<ui.Image> _renderRaster(
  WorkflowDefinition workflow,
  _WorkflowExportLayout layout,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final colors = kWorkflowExportColorScheme;
  final surface = Rect.fromLTWH(
    0,
    0,
    layout.outputWidth.toDouble(),
    layout.outputHeight.toDouble(),
  );
  _paintExportBackground(canvas, surface, layout.scale, colors);
  if (workflow.nodes.isEmpty && workflow.annotations.isEmpty) {
    final scale = layout.scale;
    _paintText(
      canvas,
      '空工作流',
      Offset(72 * scale, 72 * scale),
      maxWidth: surface.width - 144 * scale,
      style: TextStyle(
        color: colors.onSurface,
        fontSize: 34 * scale,
        fontWeight: FontWeight.w800,
      ),
    );
    _paintText(
      canvas,
      workflow.name,
      Offset(72 * scale, 126 * scale),
      maxWidth: surface.width - 144 * scale,
      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 20 * scale),
    );
    return _pictureToImage(
      recorder.endRecording(),
      layout.outputWidth,
      layout.outputHeight,
    );
  }

  for (final annotation in workflow.annotations) {
    final origin = layout.position(Offset(annotation.x, annotation.y));
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      annotation.width * layout.scale,
      annotation.height * layout.scale,
    );
    final style = _annotationStyle(annotation.theme);
    final radius = Radius.circular(14 * layout.scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = style.soft,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = style.accent.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * layout.scale,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 12 * layout.scale),
      Paint()..color = style.accent.withValues(alpha: 0.24),
    );
    canvas.restore();
    _paintText(
      canvas,
      annotation.text.trim().isEmpty ? '工作流注释' : annotation.text.trim(),
      Offset(rect.left + 18 * layout.scale, rect.top + 28 * layout.scale),
      maxWidth: rect.width - 36 * layout.scale,
      maxLines: math.max(
        1,
        ((annotation.height - 48) / math.max(1, annotation.fontSize * 1.4))
            .floor(),
      ),
      style: TextStyle(
        color: colors.onSurface,
        fontSize: annotation.fontSize * layout.scale,
        fontWeight: annotation.bold ? FontWeight.w800 : FontWeight.w500,
        fontStyle: annotation.italic ? FontStyle.italic : FontStyle.normal,
        decoration: annotation.strikethrough
            ? TextDecoration.lineThrough
            : TextDecoration.none,
        height: 1.4,
      ),
    );
  }

  final nodesById = <String, WorkflowNode>{
    for (final node in workflow.nodes) node.id: node,
  };
  final connectionColor = colors.primary;
  final haloPaint = Paint()
    ..color = colors.outline.withValues(alpha: 0.16)
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kConnectionHalo * layout.scale
    ..strokeCap = StrokeCap.round;
  final linePaint = Paint()
    ..color = connectionColor.withValues(alpha: 0.72)
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kConnectionStroke * layout.scale
    ..strokeCap = StrokeCap.round;
  for (final connection in workflow.connections) {
    final source = nodesById[connection.sourceNodeId];
    final target = nodesById[connection.targetNodeId];
    if (source == null || target == null) continue;
    final geometry = _connectionGeometry(source, target, layout);
    final path = _connectionPath(geometry);
    canvas.drawPath(path, haloPaint);
    canvas.drawPath(path, linePaint);
    final arrowBase = _connectionArrowBase(
      geometry.end,
      geometry.control2,
      10 * layout.scale,
      6 * layout.scale,
    );
    final arrow = Path()
      ..moveTo(geometry.end.dx, geometry.end.dy)
      ..lineTo(arrowBase.left.dx, arrowBase.left.dy)
      ..lineTo(arrowBase.right.dx, arrowBase.right.dy)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()..color = connectionColor.withValues(alpha: 0.88),
    );
  }

  for (final node in workflow.nodes) {
    _paintExportNode(canvas, node, layout, colors);
  }
  return _pictureToImage(
    recorder.endRecording(),
    layout.outputWidth,
    layout.outputHeight,
  );
}

void _paintExportBackground(
  Canvas canvas,
  Rect surface,
  double scale,
  ColorScheme colors,
) {
  canvas.drawRect(surface, Paint()..color = colors.surface);
  final minorPaint = Paint()
    ..color = colors.outlineVariant.withValues(alpha: 0.46);
  final majorPaint = Paint()..color = colors.outline.withValues(alpha: 0.35);
  final minor = _kGridSpacing * scale;
  final majorStep = math.max(1, (_kGridMajorSpacing / _kGridSpacing).round());
  for (var column = 0; ; column++) {
    final x = column * minor;
    if (x > surface.width) break;
    for (var row = 0; ; row++) {
      final y = row * minor;
      if (y > surface.height) break;
      final isMajor = column % majorStep == 0 && row % majorStep == 0;
      canvas.drawCircle(
        Offset(x, y),
        (isMajor ? _kGridMajorDotRadius : _kGridDotRadius) * scale,
        isMajor ? majorPaint : minorPaint,
      );
    }
  }
}

void _paintExportNode(
  Canvas canvas,
  WorkflowNode node,
  _WorkflowExportLayout layout,
  ColorScheme colors,
) {
  final size = _nodeSize(node);
  final scale = layout.scale;
  final origin = layout.position(Offset(node.x, node.y));
  final rect = Rect.fromLTWH(
    origin.dx,
    origin.dy,
    size.width * scale,
    size.height * scale,
  );
  final content = _nodeContent(node, colors);
  final fill = content.controlFlow
      ? Color.alphaBlend(
          content.accent.withValues(alpha: 0.07),
          colors.surfaceContainerHigh,
        )
      : colors.surfaceContainerHigh;
  final border = content.controlFlow
      ? content.accent.withValues(alpha: 0.42)
      : colors.outlineVariant;
  final radius = Radius.circular(_kNodeCornerRadius * scale);
  final shape = RRect.fromRectAndRadius(rect, radius);
  canvas.drawShadow(
    Path()..addRRect(shape),
    colors.shadow.withValues(alpha: 0.55),
    10 * scale,
    false,
  );
  canvas.drawRRect(shape, Paint()..color = fill);
  canvas.drawRRect(
    shape,
    Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * scale,
  );

  final padding = _kNodePadding * scale;
  final iconSize = _kNodeIconSize * scale;
  final iconRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(rect.left + padding, rect.top + padding, iconSize, iconSize),
    Radius.circular(_kNodeIconRadius * scale),
  );
  canvas.drawRRect(
    iconRect,
    Paint()..color = content.accent.withValues(alpha: 0.15),
  );
  _paintIcon(
    canvas,
    content.icon,
    iconRect.outerRect.center,
    19 * scale,
    content.accent,
  );

  final titleLeft = rect.left + padding + iconSize + 9 * scale;
  _paintText(
    canvas,
    content.title,
    Offset(titleLeft, rect.top + padding + 7 * scale),
    maxWidth: rect.right - padding - titleLeft,
    style: TextStyle(
      color: colors.onSurface,
      fontSize: 14 * scale,
      fontWeight: FontWeight.w900,
      height: 1.2,
    ),
  );

  final summaryTop = rect.top + padding + iconSize + 12 * scale;
  _paintText(
    canvas,
    content.summary,
    Offset(rect.left + padding, summaryTop),
    maxWidth: rect.width - padding * 2,
    maxLines: 2,
    style: TextStyle(
      color: colors.onSurfaceVariant,
      fontSize: 12 * scale,
      height: 1.4,
      fontWeight: FontWeight.w500,
    ),
  );

  final labelPainter = TextPainter(
    text: TextSpan(
      text: content.typeLabel,
      style: TextStyle(
        color: content.accent,
        fontSize: 11 * scale,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: rect.width * 0.55);
  final showOutPort = !isWorkflowTerminalNodeKind(node.kind);
  final portRadius = _kNodePortRadius * scale;
  final labelBottom = rect.bottom - padding - 2 * scale;
  final labelRight = showOutPort
      ? rect.right - padding - portRadius * 2 - 6 * scale
      : rect.right - padding;
  labelPainter.paint(
    canvas,
    Offset(labelRight - labelPainter.width, labelBottom - labelPainter.height),
  );
  if (showOutPort) {
    canvas.drawCircle(
      Offset(rect.right - padding / 2, rect.center.dy),
      portRadius,
      Paint()..color = content.accent,
    );
  }
  if (node.kind != WorkflowNodeKind.start) {
    canvas.drawCircle(
      Offset(rect.left, rect.center.dy),
      portRadius,
      Paint()
        ..color = colors.outline
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(rect.left, rect.center.dy),
      portRadius,
      Paint()
        ..color = colors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale,
    );
  }
}

Future<ui.Image> _pictureToImage(
  ui.Picture picture,
  int width,
  int height,
) async {
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

void _paintIcon(
  Canvas canvas,
  IconData icon,
  Offset center,
  double size,
  Color color,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
  );
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset, {
  required double maxWidth,
  required TextStyle style,
  int maxLines = 1,
  TextAlign textAlign = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: textAlign,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: math.max(1, maxWidth));
  painter.paint(canvas, offset);
}

String _renderSvg(WorkflowDefinition workflow, _WorkflowExportLayout layout) {
  final colors = kWorkflowExportColorScheme;
  final scale = layout.scale;
  final gridSpacing = _kGridSpacing * scale;
  final majorSpacing = _kGridMajorSpacing * scale;
  final surfaceHex = _colorHex(colors.surface);
  final onSurfaceHex = _colorHex(colors.onSurface);
  final onVariantHex = _colorHex(colors.onSurfaceVariant);
  final outlineHex = _colorHex(colors.outline);
  final outlineVariantHex = _colorHex(colors.outlineVariant);
  final primaryHex = _colorHex(colors.primary);
  final surfaceHighHex = _colorHex(colors.surfaceContainerHigh);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${layout.outputWidth}" '
      'height="${layout.outputHeight}" viewBox="0 0 ${layout.outputWidth} ${layout.outputHeight}">',
    )
    ..writeln('<rect width="100%" height="100%" fill="$surfaceHex"/>')
    ..writeln(
      '<defs>'
      '<pattern id="grid-minor" width="$gridSpacing" height="$gridSpacing" '
      'patternUnits="userSpaceOnUse">'
      '<circle cx="$scale" cy="$scale" r="${_kGridDotRadius * scale}" '
      'fill="$outlineVariantHex" fill-opacity="0.46"/>'
      '</pattern>'
      '<pattern id="grid-major" width="$majorSpacing" height="$majorSpacing" '
      'patternUnits="userSpaceOnUse">'
      '<circle cx="$scale" cy="$scale" r="${_kGridMajorDotRadius * scale}" '
      'fill="$outlineHex" fill-opacity="0.35"/>'
      '</pattern>'
      '</defs>',
    )
    ..writeln('<rect width="100%" height="100%" fill="url(#grid-minor)"/>')
    ..writeln('<rect width="100%" height="100%" fill="url(#grid-major)"/>');
  if (workflow.nodes.isEmpty && workflow.annotations.isEmpty) {
    buffer
      ..writeln(
        '<text x="${72 * scale}" y="${105 * scale}" font-family="sans-serif" '
        'font-size="${34 * scale}" '
        'font-weight="800" fill="$onSurfaceHex">空工作流</text>',
      )
      ..writeln(
        '<text x="${72 * scale}" y="${150 * scale}" font-family="sans-serif" '
        'font-size="${20 * scale}" '
        'fill="$onVariantHex">${_escapeXml(workflow.name)}</text>',
      )
      ..writeln('</svg>');
    return buffer.toString();
  }
  for (final annotation in workflow.annotations) {
    final origin = layout.position(Offset(annotation.x, annotation.y));
    final width = annotation.width * scale;
    final height = annotation.height * scale;
    final style = _annotationStyle(annotation.theme);
    final accent = _colorHex(style.accent);
    final soft = _colorHex(style.soft);
    final fontSize = annotation.fontSize * scale;
    final lines = _annotationSvgLines(annotation);
    buffer
      ..writeln(
        '<rect x="${origin.dx}" y="${origin.dy}" width="$width" height="$height" '
        'rx="${14 * scale}" fill="$soft" stroke="$accent" stroke-opacity="0.42" '
        'stroke-width="${1.2 * scale}"/>',
      )
      ..writeln(
        '<rect x="${origin.dx}" y="${origin.dy}" width="$width" '
        'height="${12 * scale}" rx="${8 * scale}" '
        'fill="$accent" fill-opacity="0.24"/>',
      )
      ..writeln(
        '<text x="${origin.dx + 18 * scale}" '
        'y="${origin.dy + 30 * scale}" font-family="sans-serif" '
        'font-size="$fontSize" font-weight="${annotation.bold ? 800 : 500}" '
        'font-style="${annotation.italic ? 'italic' : 'normal'}" '
        'text-decoration="${annotation.strikethrough ? 'line-through' : 'none'}" '
        'fill="$onSurfaceHex">',
      );
    for (final line in lines.indexed) {
      buffer.writeln(
        '<tspan x="${origin.dx + 18 * scale}" '
        'dy="${line.$1 == 0 ? 0 : fontSize * 1.4}">'
        '${_escapeXml(line.$2)}</tspan>',
      );
    }
    buffer.writeln('</text>');
  }
  final nodesById = <String, WorkflowNode>{
    for (final node in workflow.nodes) node.id: node,
  };
  for (final connection in workflow.connections) {
    final source = nodesById[connection.sourceNodeId];
    final target = nodesById[connection.targetNodeId];
    if (source == null || target == null) continue;
    final geometry = _connectionGeometry(source, target, layout);
    final path =
        'M ${geometry.start.dx.toStringAsFixed(2)} ${geometry.start.dy.toStringAsFixed(2)} '
        'C ${geometry.control1.dx.toStringAsFixed(2)} ${geometry.control1.dy.toStringAsFixed(2)}, '
        '${geometry.control2.dx.toStringAsFixed(2)} ${geometry.control2.dy.toStringAsFixed(2)}, '
        '${geometry.end.dx.toStringAsFixed(2)} ${geometry.end.dy.toStringAsFixed(2)}';
    final arrowBase = _connectionArrowBase(
      geometry.end,
      geometry.control2,
      10 * scale,
      6 * scale,
    );
    buffer
      ..writeln(
        '<path d="$path" fill="none" stroke="$outlineHex" stroke-opacity="0.16" '
        'stroke-width="${(_kConnectionHalo * scale).toStringAsFixed(2)}" stroke-linecap="round"/>',
      )
      ..writeln(
        '<path d="$path" fill="none" stroke="$primaryHex" stroke-opacity="0.72" '
        'stroke-width="${(_kConnectionStroke * scale).toStringAsFixed(2)}" stroke-linecap="round"/>',
      )
      ..writeln(
        '<path d="M ${geometry.end.dx} ${geometry.end.dy} L ${arrowBase.left.dx} '
        '${arrowBase.left.dy} L ${arrowBase.right.dx} '
        '${arrowBase.right.dy} Z" fill="$primaryHex" fill-opacity="0.88"/>',
      );
  }
  for (final node in workflow.nodes) {
    _appendExportNodeSvg(buffer, node, layout, colors, surfaceHighHex);
  }
  buffer.writeln('</svg>');
  return buffer.toString();
}

void _appendExportNodeSvg(
  StringBuffer buffer,
  WorkflowNode node,
  _WorkflowExportLayout layout,
  ColorScheme colors,
  String surfaceHighHex,
) {
  final scale = layout.scale;
  final origin = layout.position(Offset(node.x, node.y));
  final size = _nodeSize(node);
  final width = size.width * scale;
  final height = size.height * scale;
  final content = _nodeContent(node, colors);
  final accent = _colorHex(content.accent);
  final fill = content.controlFlow
      ? _colorHex(
          Color.alphaBlend(
            content.accent.withValues(alpha: 0.07),
            colors.surfaceContainerHigh,
          ),
        )
      : surfaceHighHex;
  final borderHex = content.controlFlow
      ? accent
      : _colorHex(colors.outlineVariant);
  final borderOpacity = content.controlFlow ? 0.42 : 1.0;
  final padding = _kNodePadding * scale;
  final iconSize = _kNodeIconSize * scale;
  final title = _clipSvgText(content.title);
  final summary = _clipSvgText(content.summary, maxChars: 36);
  final showOutPort = !isWorkflowTerminalNodeKind(node.kind);
  final portRadius = _kNodePortRadius * scale;
  buffer
    ..writeln(
      '<rect x="${origin.dx + 1 * scale}" y="${origin.dy + 7 * scale}" '
      'width="$width" height="$height" rx="${_kNodeCornerRadius * scale}" '
      'fill="${_colorHex(colors.shadow)}" fill-opacity="0.08"/>',
    )
    ..writeln(
      '<rect x="${origin.dx}" y="${origin.dy}" width="$width" height="$height" '
      'rx="${_kNodeCornerRadius * scale}" fill="$fill" stroke="$borderHex" '
      'stroke-opacity="$borderOpacity" stroke-width="${1 * scale}"/>',
    )
    ..writeln(
      '<rect x="${origin.dx + padding}" y="${origin.dy + padding}" '
      'width="$iconSize" height="$iconSize" rx="${_kNodeIconRadius * scale}" '
      'fill="$accent" fill-opacity="0.15"/>',
    )
    ..writeln(
      '<text x="${origin.dx + padding + iconSize / 2}" '
      'y="${origin.dy + padding + iconSize * 0.68}" text-anchor="middle" '
      'font-family="sans-serif" font-size="${13 * scale}" font-weight="800" '
      'fill="$accent">${_escapeXml(_exportIconGlyph(node.kind))}</text>',
    )
    ..writeln(
      '<text x="${origin.dx + padding + iconSize + 9 * scale}" '
      'y="${origin.dy + padding + 22 * scale}" font-family="sans-serif" '
      'font-size="${14 * scale}" font-weight="900" fill="${_colorHex(colors.onSurface)}">'
      '${_escapeXml(title)}</text>',
    )
    ..writeln(
      '<text x="${origin.dx + padding}" '
      'y="${origin.dy + padding + iconSize + 24 * scale}" font-family="sans-serif" '
      'font-size="${12 * scale}" fill="${_colorHex(colors.onSurfaceVariant)}">'
      '${_escapeXml(summary)}</text>',
    )
    ..writeln(
      '<text x="${origin.dx + width - padding - (showOutPort ? portRadius * 2 + 6 * scale : 0)}" '
      'y="${origin.dy + height - padding - 2 * scale}" text-anchor="end" '
      'font-family="sans-serif" font-size="${11 * scale}" font-weight="800" fill="$accent">'
      '${_escapeXml(content.typeLabel)}</text>',
    );
  if (showOutPort) {
    buffer.writeln(
      '<circle cx="${origin.dx + width - padding / 2}" cy="${origin.dy + height / 2}" '
      'r="$portRadius" fill="$accent"/>',
    );
  }
  if (node.kind != WorkflowNodeKind.start) {
    buffer
      ..writeln(
        '<circle cx="${origin.dx}" cy="${origin.dy + height / 2}" '
        'r="$portRadius" fill="${_colorHex(colors.outline)}"/>',
      )
      ..writeln(
        '<circle cx="${origin.dx}" cy="${origin.dy + height / 2}" '
        'r="$portRadius" fill="none" stroke="${_colorHex(colors.surface)}" '
        'stroke-width="${1.5 * scale}"/>',
      );
  }
}

String _exportIconGlyph(WorkflowNodeKind kind) => switch (kind) {
  WorkflowNodeKind.start => '▶',
  WorkflowNodeKind.end => '■',
  WorkflowNodeKind.codeExecution => '{}',
  WorkflowNodeKind.condition => '⑂',
  WorkflowNodeKind.loop || WorkflowNodeKind.iteration => '↻',
  WorkflowNodeKind.llm => '✦',
  WorkflowNodeKind.httpRequest => '◎',
  WorkflowNodeKind.humanIntervention => '◆',
  WorkflowNodeKind.loopExit => '↩',
  WorkflowNodeKind.parameterAssignment => '≡',
  WorkflowNodeKind.listOperation => '☰',
};

String _clipSvgText(String text, {int maxChars = 24}) {
  final characters = text.runes.toList(growable: false);
  if (characters.length <= maxChars) return text;
  return '${String.fromCharCodes(characters.take(maxChars - 1))}…';
}

List<String> _annotationSvgLines(WorkflowAnnotation annotation) {
  final source = annotation.text.trim().isEmpty
      ? '工作流注释'
      : annotation.text.trim();
  final charactersPerLine = math.max(
    4,
    (annotation.width / math.max(1, annotation.fontSize * 0.9)).floor(),
  );
  final maxLines = math.max(
    1,
    ((annotation.height - 48) / math.max(1, annotation.fontSize * 1.4)).floor(),
  );
  final lines = <String>[];
  for (final paragraph in source.split('\n')) {
    final runes = paragraph.runes.toList(growable: false);
    if (runes.isEmpty) {
      lines.add('');
      continue;
    }
    for (var offset = 0; offset < runes.length; offset += charactersPerLine) {
      lines.add(
        String.fromCharCodes(runes.skip(offset).take(charactersPerLine)),
      );
    }
  }
  if (lines.length <= maxLines) return lines;
  final visible = lines.take(maxLines).toList(growable: true);
  final last = visible.last.runes.toList(growable: false);
  visible[visible.length - 1] =
      '${String.fromCharCodes(last.take(math.max(1, last.length - 1)))}…';
  return visible;
}

final RegExp _xmlIllegalControlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

String _escapeXml(String value) =>
    escapeXmlAttribute(value.replaceAll(_xmlIllegalControlChars, ''));

String _colorHex(Color color) =>
    '#${rgbHexFromArgb32(color.toARGB32()).toUpperCase()}';
