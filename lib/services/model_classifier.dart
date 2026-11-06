import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/ai_model_info.dart';

/// Ticket 25 — local-only model classifier.
///
/// Reads a GGUF header (metadata KVs only, never tensor data, no
/// network — the offline law forbids phoning home to identify a
/// model) and derives: a clean display name, capability tags, and
/// the model's real context length. Filename heuristics are the
/// fallback when metadata is thin.
class GgufHeader {
  final String? name;
  final String? architecture;
  final int? expertCount;
  final int? contextLength;
  const GgufHeader({
    this.name,
    this.architecture,
    this.contextLength,
    this.expertCount,
  });
}

class _Reader {
  final Uint8List bytes;
  int pos = 0;
  _Reader(this.bytes);
  int u32() {
    final v = ByteData.sublistView(
      bytes,
      pos,
      pos + 4,
    ).getUint32(0, Endian.little);
    pos += 4;
    return v;
  }

  int u64() {
    final v = ByteData.sublistView(
      bytes,
      pos,
      pos + 8,
    ).getUint64(0, Endian.little);
    pos += 8;
    return v;
  }

  String str() {
    final len = u64();
    if (len < 0 || pos + len > bytes.length) {
      throw const FormatException('gguf string overruns the read window');
    }
    final s = utf8.decode(bytes.sublist(pos, pos + len), allowMalformed: true);
    pos += len;
    return s;
  }

  void skipValue(int type) {
    switch (type) {
      case 0: // u8
      case 1: // i8
      case 7: // bool
        pos += 1;
      case 2: // u16
      case 3: // i16
        pos += 2;
      case 4: // u32
      case 5: // i32
      case 6: // f32
        pos += 4;
      case 8: // string
        final len = u64();
        pos += len;
      case 9: // array
        final elemType = u32();
        final count = u64();
        // Corrupt counts must not loop (near-)forever or run off
        // the read window (Claude audit). Fixed-size elements skip
        // in O(1); strings recurse with the same bounds checks.
        if (count < 0 || count > 100000000) {
          throw const FormatException('gguf array count out of range');
        }
        const stride = {
          0: 1,
          1: 1,
          7: 1,
          2: 2,
          3: 2,
          4: 4,
          5: 4,
          6: 4,
          10: 8,
          11: 8,
          12: 8,
        };
        final st = stride[elemType];
        if (st != null) {
          pos += st * count;
          if (pos > bytes.length) {
            throw const FormatException('gguf array overruns the read window');
          }
        } else {
          for (var i = 0; i < count; i++) {
            skipValue(elemType);
          }
        }
      case 10: // u64
      case 11: // i64
      case 12: // f64
        pos += 8;
      default:
        throw const FormatException('unknown gguf value type');
    }
  }

  Object? readValue(int type) {
    switch (type) {
      case 0:
        return bytes[pos++];
      case 1:
        final v = ByteData.sublistView(bytes, pos, pos + 1).getInt8(0);
        pos += 1;
        return v;
      case 2:
        final v = ByteData.sublistView(
          bytes,
          pos,
          pos + 2,
        ).getUint16(0, Endian.little);
        pos += 2;
        return v;
      case 3:
        final v = ByteData.sublistView(
          bytes,
          pos,
          pos + 2,
        ).getInt16(0, Endian.little);
        pos += 2;
        return v;
      case 4:
      case 5:
      case 6:
        final start = pos;
        skipValue(type);
        if (type == 6) {
          return ByteData.sublistView(
            bytes,
            start,
            start + 4,
          ).getFloat32(0, Endian.little);
        }
        return ByteData.sublistView(
          bytes,
          start,
          start + 4,
        ).getUint32(0, Endian.little);
      case 7:
        return bytes[pos++] != 0;
      case 8:
        return str();
      case 9:
        skipValue(type);
        return null;
      case 10:
      case 11:
      case 12:
        final start = pos;
        skipValue(type);
        return ByteData.sublistView(
          bytes,
          start,
          start + 8,
        ).getUint64(0, Endian.little);
      default:
        return null;
    }
  }
}

