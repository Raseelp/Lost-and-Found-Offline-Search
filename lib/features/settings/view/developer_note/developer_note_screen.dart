import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lost_and_found/core/app_links.dart';
import 'package:lost_and_found/core/open_link.dart';
import 'package:lost_and_found/core/theme/app_colors.dart';
import 'package:lost_and_found/core/theme/app_radius.dart';
import 'package:lost_and_found/core/theme/app_spacing.dart';
import 'package:lost_and_found/core/theme/motion.dart';
import 'package:lost_and_found/core/widgets/app_toast.dart';
import 'package:lost_and_found/features/settings/models/report_attachment.dart';
import 'package:lost_and_found/features/settings/services/settings_service.dart';
import 'package:lost_and_found/features/settings/view/developer_note/log_viewer_screen.dart';
import 'package:lost_and_found/features/settings/view/developer_note/note_motion.dart';
import 'package:lost_and_found/features/settings/view/developer_note/page_bar.dart';
import 'package:lost_and_found/features/settings/view/developer_note/report_card.dart';

/// A note from the developer: who makes the app and why it is free, an invitation to the code on GitHub, and a way to
/// report a problem or suggest something. It is the person's first impression of whoever is behind the app, so it is
/// a calm page of its own: a background of soft washes of the accent that drift slowly, and each part settling into
/// place one after another. All of that stands still when the phone asks for no animations.
/// Send opens the person's mail app with the report filled in. Nothing is sent from the app itself.
class DeveloperNoteScreen extends StatefulWidget {
  const DeveloperNoteScreen({super.key, this.full = true});

  /// The whole page, or only the way to report a problem. The whole page is for people who have used the app for a
  /// while (see DeveloperNoteController).
  final bool full;

  /// The page fades in and rises a little, instead of sliding over Settings.
  static Route<void> route({bool full = true}) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => DeveloperNoteScreen(full: full),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurveTween(curve: Curves.easeOutCubic).animate(animation);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );

  @override
  State<DeveloperNoteScreen> createState() => _DeveloperNoteScreenState();
}

class _DeveloperNoteScreenState extends State<DeveloperNoteScreen> with TickerProviderStateMixin {
  static const _issueBodyLimit = 1500;

  /// How many parts settle into place, one after another: the greeting and the note, then the heading of the report
  /// and the box.
  int get _parts => widget.full ? 7 : 2;

  /// Where in that order the heading of the report comes.
  int get _reportAt => widget.full ? 5 : 0;

