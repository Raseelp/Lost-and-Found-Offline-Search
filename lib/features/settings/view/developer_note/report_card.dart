import 'package:flutter/material.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/features/settings/models/report_attachment.dart';
import 'package:lost_and_found/features/settings/view/developer_note/note_motion.dart';

/// Where the report is on its way: not yet sent, being got ready, or open in the mail app.
enum ReportSendState { idle, sending, opened }

/// The problem report in one box: what went wrong, everything that goes along as chips, the way a mail app shows
/// attachments, and Send at the bottom. The logs are one of the chips, and the person can leave them out or read them
/// first. The box takes a thin outline of the accent while the person is typing.
class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.message,
    required this.focusNode,
    required this.onMessageChanged,
    required this.attachments,
    required this.tooBig,
    required this.onAdd,
    required this.onRemove,
    required this.includeLogs,
    required this.onIncludeLogs,
    required this.onViewLogs,
    required this.canSend,
    required this.sendState,
    required this.onSend,
  });

  final TextEditingController message;
  final FocusNode focusNode;
  final VoidCallback onMessageChanged;
  final List<ReportAttachment> attachments;
  final bool tooBig;
  final VoidCallback onAdd;
  final ValueChanged<ReportAttachment> onRemove;
  final bool includeLogs;
  final ValueChanged<bool> onIncludeLogs;
  final VoidCallback onViewLogs;
  final bool canSend;
  final ReportSendState sendState;
  final VoidCallback onSend;

  static const _maxLength = 4000;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final limit = ReportAttachment.formatSize(ReportAttachment.maxTotalBytes);
    final total = ReportAttachment.totalSize(attachments);
    final filesNote = tooBig
        ? 'The files are ${ReportAttachment.formatSize(total)}. Keep them under $limit.'
        : total == 0
        ? 'Keep the files under $limit.'
        : '${ReportAttachment.formatSize(total)} of $limit.';
    final caption = text.bodySmall?.copyWith(
      color: AppColors.ink48,
      height: 1.4,
    );
    final quick = calm(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) => AnimatedContainer(
        duration: quick,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: focusNode.hasFocus
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.dividerSoft,
          ),
        ),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: TextField(
              controller: message,
              focusNode: focusNode,
              onChanged: (_) => onMessageChanged(),
              minLines: 4,
              maxLines: 9,
              maxLength: _maxLength,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              textCapitalization: TextCapitalization.sentences,
              style: text.bodyLarge,
              decoration: InputDecoration(
                hintText: 'What went wrong, or what would you like to see?',
                hintStyle: text.bodyLarge?.copyWith(color: AppColors.ink48),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.dividerSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.base,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SmoothSize(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      AnimatedSwitcher(
                        duration: quick,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween(
                              begin: 0.9,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: includeLogs
                            ? _LogsChip(
                                key: const ValueKey('logs-on'),
                                onOpen: onViewLogs,
                                onLeaveOut: () => onIncludeLogs(false),
                              )
                            : _GhostChip(
                                key: const ValueKey('logs-off'),
                                icon: Icons.add_rounded,
                                label: 'Attach logs',
                                onTap: () => onIncludeLogs(true),
                              ),
                      ),
                      for (final a in attachments)
                        Pop(
                          key: ValueKey(a.uri),
                          child: _FileChip(
                            attachment: a,
                            onRemove: () => onRemove(a),
                          ),
                        ),
                      _GhostChip(
                        key: const ValueKey('add'),
                        icon: Icons.attach_file_rounded,
                        label: 'Add a screenshot or recording',
                        onTap: onAdd,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  includeLogs
                      ? 'Logs help me find the problem faster. Tap them to read what is attached.'
                      : 'Logs help me find the problem faster. You can attach them again.',
                  style: caption,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (MediaQuery.textScalerOf(context).scale(14) > 18) ...[
                  Text(
                    filesNote,
                    style: caption?.copyWith(
                      color: tooBig ? AppColors.danger : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SendButton(
                      enabled: canSend,
                      state: sendState,
                      onTap: onSend,
                    ),
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          filesNote,
                          style: caption?.copyWith(
                            color: tooBig ? AppColors.danger : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _SendButton(
                        enabled: canSend,
                        state: sendState,
                        onTap: onSend,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Send, small and at the bottom right of the box, as in a message composer. It stays dim until there is something to
/// send, then comes up to size with a small overshoot, and while the mail is got ready it shows a spinner and then, for
/// a moment, that the mail app is open.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final bool enabled;
  final ReportSendState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quick = calm(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final label = Theme.of(context).textTheme.labelLarge;
    final Widget content = switch (state) {
      ReportSendState.idle => Row(
        key: const ValueKey('idle'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.send_rounded, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Send',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: label,
            ),
          ),
        ],
      ),
      ReportSendState.sending => const SizedBox(
        key: ValueKey('sending'),
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.ink48,
        ),
      ),
      ReportSendState.opened => Row(
        key: const ValueKey('opened'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Email app open',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: label,
            ),
          ),
        ],
      ),
    };

    return AnimatedScale(
      scale: enabled ? 1 : 0.96,
      duration: quick,
      curve: Curves.easeOutBack,
      child: SmoothSize(
        alignment: Alignment.centerRight,
        duration: quick,
        child: FilledButton(
          onPressed: enabled ? onTap : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 40),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            shape: const StadiumBorder(),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: AnimatedSwitcher(
            duration: quick,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A pill the size of a chip, with a label and an optional end.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.background,
    required this.child,
    this.onTap,
    this.outlined = false,
  });

  final Color background;
  final Widget child;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: StadiumBorder(
        side: outlined
            ? const BorderSide(color: AppColors.hairline)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40, maxWidth: 300),
              child: child,
            )
          : InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40, maxWidth: 300),
                child: child,
              ),
            ),
    );
  }
}

/// The logs, attached. The body of the pill opens them to read, and the cross leaves them out. They are separate
/// targets, so a screen reader reaches both.
class _LogsChip extends StatelessWidget {
  const _LogsChip({super.key, required this.onOpen, required this.onLeaveOut});

  final VoidCallback onOpen;
  final VoidCallback onLeaveOut;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AppColors.primary);
    return _Chip(
      background: AppColors.primary.withValues(alpha: 0.09),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              button: true,
              label: 'Logs attached. Tap to read them.',
              excludeSemantics: true,
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'Logs attached',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ChipCross(
            tooltip: 'Leave the logs out',
            color: AppColors.primary,
            onTap: onLeaveOut,
          ),
        ],
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.attachment, required this.onRemove});

  final ReportAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Chip(
      background: AppColors.parchment,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              attachment.isVideo
                  ? Icons.videocam_outlined
                  : Icons.image_outlined,
              size: 18,
              color: AppColors.ink80,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge,
              ),
            ),
            if (attachment.size > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                ReportAttachment.formatSize(attachment.size),
                style: text.bodySmall?.copyWith(color: AppColors.ink48),
              ),
            ],
            _ChipCross(
              tooltip: 'Remove ${attachment.name}',
              color: AppColors.ink48,
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// A chip with only an outline, for something that can be added.
class _GhostChip extends StatelessWidget {
  const _GhostChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Chip(
      background: AppColors.transparent,
      outlined: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.ink80),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppColors.ink80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cross at the end of a chip. Its touch area is the height of the chip.
class _ChipCross extends StatelessWidget {
  const _ChipCross({
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.close_rounded, size: 16, color: color),
        ),
      ),
    );
  }
}
