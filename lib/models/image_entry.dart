// Ticket 28: one image-generation entry (a lane target).
// lane: 'owner' (third-party Gradio Space, $0/gen) or 'runpod' (Kai's own
// serverless endpoint - Kai-only by founder rule, Amendment 9: runpod
// entries are device-local, never synced, never pinned).
class ImageEntry {
  final String id;
  final String name;
  final String link; // Space URL (owner) or HF GGUF repo id (runpod)
  final String lane; // 'owner' | 'runpod'
  final String endpoint; // gradio endpoint path for owner entries
  final int fnIndex; // position of the endpoint in the Space's API info
  final bool pinned;
  final bool remote; // came from the shared config (pinned by Kai)
  final int createdMs;
  // Ticket 32: 'image' | 'video'. Video entries are RunPod-only; for
  // them the link is the LoRA repo (the Wan 2.2 base stack is fixed
  // infrastructure on the worker, not a per-entry model).
  final String kind;
  final String lora; // optional extra LoRA ref for image entries

  const ImageEntry({
    required this.id,
    required this.name,
    required this.link,
    required this.lane,
    this.endpoint = '/generate',
    this.fnIndex = 0,
    this.pinned = false,
    this.remote = false,
    required this.createdMs,
    this.kind = 'image',
    this.lora = '',
  });

  bool get isRunpod => lane == 'runpod';
  bool get isChatGpt => lane == 'chatgpt'; // ticket 33 subscription lane
  bool get isVideo => kind == 'video';

  // Gradio API host for owner entries: a huggingface.co/spaces/<u>/<n> page
  // URL maps to https://<u>-<n>.hf.space; a direct *.hf.space URL passes.
  String get gradioBase {
    var l = link.trim();
    if (l.endsWith('/')) l = l.substring(0, l.length - 1);
    final sp = l.indexOf('/spaces/');
    if (sp >= 0) {
      final rest = l.substring(sp + '/spaces/'.length);
      final parts = rest.split('/');
      if (parts.length >= 2) {
        return 'https://${parts[0]}-${parts[1]}.hf.space';
      }
    }
    return l;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'link': link,
        'lane': lane,
        'endpoint': endpoint,
        'fnIndex': fnIndex,
        'pinned': pinned,
        'createdMs': createdMs,
        'kind': kind,
        'lora': lora,
      };

  factory ImageEntry.fromMap(Map m, {bool remote = false}) => ImageEntry(
        id: m['id']?.toString() ?? '',
        name: m['name']?.toString() ?? 'Entry',
        link: m['link']?.toString() ?? '',
        lane: m['lane']?.toString() ?? 'owner',
        endpoint: m['endpoint']?.toString() ?? '/generate',
        fnIndex: (m['fnIndex'] as num?)?.toInt() ?? 0,
        pinned: m['pinned'] == true,
        remote: remote,
        createdMs: (m['createdMs'] as num?)?.toInt() ?? 0,
        kind: m['kind']?.toString() ?? 'image',
        lora: m['lora']?.toString() ?? '',
      );

  ImageEntry copyWith({bool? pinned}) => ImageEntry(
        id: id,
        name: name,
        link: link,
        lane: lane,
        endpoint: endpoint,
        pinned: pinned ?? this.pinned,
        remote: remote,
        createdMs: createdMs,
        kind: kind,
        lora: lora,
      );
}
