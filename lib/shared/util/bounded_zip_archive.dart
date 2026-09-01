import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'byte_size_format.dart';

final class BoundedZipArchive {
  BoundedZipArchive._(this.files, this._filesByName);

  factory BoundedZipArchive.decode(
    Uint8List bytes, {
    required int maxEntries,
    required int maxReadBytes,
  }) {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', '必须大于零。');
    }
    if (maxReadBytes < 0) {
      throw ArgumentError.value(maxReadBytes, 'maxReadBytes', '不得小于零。');
    }
    final data = ByteData.sublistView(bytes);
    final readBudget = _ZipReadBudget(maxReadBytes);
    final eocdOffset = _findEndOfCentralDirectory(bytes, data);
    if (eocdOffset < 0) {
      throw const FormatException('ZIP 缺少有效的中央目录。');
    }

    final diskNumber = _readUint16(data, eocdOffset + 4);
    final centralDirectoryDisk = _readUint16(data, eocdOffset + 6);
    final diskEntries = _readUint16(data, eocdOffset + 8);
    final totalEntries = _readUint16(data, eocdOffset + 10);
    final centralDirectorySize = _readUint32(data, eocdOffset + 12);
    final centralDirectoryOffset = _readUint32(data, eocdOffset + 16);
    if (diskNumber != 0 ||
        centralDirectoryDisk != 0 ||
        diskEntries != totalEntries) {
      throw const FormatException('不支持分卷 ZIP 归档。');
    }
    if (totalEntries == _zip64Uint16 ||
        centralDirectorySize == _zip64Uint32 ||
        centralDirectoryOffset == _zip64Uint32) {
      throw const FormatException('不支持 ZIP64 归档。');
    }
    if (totalEntries > maxEntries) {
      throw const FormatException('ZIP 条目数量超过安全上限。');
    }
    if (centralDirectoryOffset > eocdOffset ||
        centralDirectorySize != eocdOffset - centralDirectoryOffset) {
      throw const FormatException('ZIP 中央目录范围无效。');
    }

