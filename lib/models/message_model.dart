import 'package:hive/hive.dart';

part 'message_model.g.dart';

@HiveType(typeId: 1)
enum MessageRole {
  @HiveField(0)
  user,
  @HiveField(1)
  assistant,
  @HiveField(2)
  system,
}

@HiveType(typeId: 2)
class MessageModel extends HiveObject {
  @HiveField(0)
  final MessageRole role;

  @HiveField(1)
  String content;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  String? imageBase64;

  @HiveField(4)
  String? imageMimeType;

  /// UI audit 2026-11-06 (Claude P2-6, Codex P1-12): an explicit
  /// failure state. A stream that died mid-reply used to be stored
  /// as a '⚠ Error: ...' string (or worse, passed off as a complete
  /// partial answer); now the flag carries it and the UI offers a
  /// retry. Old records have no field 5 and read back as false.
  @HiveField(5)
  bool failed;

  MessageModel({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.imageBase64,
    this.imageMimeType,
    this.failed = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isSystem => role == MessageRole.system;

  Map<String, String> toLlamaMessage() {
    return {
      'role': role.name,
      'content': content,
    };
  }
}