  /// How long "Your email app is open" stays on the Send button.
  static const _openedFor = Duration(milliseconds: 2800);

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 16));
  final _message = TextEditingController();
  final _focus = FocusNode();
  final _attachments = <ReportAttachment>[];
  bool _includeLogs = true;
  ReportSendState _sendState = ReportSendState.idle;
  bool _thanked = false;
  bool _started = false;
  bool _picking = false;
  Timer? _openedTimer;

  late final _contribute = TapGestureRecognizer()..onTap = () => openLink(kRepoUrl);

  int get _total => ReportAttachment.totalSize(_attachments);
  bool get _tooBig => _total > ReportAttachment.maxTotalBytes;
  bool get _canSend => _sendState != ReportSendState.sending && _message.text.trim().isNotEmpty && !_tooBig;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessCalm(context, _drift, reverse: true, rest: 0.5);
    if (_started) return;
    _started = true;
    if (calm(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _openedTimer?.cancel();
    _enter.dispose();
    _drift.dispose();
    _message.dispose();
    _focus.dispose();
    _contribute.dispose();
    super.dispose();
  }

  void _tick() => unawaited(HapticFeedback.lightImpact().catchError((_) {}));

  Future<void> _add() async {
    if (_picking) return;
    _picking = true;
    final List<ReportAttachment> picked;
    try {
      picked = await SettingsService().pickReportFiles();
    } catch (_) {
      _picking = false;
      AppToast.show("Couldn't open the file picker.");
      return;
    }
    _picking = false;
    if (!mounted) return;
    setState(() {
      for (final item in picked) {
        if (_attachments.every((a) => a.uri != item.uri)) {
          _attachments.add(item);
        }
      }
    });
  }

  Future<void> _send() async {
    _tick();
    FocusScope.of(context).unfocus();
    setState(() => _sendState = ReportSendState.sending);
    final String answer;
    try {
      answer = await SettingsService().sendReport(
        to: kDeveloperEmail,
        message: _message.text,
        attachments: _attachments,
        includeLogs: _includeLogs,
      );
    } catch (_) {
      if (mounted) setState(() => _sendState = ReportSendState.idle);
      AppToast.show("Couldn't open your email app.");
      return;
    }
    if (!mounted) return;
    if (answer == 'no_mail_app') {
      setState(() => _sendState = ReportSendState.idle);
      AppToast.show('No email app found. Opening GitHub instead.');
      await openLink(_issueUrl());
      return;
    }
    setState(() {
      _sendState = ReportSendState.opened;
      _thanked = true;
    });
    _openedTimer?.cancel();
    _openedTimer = Timer(_openedFor, () {
      if (mounted) setState(() => _sendState = ReportSendState.idle);
    });
  }

  String _issueUrl() {
    var body = _message.text.trim();
    if (body.length > _issueBodyLimit) {
      body = body.substring(0, _issueBodyLimit);
    }
    return Uri.parse(kRepoNewIssueUrl).replace(queryParameters: {'body': body}).toString();
  }

  /// Wraps part [index] so it fades in and rises while the page settles.
  Widget _part(int index, Widget child, {bool pop = false}) =>
      Settle(controller: _enter, index: index, parts: _parts, pop: pop, child: child);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lead = text.bodyLarge?.copyWith(fontSize: 18, height: 1.5);
    final body = text.bodyMedium?.copyWith(color: AppColors.ink80, fontSize: 15, height: 1.55);
    final strong = lead?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600);
    final link = body?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600);

    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: DriftingBackground(
        drift: _drift,
        child: SafeArea(
          child: Column(
            children: [
              const PageBar(),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xxl),
                  children: [
                    if (widget.full) ...[
                      _part(
                        0,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.xl),
                                child: Image.asset('assets/tour/logos/lost_and_found.png', width: 72, height: 72),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              "Hi, I'm Raseel",
                              style: text.headlineMedium?.copyWith(fontSize: 34, height: 1.1, letterSpacing: -0.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _part(
                        1,
                        Text.rich(
                          TextSpan(
                            style: lead,
                            children: [
                              const TextSpan(text: 'Lost & Found is a side project of mine. It is '),
                              TextSpan(text: 'free', style: strong),
                              const TextSpan(text: ' and '),
                              TextSpan(text: 'open source', style: strong),
                              const TextSpan(text: ', it has '),
                              TextSpan(text: 'no ads', style: strong),
                              const TextSpan(text: ', and there will be '),
                              TextSpan(text: 'no subscription, ever', style: strong),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _part(
                        2,
                        Text(
                          'That is possible because everything runs on your device itself: the searching, the face '
                          'recognition, all of it. So I have no server to run. The only thing the app downloads, the '
                          'search model, is hosted for free. It costs me nothing except my time and effort. '
                          'Your support buys me more of that time to improve them and keep them free.',
                          style: body,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      _part(3, const Align(alignment: Alignment.centerLeft, child: _CoffeeButton()), pop: true),
                      const SizedBox(height: AppSpacing.lg),
                      _part(
                        4,
                        Text.rich(
                          TextSpan(
                            style: body,
                            children: [
                              const TextSpan(text: 'The code is open. You are welcome to read it, and to '),
                              TextSpan(text: 'contribute on GitHub', style: link, recognizer: _contribute),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ] else
                      const SizedBox(height: AppSpacing.lg),
                    _part(
                      _reportAt,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.full)
                            Text('Report a problem', style: text.titleLarge)
                          else
                            Text(
                              'Report an issue',
                              style: text.headlineMedium?.copyWith(fontSize: 34, height: 1.1, letterSpacing: -0.5),
                            ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'If something is not working, or you have a suggestion, you can tell me here.',
                            style: body,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _part(
                      _reportAt + 1,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReportCard(
                            message: _message,
                            focusNode: _focus,
                            onMessageChanged: () => setState(() {}),
                            attachments: _attachments,
                            tooBig: _tooBig,
                            onAdd: _add,
                            onRemove: (a) => setState(() => _attachments.remove(a)),
                            includeLogs: _includeLogs,
                            onIncludeLogs: (value) {
                              _tick();
                              setState(() => _includeLogs = value);
                            },
                            onViewLogs: () =>
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogViewerScreen())),
                            canSend: _canSend,
                            sendState: _sendState,
                            onSend: _send,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                            child: Text(
                              'Send opens your email app, addressed to $kDeveloperEmail. You press Send there.',
                              style: text.bodySmall?.copyWith(color: AppColors.ink48, height: 1.4),
                            ),
                          ),
                          SmoothSize(
                            duration: const Duration(milliseconds: 300),
                            child: _thanked
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.md, AppSpacing.xs, 0),
                                    child: Text(
                                      'Thank you for telling me.',
                                      style: text.titleSmall?.copyWith(color: AppColors.primary),
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buy Me a Coffee's own button, as they publish it. It gives under a press and springs back.
class _CoffeeButton extends StatefulWidget {
  const _CoffeeButton();

  @override
  State<_CoffeeButton> createState() => _CoffeeButtonState();
}

class _CoffeeButtonState extends State<_CoffeeButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Buy me a coffee',
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: calm(context) ? Duration.zero : const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onHighlightChanged: (down) => setState(() => _down = down),
          onTap: () => openLink(kCoffeeUrl),
          child: Image.asset('assets/support/buy_me_a_coffee.png', width: 200),
        ),
      ),
    );
  }
}