    final files = <BoundedZipEntry>[];
    final filesByName = <String, BoundedZipEntry>{};
    final occupiedRanges = <({int start, int end, String name})>[];
    var cursor = centralDirectoryOffset;
    for (var index = 0; index < totalEntries; index++) {
      _requireRange(bytes, cursor, 46, 'ZIP 中央目录条目不完整。');
      if (_readUint32(data, cursor) != _centralDirectorySignature) {
        throw const FormatException('ZIP 中央目录条目标识无效。');
      }

      final versionMadeBy = _readUint16(data, cursor + 4);
      final flags = _readUint16(data, cursor + 8);
      final compressionMethod = _readUint16(data, cursor + 10);
      final crc32 = _readUint32(data, cursor + 16);
      final compressedSize = _readUint32(data, cursor + 20);
      final uncompressedSize = _readUint32(data, cursor + 24);
      final fileNameLength = _readUint16(data, cursor + 28);
      final extraFieldLength = _readUint16(data, cursor + 30);
      final fileCommentLength = _readUint16(data, cursor + 32);
      final diskStart = _readUint16(data, cursor + 34);
      final externalAttributes = _readUint32(data, cursor + 38);
      final localHeaderOffset = _readUint32(data, cursor + 42);
      if (compressedSize == _zip64Uint32 ||
          uncompressedSize == _zip64Uint32 ||
          localHeaderOffset == _zip64Uint32 ||
          diskStart == _zip64Uint16) {
        throw const FormatException('不支持 ZIP64 条目。');
      }
      if (diskStart != 0) {
        throw const FormatException('不支持分卷 ZIP 条目。');
      }
      if (flags & _encryptedFlags != 0) {
        throw const FormatException('不支持加密 ZIP 条目。');
      }
      final unixFileType = (externalAttributes >> 16) & _unixFileTypeMask;
      if ((versionMadeBy >> 8) == 3 && unixFileType == _unixSymbolicLinkType) {
        throw const FormatException('不支持 ZIP 符号链接条目。');
      }

      final variableLength =
          fileNameLength + extraFieldLength + fileCommentLength;
      _requireRange(bytes, cursor + 46, variableLength, 'ZIP 中央目录条目不完整。');
      final fileNameBytes = Uint8List.sublistView(
        bytes,
        cursor + 46,
        cursor + 46 + fileNameLength,
      );
      final name = _decodeFileName(fileNameBytes, flags);
      if (name.isEmpty || name.contains('\u0000')) {
        throw const FormatException('ZIP 条目名称无效。');
      }
      if (filesByName.containsKey(name)) {
        throw FormatException('ZIP 包含重复条目：$name。');
      }

      _requireRange(bytes, localHeaderOffset, 30, 'ZIP 本地条目头不完整。');
      if (_readUint32(data, localHeaderOffset) != _localFileHeaderSignature) {
        throw FormatException('ZIP 本地条目标识无效：$name。');
      }
      final localFlags = _readUint16(data, localHeaderOffset + 6);
      final localCompressionMethod = _readUint16(data, localHeaderOffset + 8);
      final localCrc32 = _readUint32(data, localHeaderOffset + 14);
      final localCompressedSize = _readUint32(data, localHeaderOffset + 18);
      final localUncompressedSize = _readUint32(data, localHeaderOffset + 22);
      final localFileNameLength = _readUint16(data, localHeaderOffset + 26);
      final localExtraFieldLength = _readUint16(data, localHeaderOffset + 28);
      if (localFlags != flags || localCompressionMethod != compressionMethod) {
        throw FormatException('ZIP 条目元数据不一致：$name。');
      }
      if (flags & 0x0008 == 0 &&
          (localCrc32 != crc32 ||
              localCompressedSize != compressedSize ||
              localUncompressedSize != uncompressedSize)) {
        throw FormatException('ZIP 条目长度或校验值不一致：$name。');
      }
      final localNameStart = localHeaderOffset + 30;
      _requireRange(
        bytes,
        localNameStart,
        localFileNameLength + localExtraFieldLength,
        'ZIP 本地条目头不完整。',
      );
      final localNameBytes = Uint8List.sublistView(
        bytes,
        localNameStart,
        localNameStart + localFileNameLength,
      );
      if (!_equalBytes(fileNameBytes, localNameBytes)) {
        throw FormatException('ZIP 条目名称不一致：$name。');
      }

      final dataOffset =
          localNameStart + localFileNameLength + localExtraFieldLength;
      if (dataOffset > centralDirectoryOffset ||
          compressedSize > centralDirectoryOffset - dataOffset) {
        throw FormatException('ZIP 条目数据范围无效：$name。');
      }
      final entryEnd = dataOffset + compressedSize;
      occupiedRanges.add((start: localHeaderOffset, end: entryEnd, name: name));

      final entry = BoundedZipEntry._(
        archiveBytes: bytes,
        readBudget: readBudget,
        name: name,
        compressionMethod: compressionMethod,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        crc32: crc32,
        dataOffset: dataOffset,
        isFile: !name.endsWith('/') && !name.endsWith(r'\'),
      );
      files.add(entry);
      filesByName[name] = entry;
      cursor += 46 + variableLength;
    }
    if (cursor != eocdOffset) {
      throw const FormatException('ZIP 中央目录长度不一致。');
    }
    occupiedRanges.sort((left, right) => left.start.compareTo(right.start));
    for (var index = 1; index < occupiedRanges.length; index++) {
      if (occupiedRanges[index].start < occupiedRanges[index - 1].end) {
        throw FormatException('ZIP 条目数据范围重叠：${occupiedRanges[index].name}。');
      }
    }
    return BoundedZipArchive._(
      List<BoundedZipEntry>.unmodifiable(files),
      Map<String, BoundedZipEntry>.unmodifiable(filesByName),
    );
  }

  static const int _endOfCentralDirectorySignature = 0x06054b50;
  static const int _centralDirectorySignature = 0x02014b50;
  static const int _localFileHeaderSignature = 0x04034b50;
  static const int _zip64Uint16 = 0xffff;
  static const int _zip64Uint32 = 0xffffffff;
  static const int _encryptedFlags = 0x2041;
  static const int _unixSymbolicLinkType = 0xa000;
  static const int _unixFileTypeMask = 0xf000;
  static const int _maxCommentBytes = 0xffff;

  final List<BoundedZipEntry> files;
  final Map<String, BoundedZipEntry> _filesByName;

  int get length => files.length;

  BoundedZipEntry? findFile(String name) => _filesByName[name];

  static int _findEndOfCentralDirectory(Uint8List bytes, ByteData data) {
    if (bytes.length < 22) return -1;
    final minOffset = math.max(0, bytes.length - 22 - _maxCommentBytes);
    for (var offset = bytes.length - 22; offset >= minOffset; offset--) {
      if (_readUint32(data, offset) != _endOfCentralDirectorySignature) {
        continue;
      }
      final commentLength = _readUint16(data, offset + 20);
      if (offset + 22 + commentLength == bytes.length) return offset;
    }
    return -1;
  }

