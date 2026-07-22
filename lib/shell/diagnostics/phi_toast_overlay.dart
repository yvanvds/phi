import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_spacing.dart';
import 'phi_toast.dart';
import 'toast_controller.dart';
import 'toast_message.dart';

/// Renders the [ToastController]'s active toasts stacked at the bottom-centre,
/// above the status bar (design `docs/design/diagnostics.md` §3).
///
/// Non-interactive (an [IgnorePointer]) so it never steals a click from the
/// chrome beneath — a toast is a passing notice, not a control. Each toast's
/// auto-dismiss timer lives in [_ToastEntry] and is cancelled when that widget
/// is disposed, so a torn-down tree leaves no pending timer.
class PhiToastOverlay extends StatelessWidget {
  /// Watches [controller] and paints whatever toasts it holds.
  const PhiToastOverlay({required this.controller, super.key});

  /// The source of truth for which toasts are on screen.
  final ToastController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: PhiSpacing.s5),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final toast in controller.visible)
                    _ToastEntry(
                      key: ValueKey<int>(toast.id),
                      toast: toast,
                      lifespan: controller.displayDuration,
                      onDismiss: () => controller.dismiss(toast.id),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One toast plus its lifecycle: an entry fade/slide and the auto-dismiss timer.
class _ToastEntry extends StatefulWidget {
  const _ToastEntry({
    required this.toast,
    required this.lifespan,
    required this.onDismiss,
    super.key,
  });

  final ToastMessage toast;
  final Duration lifespan;
  final VoidCallback onDismiss;

  @override
  State<_ToastEntry> createState() => _ToastEntryState();
}

class _ToastEntryState extends State<_ToastEntry> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.lifespan, widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: PhiMotion.dur2,
      curve: PhiMotion.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: PhiToast(text: widget.toast.text, level: widget.toast.level),
    );
  }
}
