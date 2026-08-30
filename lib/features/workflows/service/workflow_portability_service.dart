import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:yaml/yaml.dart';

import '../model/workflow_definition.dart';

const int kMaxWorkflowImportBytes = 4 * 1024 * 1024;
const int _kMaxWorkflowNodes = 1000;
const int _kMaxWorkflowConnections = 5000;
const int _kMaxWorkflowAnnotations = 500;
const int _kMaxYamlDepth = 64;
const int _kMaxYamlValues = 100000;
const double _kNodeWidth = 246;
const double _kNodeHeight = 130;
const double _kExportPadding = 72;
const double _kGridSpacing = 24;
const double _kGridDotRadius = 0.8;

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
  if (nodes is List && nodes.length > _kMaxWorkflowNodes) {
    throw const WorkflowPortabilityException(
      '工作流节点数量超过 $_kMaxWorkflowNodes 个安全上限。',
    );
  }
  if (connections is List && connections.length > _kMaxWorkflowConnections) {
    throw const WorkflowPortabilityException(
      '工作流连线数量超过 $_kMaxWorkflowConnections 条安全上限。',
    );
  }
  if (annotations is List && annotations.length > _kMaxWorkflowAnnotations) {
    throw const WorkflowPortabilityException(
      '工作流注释数量超过 $_kMaxWorkflowAnnotations 个安全上限。',
    );
  }
  try {
    final definition = WorkflowDefinition.fromJson(workflow);
    if (nodes is List && definition.nodes.length != nodes.length) {
      throw const WorkflowPortabilityException('工作流包含无法识别的节点数据。');
    }
    if (connections is List &&
        definition.connections.length != connections.length) {
      throw const WorkflowPortabilityException('工作流包含无效或断开的连线。');
    }
    if (annotations is List &&
        definition.annotations.length != annotations.length) {
      throw const WorkflowPortabilityException('工作流包含无法识别的注释数据。');
    }
    if (definition.name.runes.length > 120) {
      throw const WorkflowPortabilityException('工作流名称不能超过 120 个字符。');
    }
    if (utf8.encode(definition.encode()).length > kMaxWorkflowImportBytes) {
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
  if (workflow.nodes.length > _kMaxWorkflowNodes ||
      workflow.connections.length > _kMaxWorkflowConnections ||
      workflow.annotations.length > _kMaxWorkflowAnnotations) {
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
    var scale = math
        .min(
          _kPreferredExportScale,
          math.min(
            _kMaxRasterSide / logicalWidth,
            _kMaxRasterSide / logicalHeight,
          ),
        )
        .toDouble();
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

({Offset control1, Offset control2}) _connectionControls(
  Offset start,
  Offset end, {
  double minimumDistance = 48,
}) {
  final distance = math
      .max(minimumDistance, (end.dx - start.dx).abs() * 0.46)
      .toDouble();
  final delta = end - start;
  final magnitude = math.sqrt(delta.dx * delta.dx + delta.dy * delta.dy);
  final direction = magnitude > 0.0001
      ? Offset(delta.dx / magnitude, delta.dy / magnitude)
      : const Offset(1, 0);
  return (
    control1: Offset(start.dx + distance, start.dy),
    control2: end - direction * distance,
  );
}

Path _connectionPath(Offset start, Offset end, {double minimumDistance = 48}) {
  final controls = _connectionControls(
    start,
    end,
    minimumDistance: minimumDistance,
  );
  return Path()
    ..moveTo(start.dx, start.dy)
    ..cubicTo(
      controls.control1.dx,
      controls.control1.dy,
      controls.control2.dx,
      controls.control2.dy,
      end.dx,
      end.dy,
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

({Color accent, Color soft, String shortLabel}) _nodeStyle(
  WorkflowNodeKind kind,
) => switch (kind) {
  WorkflowNodeKind.start => (
    accent: const Color(0xFF2E7D32),
    soft: const Color(0xFFE4F3E5),
    shortLabel: 'START',
  ),
  WorkflowNodeKind.condition => (
    accent: const Color(0xFF1565C0),
    soft: const Color(0xFFE1EEFC),
    shortLabel: 'IF',
  ),
  WorkflowNodeKind.loop || WorkflowNodeKind.iteration => (
    accent: const Color(0xFF6A1B9A),
    soft: const Color(0xFFF0E4F6),
    shortLabel: 'LOOP',
  ),
  WorkflowNodeKind.parameterAssignment || WorkflowNodeKind.listOperation => (
    accent: const Color(0xFF00695C),
    soft: const Color(0xFFDFF1EE),
    shortLabel: 'DATA',
  ),
  WorkflowNodeKind.codeExecution => (
    accent: const Color(0xFFEF6C00),
    soft: const Color(0xFFFFEBD9),
    shortLabel: 'CODE',
  ),
  WorkflowNodeKind.humanIntervention => (
    accent: const Color(0xFF00838F),
    soft: const Color(0xFFDDF3F5),
    shortLabel: 'HUMAN',
  ),
  WorkflowNodeKind.loopExit => (
    accent: const Color(0xFF5D4037),
    soft: const Color(0xFFEDE6E3),
    shortLabel: 'EXIT',
  ),
  WorkflowNodeKind.llm => (
    accent: const Color(0xFFC2185B),
    soft: const Color(0xFFF8E1EA),
    shortLabel: 'LLM',
  ),
  WorkflowNodeKind.httpRequest => (
    accent: const Color(0xFF0277BD),
    soft: const Color(0xFFDFF0FA),
    shortLabel: 'HTTP',
  ),
  WorkflowNodeKind.end => (
    accent: const Color(0xFFC62828),
    soft: const Color(0xFFF8E2E2),
    shortLabel: 'END',
  ),
};

({Color accent, Color soft}) _annotationStyle(WorkflowAnnotationTheme theme) =>
    (accent: Color(theme.accentColorValue), soft: Color(theme.softColorValue));

Future<ui.Image> _renderRaster(
  WorkflowDefinition workflow,
  _WorkflowExportLayout layout,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final surface = Rect.fromLTWH(
    0,
    0,
    layout.outputWidth.toDouble(),
    layout.outputHeight.toDouble(),
  );
  canvas.drawRect(surface, Paint()..color = const Color(0xFFF7F8FC));
  final gridPaint = Paint()..color = const Color(0xFFDDE1EA);
  final gridSpacing = _kGridSpacing * layout.scale;
  for (var x = gridSpacing; x < surface.width; x += gridSpacing) {
    for (var y = gridSpacing; y < surface.height; y += gridSpacing) {
      canvas.drawCircle(
        Offset(x, y),
        _kGridDotRadius * layout.scale,
        gridPaint,
      );
    }
  }
  if (workflow.nodes.isEmpty && workflow.annotations.isEmpty) {
    final scale = layout.scale;
    _paintText(
      canvas,
      '空工作流',
      Offset(72 * scale, 72 * scale),
      maxWidth: surface.width - 144 * scale,
      style: TextStyle(
        color: const Color(0xFF20242C),
        fontSize: 34 * scale,
        fontWeight: FontWeight.w800,
      ),
    );
    _paintText(
      canvas,
      workflow.name,
      Offset(72 * scale, 126 * scale),
      maxWidth: surface.width - 144 * scale,
      style: TextStyle(color: const Color(0xFF667085), fontSize: 20 * scale),
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
        color: const Color(0xFF20242C),
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
  final linePaint = Paint()
    ..color = const Color(0xFF667085)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4 * layout.scale
    ..strokeCap = StrokeCap.round;
  for (final connection in workflow.connections) {
    final source = nodesById[connection.sourceNodeId];
    final target = nodesById[connection.targetNodeId];
    if (source == null || target == null) continue;
    final sourceSize = _nodeSize(source);
    final targetSize = _nodeSize(target);
    final start = layout.position(
      Offset(source.x + sourceSize.width, source.y + sourceSize.height / 2),
    );
    final end = layout.position(
      Offset(target.x, target.y + targetSize.height / 2),
    );
    final minimumDistance = 48 * layout.scale;
    final path = _connectionPath(start, end, minimumDistance: minimumDistance);
    canvas.drawPath(path, linePaint);
    final controls = _connectionControls(
      start,
      end,
      minimumDistance: minimumDistance,
    );
    final arrowBase = _connectionArrowBase(
      end,
      controls.control2,
      10 * layout.scale,
      6 * layout.scale,
    );
    final arrow = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(arrowBase.left.dx, arrowBase.left.dy)
      ..lineTo(arrowBase.right.dx, arrowBase.right.dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFF667085));
  }

  for (final node in workflow.nodes) {
    final size = _nodeSize(node);
    final origin = layout.position(Offset(node.x, node.y));
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      size.width * layout.scale,
      size.height * layout.scale,
    );
    final style = _nodeStyle(node.kind);
    final radius = Radius.circular(18 * layout.scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = style.accent.withValues(alpha: 0.36)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * layout.scale,
    );
    final badgeRect = Rect.fromLTWH(
      rect.left + 16 * layout.scale,
      rect.top + 16 * layout.scale,
      58 * layout.scale,
      34 * layout.scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(10 * layout.scale)),
      Paint()..color = style.soft,
    );
    _paintText(
      canvas,
      style.shortLabel,
      Offset(
        badgeRect.left + 10 * layout.scale,
        badgeRect.top + 8 * layout.scale,
      ),
      maxWidth: badgeRect.width - 20 * layout.scale,
      style: TextStyle(
        color: style.accent,
        fontSize: 11 * layout.scale,
        fontWeight: FontWeight.w800,
      ),
    );
    _paintText(
      canvas,
      node.title.trim().isEmpty ? node.kind.storageValue : node.title.trim(),
      Offset(rect.left + 16 * layout.scale, rect.top + 64 * layout.scale),
      maxWidth: rect.width - 32 * layout.scale,
      style: TextStyle(
        color: const Color(0xFF20242C),
        fontSize: 18 * layout.scale,
        fontWeight: FontWeight.w700,
      ),
    );
    _paintText(
      canvas,
      node.kind.storageValue,
      Offset(rect.left + 16 * layout.scale, rect.top + 94 * layout.scale),
      maxWidth: rect.width - 32 * layout.scale,
      style: TextStyle(
        color: const Color(0xFF667085),
        fontSize: 12 * layout.scale,
      ),
    );
  }
  return _pictureToImage(
    recorder.endRecording(),
    layout.outputWidth,
    layout.outputHeight,
  );
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

void _paintText(
  Canvas canvas,
  String text,
  Offset offset, {
  required double maxWidth,
  required TextStyle style,
  int maxLines = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: math.max(1, maxWidth));
  painter.paint(canvas, offset);
}

String _renderSvg(WorkflowDefinition workflow, _WorkflowExportLayout layout) {
  final gridSpacing = _kGridSpacing * layout.scale;
  final gridDotRadius = _kGridDotRadius * layout.scale;
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${layout.outputWidth}" '
      'height="${layout.outputHeight}" viewBox="0 0 ${layout.outputWidth} ${layout.outputHeight}">',
    )
    ..writeln('<rect width="100%" height="100%" fill="#F7F8FC"/>')
    ..writeln(
      '<defs><pattern id="grid" width="$gridSpacing" height="$gridSpacing" '
      'patternUnits="userSpaceOnUse"><circle cx="${layout.scale}" cy="${layout.scale}" '
      'r="$gridDotRadius" fill="#DDE1EA"/></pattern></defs>',
    )
    ..writeln('<rect width="100%" height="100%" fill="url(#grid)"/>');
  if (workflow.nodes.isEmpty && workflow.annotations.isEmpty) {
    final scale = layout.scale;
    buffer
      ..writeln(
        '<text x="${72 * scale}" y="${105 * scale}" font-family="sans-serif" '
        'font-size="${34 * scale}" '
        'font-weight="800" fill="#20242C">空工作流</text>',
      )
      ..writeln(
        '<text x="${72 * scale}" y="${150 * scale}" font-family="sans-serif" '
        'font-size="${20 * scale}" '
        'fill="#667085">${_escapeXml(workflow.name)}</text>',
      )
      ..writeln('</svg>');
    return buffer.toString();
  }
  for (final annotation in workflow.annotations) {
    final origin = layout.position(Offset(annotation.x, annotation.y));
    final width = annotation.width * layout.scale;
    final height = annotation.height * layout.scale;
    final style = _annotationStyle(annotation.theme);
    final accent = _colorHex(style.accent);
    final soft = _colorHex(style.soft);
    final fontSize = annotation.fontSize * layout.scale;
    final lines = _annotationSvgLines(annotation);
    buffer
      ..writeln(
        '<rect x="${origin.dx}" y="${origin.dy}" width="$width" height="$height" '
        'rx="${14 * layout.scale}" fill="$soft" stroke="$accent" stroke-opacity="0.42" '
        'stroke-width="${1.2 * layout.scale}"/>',
      )
      ..writeln(
        '<rect x="${origin.dx}" y="${origin.dy}" width="$width" '
        'height="${12 * layout.scale}" rx="${8 * layout.scale}" '
        'fill="$accent" fill-opacity="0.24"/>',
      )
      ..writeln(
        '<text x="${origin.dx + 18 * layout.scale}" '
        'y="${origin.dy + 30 * layout.scale}" font-family="sans-serif" '
        'font-size="$fontSize" font-weight="${annotation.bold ? 800 : 500}" '
        'font-style="${annotation.italic ? 'italic' : 'normal'}" '
        'text-decoration="${annotation.strikethrough ? 'line-through' : 'none'}" '
        'fill="#20242C">',
      );
    for (final line in lines.indexed) {
      buffer.writeln(
        '<tspan x="${origin.dx + 18 * layout.scale}" '
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
    final sourceSize = _nodeSize(source);
    final targetSize = _nodeSize(target);
    final start = layout.position(
      Offset(source.x + sourceSize.width, source.y + sourceSize.height / 2),
    );
    final end = layout.position(
      Offset(target.x, target.y + targetSize.height / 2),
    );
    final controls = _connectionControls(
      start,
      end,
      minimumDistance: 48 * layout.scale,
    );
    final path =
        'M ${start.dx.toStringAsFixed(2)} ${start.dy.toStringAsFixed(2)} '
        'C ${controls.control1.dx.toStringAsFixed(2)} ${controls.control1.dy.toStringAsFixed(2)}, '
        '${controls.control2.dx.toStringAsFixed(2)} ${controls.control2.dy.toStringAsFixed(2)}, '
        '${end.dx.toStringAsFixed(2)} ${end.dy.toStringAsFixed(2)}';
    final arrowBase = _connectionArrowBase(
      end,
      controls.control2,
      10 * layout.scale,
      6 * layout.scale,
    );
    buffer
      ..writeln(
        '<path d="$path" fill="none" stroke="#667085" '
        'stroke-width="${(2.4 * layout.scale).toStringAsFixed(2)}" stroke-linecap="round"/>',
      )
      ..writeln(
        '<path d="M ${end.dx} ${end.dy} L ${arrowBase.left.dx} '
        '${arrowBase.left.dy} L ${arrowBase.right.dx} '
        '${arrowBase.right.dy} Z" fill="#667085"/>',
      );
  }
  for (final node in workflow.nodes) {
    final origin = layout.position(Offset(node.x, node.y));
    final size = _nodeSize(node);
    final width = size.width * layout.scale;
    final height = size.height * layout.scale;
    final style = _nodeStyle(node.kind);
    final accent = _colorHex(style.accent);
    final soft = _colorHex(style.soft);
    final title = node.title.trim().isEmpty
        ? node.kind.storageValue
        : node.title.trim();
    buffer
      ..writeln(
        '<rect x="${origin.dx}" y="${origin.dy}" width="$width" height="$height" '
        'rx="${18 * layout.scale}" fill="#FFFFFF" stroke="$accent" stroke-opacity="0.36" '
        'stroke-width="${1.4 * layout.scale}"/>',
      )
      ..writeln(
        '<rect x="${origin.dx + 16 * layout.scale}" y="${origin.dy + 16 * layout.scale}" '
        'width="${58 * layout.scale}" height="${34 * layout.scale}" rx="${10 * layout.scale}" fill="$soft"/>',
      )
      ..writeln(
        '<text x="${origin.dx + 26 * layout.scale}" y="${origin.dy + 38 * layout.scale}" '
        'font-family="sans-serif" font-size="${11 * layout.scale}" font-weight="800" fill="$accent">'
        '${style.shortLabel}</text>',
      )
      ..writeln(
        '<text x="${origin.dx + 16 * layout.scale}" y="${origin.dy + 83 * layout.scale}" '
        'font-family="sans-serif" font-size="${18 * layout.scale}" font-weight="700" fill="#20242C">'
        '${_escapeXml(_clipSvgText(title))}</text>',
      )
      ..writeln(
        '<text x="${origin.dx + 16 * layout.scale}" y="${origin.dy + 111 * layout.scale}" '
        'font-family="sans-serif" font-size="${12 * layout.scale}" fill="#667085">'
        '${_escapeXml(node.kind.storageValue)}</text>',
      );
  }
  buffer.writeln('</svg>');
  return buffer.toString();
}

String _clipSvgText(String text) {
  final characters = text.runes.toList(growable: false);
  if (characters.length <= 24) return text;
  return '${String.fromCharCodes(characters.take(23))}…';
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

String _escapeXml(String value) => value
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _colorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