  static String _decodeFileName(Uint8List bytes, int flags) {
    if (flags & 0x0800 != 0) return utf8.decode(bytes);
    return String.fromCharCodes(bytes);
  }

  static bool _equalBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static void _requireRange(
    Uint8List bytes,
    int offset,
    int length,
    String message,
  ) {
    if (offset < 0 || length < 0 || offset > bytes.length - length) {
      throw FormatException(message);
    }
  }

  static int _readUint16(ByteData data, int offset) =>
      data.getUint16(offset, Endian.little);

  static int _readUint32(ByteData data, int offset) =>
      data.getUint32(offset, Endian.little);
}

final class BoundedZipEntry {
  const BoundedZipEntry._({
    required this._archiveBytes,
    required this._readBudget,
    required this.name,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
    required this.dataOffset,
    required this.isFile,
  });

  final Uint8List _archiveBytes;
  final _ZipReadBudget _readBudget;
  final String name;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int crc32;
  final int dataOffset;
  final bool isFile;

  int get size => uncompressedSize;

  bool get isDirectory => !isFile;

  Uint8List readBytes({required int maxBytes}) {
    if (!isFile) {
      throw FormatException('ZIP 条目不是文件：$name。');
    }
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', '不得小于零。');
    }
    if (compressedSize > maxBytes || uncompressedSize > maxBytes) {
      throw FormatException('ZIP 条目超过安全上限：$name。');
    }
    _readBudget.consume(uncompressedSize, name);

    final payload = Uint8List.sublistView(
      _archiveBytes,
      dataOffset,
      dataOffset + compressedSize,
    );
    late final Uint8List decoded;
    if (compressionMethod == 0) {
      if (compressedSize != uncompressedSize) {
        throw FormatException('ZIP 存储条目长度不一致：$name。');
      }
      decoded = Uint8List.fromList(payload);
    } else if (compressionMethod == 8) {
      decoded = _inflate(payload, maxBytes: uncompressedSize, name: name);
    } else {
      throw FormatException('ZIP 条目使用了不支持的压缩方式：$name。');
    }
    if (decoded.length != uncompressedSize) {
      throw FormatException('ZIP 条目展开长度不一致：$name。');
    }
    if (_crc32(decoded) != crc32) {
      throw FormatException('ZIP 条目校验失败：$name。');
    }
    return decoded;
  }

  static Uint8List _inflate(
    Uint8List payload, {
    required int maxBytes,
    required String name,
  }) {
    final output = _BoundedByteSink(maxBytes);
    try {
      final input = ZLibCodec(raw: true).decoder.startChunkedConversion(output);
      const chunkSize = 64 * kBytesPerKiB;
      for (var offset = 0; offset < payload.length; offset += chunkSize) {
        final end = math.min(payload.length, offset + chunkSize);
        input.add(Uint8List.sublistView(payload, offset, end));
      }
      input.close();
      return output.takeBytes();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException('ZIP 条目解压失败：$name。');
    }
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = _crc32Table[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static final List<int> _crc32Table = List<int>.unmodifiable(
    List<int>.generate(256, (value) {
      var entry = value;
      for (var bit = 0; bit < 8; bit++) {
        entry = entry & 1 == 0 ? entry >> 1 : (entry >> 1) ^ 0xedb88320;
      }
      return entry;
    }),
  );
}

final class _ZipReadBudget {
  _ZipReadBudget(this.maxBytes);

  final int maxBytes;
  int _usedBytes = 0;

  void consume(int bytes, String name) {
    if (bytes > maxBytes - _usedBytes) {
      throw FormatException('ZIP 累计展开大小超过安全上限：$name。');
    }
    _usedBytes += bytes;
  }
}

final class _BoundedByteSink extends ByteConversionSink {
  _BoundedByteSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> chunk) {
    if (chunk.length > maxBytes - _length) {
      throw const FormatException('ZIP 条目实际展开大小超过声明值。');
    }
    _buffer.add(chunk);
    _length += chunk.length;
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    if (start < 0 || end < start || end > chunk.length) {
      throw RangeError.range(end, start, chunk.length);
    }
    add(
      chunk is Uint8List
          ? Uint8List.sublistView(chunk, start, end)
          : chunk.sublist(start, end),
    );
    if (isLast) close();
  }

  @override
  void close() {}

  Uint8List takeBytes() => _buffer.takeBytes();
}