/// Parse the metadata KVs at the head of a GGUF file. Reads at
/// most the first 4 MB — headers live at the front; tensor info
/// that follows is never touched. Returns null on any surprise.
Future<GgufHeader?> readGgufHeader(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final len = await file.length();
    final take = len < 4194304 ? len : 4194304;
    final bytes = await raf.read(take);
    if (bytes.length < 16) return null;
    final r = _Reader(bytes);
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'GGUF') return null;
    r.pos = 4;
    r.u32(); // version
    r.u64(); // tensor count
    final kvCount = r.u64();
    String? name;
    String? arch;
    int? ctx;
    int? experts;
    try {
      for (var i = 0; i < kvCount; i++) {
        final key = r.str();
        final type = r.u32();
        final wanted =
            key == 'general.name' ||
            key == 'general.architecture' ||
            key.endsWith('.context_length') ||
            key.endsWith('.expert_count');
        if (!wanted) {
          r.skipValue(type);
          continue;
        }
        final v = r.readValue(type);
        if (key == 'general.name' && v is String) name = v;
        if (key == 'general.architecture' && v is String) arch = v;
        if (key.endsWith('.context_length') && v is num) ctx = v.toInt();
        if (key.endsWith('.expert_count') && v is num) experts = v.toInt();
        // Everything wanted is in hand; the rest of the KV block
        // (large vocabularies push it past the 4 MB window) is
        // not worth another byte.
        if (name != null && arch != null && ctx != null && experts != null) {
          break;
        }
      }
    } catch (_) {
      // A surprise mid-walk keeps whatever was already parsed
      // instead of discarding the whole header (Claude audit).
      if (name == null && arch == null) rethrow;
    }
    return GgufHeader(
      name: name,
      architecture: arch,
      contextLength: ctx,
      expertCount: experts,
    );
  } catch (_) {
    return null;
  } finally {
    await raf?.close();
  }
}

class ModelClassifier {
  static final _quantSuffix = RegExp(
    r'[-_. ]?(UD[-_. ]?)?(IQ\d+(_[A-Z0-9]+)?|Q\d+(_K(_[SMLX]+)?|_\d+)?|F16|BF16|F32|FP16)$',
    caseSensitive: false,
  );
  static final _noise = RegExp(r'\b(gguf|the)\b', caseSensitive: false);

  /// Presentation name: the GGUF's own name when present, else the
  /// filename with quant + repo noise stripped. The filename stays
  /// the identity everywhere else.
  static String cleanName({String? ggufName, required String filename}) {
    var raw = (ggufName != null && ggufName.trim().isNotEmpty)
        ? ggufName.trim()
        : filename.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
    raw = raw.replaceAll(_quantSuffix, '');
    raw = raw.replaceAll(_noise, ' ');
    raw = raw
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (raw.isEmpty) return filename;
    return raw;
  }

  static const tagOrder = [
    'uncensored',
    'chat',
    'code',
    'vision',
    'reasoning',
    'base',
    'moe',
  ];

  /// Capability tags from the header + filename markers.
  static List<String> classifyTags({
    GgufHeader? header,
    required String filename,
    bool hasMmproj = false,
  }) {
    final hay = '${header?.name ?? ''} $filename'.toLowerCase();
    final tags = <String>{};
    bool has(List<String> needles) => needles.any(hay.contains);
    if (has([
      'abliterat',
      'heretic',
      'uncensored',
      'dolphin',
      'refusal',
      'uncnr',
      'unslop',
    ])) {
      tags.add('uncensored');
    }
    if (has(['coder', 'code-', 'code_', '-code', '_code', ' code '])) {
      tags.add('code');
    }
    if (hasMmproj ||
        has([
          '-vl',
          '_vl',
          ' llava',
          'vision',
          'multimodal',
          'minicpm-v',
          'moondream',
        ])) {
      tags.add('vision');
    }
    if (has([
      '-r1',
      '_r1',
      ' r1',
      'r1-',
      'deepseek-r1',
      'thinking',
      'reasoner',
      'reasoning',
      'qwq',
    ])) {
      tags.add('reasoning');
    }
    // MoE: the header's expert_count is the ground truth; the
    // A4B/A3B name shapes are the fallback for headers the walk
    // could not finish.
    if ((header?.expertCount ?? 0) > 0 ||
        has(['a4b', 'a3b', 'moe', '-a17b', 'a10b'])) {
      tags.add('moe');
    }
    if (has(['instruct', '-it', '_it', ' it ', 'chat', 'assistant'])) {
      tags.add('chat');
    }
    // 'base' means nothing else matched - a tuned model that
    // merely lacks the literal word 'chat' in its name is not a
    // base model (Claude audit: Dolphin got uncensored + base).
    if (tags.isEmpty) tags.add('base');
    return tagOrder.where(tags.contains).toList();
  }

  /// Classify one record. Manual records are never touched; the
  /// label stays in sync with the uncensored tag (existing
  /// surfaces read label).
  static AiModelInfo apply(
    AiModelInfo model, {
    GgufHeader? header,
    bool hasMmproj = false,
  }) {
    if (model.tagsSource == 'manual') return model;
    final tags = classifyTags(
      header: header,
      filename: model.filename,
      hasMmproj: hasMmproj,
    );
    return model.copyWith(
      name: cleanName(ggufName: header?.name, filename: model.filename),
      tags: tags,
      // A custom record's label is its persistence key (isCustom)
      // and never changes; catalog records sync as before.
      label: model.isCustom
          ? model.label
          : (tags.contains('uncensored') ? 'UNCENSORED' : model.label),
    );
  }
}
