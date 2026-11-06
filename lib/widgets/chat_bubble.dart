import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/type_scale.dart';
import '../models/message_model.dart';
import '../services/haptics.dart';
import '../services/llm_service.dart';
import 'faithful/stream.dart';
import 'faithful/widgets.dart';

class ChatBubble extends StatelessWidget {
  final MessageModel message;

  /// If true, this is the last AI message and we show speed info
  final bool showSpeed;

  /// Ticket 08: this bubble is the live stream — render Stream Reply
  /// (#26), or the #2 progressive style while [isRegenerating].
  final bool isStreaming;
  final bool isRegenerating;
  final VoidCallback? onRegenerate;

  const ChatBubble({
    super.key,
    required this.message,
    this.showSpeed = false,
    this.isStreaming = false,
    this.isRegenerating = false,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isSmall = MediaQuery.of(context).size.width < 600;
    final hPad = isSmall ? 16.0 : 24.0;

    return Container(
      width: double.infinity,
      color: isUser ? Colors.transparent : context.bgMsgAi,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar — the R1 mark is the assistant's face (ticket 08)
          if (isUser)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: context.textM,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                AppIcons.user,
                size: 16,
                color: Colors.white,
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/minix-icon.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(width: 14),

          // Content
          Expanded(child: _buildContent(context, isUser)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          message.content,
          style: TS.body(context, color: context.text),
        ),
      );
    }

    // AI: while streaming, the Stream Reply port owns the text (#26;
    // #2 progressive style when regenerating). Prefill = shimmer text
    // only — the MorphOrb at center stage is the generation indicator
    // now (Kai, 2026-11-05: the bubble's own orb overlapped it).
    if (isStreaming) {
      if (message.content.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 3),
          child: TextShimmerWave(
            text: 'Generating',
            style: TextStyle(
              fontSize: TS.of(context, 14),
              color: context.textM,
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: isRegenerating
            ? RegenRevealText(
                text: message.content,
                style: TextStyle(
                  fontSize: TS.of(context, 15),
                  height: 1.6,
                  color: context.text,
                ),
              )
            : StreamReplyText(
                text: message.content,
                streaming: true,
                caretColor: context.textM,
                style: TextStyle(
                  fontSize: TS.of(context, 15),
                  height: 1.6,
                  color: context.text,
                ),
              ),
      );
    }

    // AI: render markdown
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: MarkdownBody(
            data: message.content,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(
                fontSize: TS.of(context, 15),
                color: context.text,
                height: 1.7,
              ),
              h1: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.text,
              ),
              h2: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.text,
              ),
              h3: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.text,
              ),
              code: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.codeText,
                backgroundColor: context.isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
              ),
              codeblockDecoration: BoxDecoration(
                color: AppColors.codeBg,
                borderRadius: BorderRadius.circular(8),
              ),
              codeblockPadding: const EdgeInsets.all(14),
              // UI audit 2026-11-06 P2-2: blockquote chrome is
              // decoration; the accent is action-only.
              blockquoteDecoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                border: Border(
                  left: BorderSide(color: context.textD, width: 3),
                ),
              ),
              blockquotePadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              listBullet: TextStyle(color: context.text),
              tableHead: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.text,
                fontSize: 14,
              ),
              tableBody: TextStyle(color: context.text, fontSize: 14),
              tableBorder: TableBorder.all(color: context.border),
              tableCellsPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.border)),
              ),
            ),
          ),
        ),

        // UI audit 2026-11-06 (Claude P2-6, Codex P1-12): an
        // interrupted reply says so, in words, with a retry. The
        // partial text above stays; it is never passed off as whole.
        if (message.failed) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: AppColors.red,
              ),
              const SizedBox(width: 6),
              Text(
                message.content.isEmpty
                    ? 'The reply could not be completed.'
                    : 'Response interrupted.',
                style: const TextStyle(fontSize: 12, color: AppColors.red),
              ),
              if (onRegenerate != null) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: onRegenerate,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentHi,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],

        // Action row: Copy + Speed
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                // Copy button (UI audit 2026-11-06 P1-7: the action
                // row gets a 44pt-tall hit area via vertical padding)
                InkWell(
                  onTap: () {
                    TapFx.light();
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: context.textD,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(fontSize: 12, color: context.textD),
                        ),
                      ],
                    ),
                  ),
                ),

                // Regenerate (ticket 08 — Stream Reply anatomy)
                if (onRegenerate != null && !isStreaming) ...[
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: onRegenerate,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: context.textD,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Regenerate',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textD,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Speed indicator (on the last AI message)
                if (showSpeed) ...[
                  const SizedBox(width: 12),
                  Obx(() {
                    final llm = Get.find<LlmService>();
                    final speed = llm.isGenerating.value
                        ? llm.tokensPerSecond.value
                        : llm.lastGenerationSpeed.value;
                    if (speed <= 0) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          size: 14,
                          color: context.textD,
                        ),
                        const SizedBox(width: 4),
                        SpringNumber(
                          value: speed,
                          decimals: 1,
                          style: TextStyle(fontSize: 12, color: context.textD),
                        ),
                        Text(
                          ' t/s',
                          style: TextStyle(fontSize: 12, color: context.textD),
                        ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
