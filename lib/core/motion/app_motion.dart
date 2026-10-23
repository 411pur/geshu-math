import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared motion tokens and motion primitives for the existing UI.
///
/// Everything in this file is *additive*: the primitives only animate
/// transform / opacity / paint of the widget they wrap. None of them change
/// layout, spacing, colors or tap behavior of the existing screens, so the
/// visual design stays exactly as designed.
class AppMotion {
  AppMotion._();

  // ── Durations ────────────────────────────────────────────────────────
  static const Duration instant = Duration(milliseconds: 70);
  static const Duration fast = Duration(milliseconds: 110);
  static const Duration standard = Duration(milliseconds: 170);
  static const Duration navigation = Duration(milliseconds: 240);
  static const Duration expressive = Duration(milliseconds: 280);

  /// Entrance of a content block (hero, card group, list row).
  static const Duration reveal = Duration(milliseconds: 340);

  /// Re-entrance of a whole pane when the user switches section/tab.
  static const Duration settle = Duration(milliseconds: 260);

  /// 卡牌从环形牌阵中抽出并过渡到悬停位的时长。
  static const Duration cardDraw = Duration(milliseconds: 360);

  /// 卡牌离开悬停状态后回到牌阵的时长。
  static const Duration cardReturn = Duration(milliseconds: 280);

  /// Per-item delay for staggered groups.
  static const Duration staggerStep = Duration(milliseconds: 45);

  /// Upper bound of the stagger delay so long lists never feel slow.
  static const Duration staggerLimit = Duration(milliseconds: 320);

  /// Number roll-up on statistic cards.
  static const Duration counter = Duration(milliseconds: 760);

  // ── Curves ───────────────────────────────────────────────────────────
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeOutCubic;
  static const Curve release = Curves.easeOutBack;
  static const Curve spring = Curves.easeOutBack;

  /// Long-travel movements: starts fast, lands softly.
  static const Curve emphasized = Curves.easeOutQuint;

  /// 强回弹：明显过冲后收回，用来制造「Q 弹」手感（按压回弹、卡片进场）。
  static const Curve bouncy = Cubic(0.34, 1.56, 0.64, 1);

  /// 轻过冲：数字、图标收尾时的小弹跳。
  static const Curve pop = Cubic(0.22, 1.40, 0.36, 1);

  /// 抽牌第一段：快速离阵并保留一点“打牌”惯性。
  static const Curve cardDrawCurve = Cubic(0.16, 0.92, 0.28, 1);

  /// 抽牌第二段：从轻微过冲处落稳到悬停位。
  static const Curve cardSettleCurve = Curves.easeOutCubic;
  static const Curve settleCurve = Curves.easeOutCubic;
  static const Curve decelerate = Curves.decelerate;

  /// Returns [duration], or [Duration.zero] when the platform asks for
  /// reduced motion (`MediaQuery.disableAnimations`, i.e. the OS
  /// "reduce motion" accessibility switch).
  static Duration resolve(BuildContext context, Duration duration) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disableAnimations ? Duration.zero : duration;
  }

  /// True when the platform asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Delay of the [index]-th item inside a staggered group, capped by
  /// [limit] so even a 100-row list finishes revealing quickly.
  static Duration stagger(
    int index, {
    Duration step = staggerStep,
    Duration limit = staggerLimit,
  }) {
    final ms = math.min(
      math.max(index, 0) * step.inMilliseconds,
      limit.inMilliseconds,
    );
    return Duration(milliseconds: ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Entrance
// ─────────────────────────────────────────────────────────────────────────

/// Fades + glides its [child] into place once, when it is first inserted.
///
/// The child keeps its exact layout box during the whole animation (opacity
/// and transform only), so wrapping existing widgets never shifts the page.
///
/// Use [index] to stagger siblings:
/// ```dart
/// for (var i = 0; i < cards.length; i++) AppReveal(index: i, child: cards[i])
/// ```
class AppReveal extends StatefulWidget {
  const AppReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.duration = AppMotion.reveal,
    this.offset = const Offset(0, 12),
    this.beginScale = 0.985,
    this.curve = AppMotion.bouncy,
    this.enabled = true,
  });

  final Widget child;

  /// Position inside a staggered group (delay = index * staggerStep).
  final int index;

  /// Extra delay added on top of the staggered delay.
  final Duration delay;
  final Duration duration;

  /// Distance the child travels while fading in. Use `Offset.zero` for a
  /// pure cross-fade.
  final Offset offset;
  final double beginScale;
  final Curve curve;
  final bool enabled;

  @override
  State<AppReveal> createState() => _AppRevealState();
}

class _AppRevealState extends State<AppReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _motion;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // 透明度用不会越界的曲线，位移/缩放用过冲曲线：
    // 结果就是「淡入很干净、但图形会弹一下」，也就是 Q 弹的来源
    _fade = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
    _motion = CurvedAnimation(parent: _controller, curve: widget.curve);
    _schedule();
  }

  void _schedule() {
    final total = widget.delay + AppMotion.stagger(widget.index);
    if (total == Duration.zero) {
      _controller.forward();
      return;
    }
    // 可取消的延时，避免 widget 在等待期间被移除时留下悬挂的 Timer
    _delayTimer = Timer(total, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) && !_controller.isCompleted) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || AppMotion.reduced(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final fade = _fade.value;
        final motion = _motion.value;
        final remaining = 1 - fade;
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              widget.offset.dx * remaining,
              widget.offset.dy * remaining,
            ),
            child: Transform.scale(
              scale: widget.beginScale + (1 - widget.beginScale) * motion,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// State switching
// ─────────────────────────────────────────────────────────────────────────

/// Cross-fades between content states (loading → data → error → empty).
///
/// The outgoing state fades out while the incoming one fades in and rises a
/// few pixels. Give the [child] a changing key/type (an `.when(...)` result
/// does this naturally) so the switcher can tell the states apart.
class AppStateSwitcher extends StatelessWidget {
  const AppStateSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.standard,
    this.offset = const Offset(0, 0.03),
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;

  /// Fractional vertical offset the incoming child travels.
  final Offset offset;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, duration),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: offset,
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Replays a short "settle" animation whenever [trigger] changes.
///
/// Used by the workspace shell so switching between the five sections fades
/// and lifts the new pane into place instead of hard-cutting. The child is
/// **not** rebuilt with a new key, so each branch keeps its state and
/// scroll position.
class AppBranchSettle extends StatefulWidget {
  const AppBranchSettle({
    super.key,
    required this.trigger,
    required this.child,
    this.duration = AppMotion.settle,
    this.offset = const Offset(0, 10),
    this.beginScale = 0.995,
  });

  final Object? trigger;
  final Widget child;
  final Duration duration;
  final Offset offset;
  final double beginScale;

  @override
  State<AppBranchSettle> createState() => _AppBranchSettleState();
}

class _AppBranchSettleState extends State<AppBranchSettle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Starts settled: the pane is already visible on first paint.
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(AppBranchSettle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return widget.child;
    }
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.settleCurve,
    );
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        final value = curved.value;
        final remaining = 1 - value;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              widget.offset.dx * remaining,
              widget.offset.dy * remaining,
            ),
            child: Transform.scale(
              scale: widget.beginScale + (1 - widget.beginScale) * value,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Hover / press feedback
// ─────────────────────────────────────────────────────────────────────────

/// Adds press scaling and optional hover lift without intercepting gestures.
///
/// [Listener] observes pointer events while the wrapped button still owns its
/// original [onPressed] or [onTap] callback.
class AppPressScale extends StatefulWidget {
  const AppPressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.94,
    this.hoverScale = 1,
    this.pressDuration = AppMotion.instant,
    this.releaseDuration = AppMotion.navigation,
    this.pressedOffset = 0.8,
    this.hoverOffset = -0.8,
    this.enabled = true,
    this.cursor = MouseCursor.defer,
  });

  final Widget child;
  final double pressedScale;
  final double hoverScale;
  final Duration pressDuration;
  final Duration releaseDuration;
  final double pressedOffset;
  final double hoverOffset;
  final bool enabled;
  final MouseCursor cursor;

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final targetScale = !widget.enabled
        ? 1.0
        : _pressed
        ? widget.pressedScale
        : _hovered
        ? widget.hoverScale
        : 1.0;

    final targetOffset = !widget.enabled
        ? 0.0
        : _pressed
        ? widget.pressedOffset
        : _hovered
        ? widget.hoverOffset
        : 0.0;
    final duration = _pressed ? widget.pressDuration : widget.releaseDuration;

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) {
        if (widget.enabled && widget.hoverScale != 1) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, duration),
          curve: _pressed ? AppMotion.exit : AppMotion.bouncy,
          transform: Matrix4.translationValues(0, targetOffset, 0),
          child: AnimatedScale(
            scale: targetScale,
            duration: AppMotion.resolve(context, duration),
            curve: _pressed ? AppMotion.exit : AppMotion.bouncy,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Hover-only lift for surfaces that are *not* buttons (stat cards, list
/// rows, read-only cards). Keeps the desktop workspace feeling alive without
/// implying a tap target that does not exist.
class AppHoverLift extends StatefulWidget {
  const AppHoverLift({
    super.key,
    required this.child,
    this.lift = -3,
    this.scale = 1.012,
    this.duration = AppMotion.navigation,
    this.enabled = true,
  });

  final Widget child;
  final double lift;
  final double scale;
  final Duration duration;
  final bool enabled;

  @override
  State<AppHoverLift> createState() => _AppHoverLiftState();
}

class _AppHoverLiftState extends State<AppHoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _hovered;
    final duration = AppMotion.resolve(context, widget.duration);

    return MouseRegion(
      onEnter: (_) {
        if (widget.enabled && !_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.bouncy,
        transform: Matrix4.translationValues(0, active ? widget.lift : 0, 0),
        child: AnimatedScale(
          scale: active ? widget.scale : 1,
          duration: duration,
          curve: AppMotion.bouncy,
          child: widget.child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Attention / emphasis
// ─────────────────────────────────────────────────────────────────────────

/// One-shot horizontal shake, used to draw the eye to a failed action or an
/// error banner the moment it appears. Layout box is unchanged.
class AppShake extends StatefulWidget {
  const AppShake({
    super.key,
    required this.child,
    this.amplitude = 6,
    this.cycles = 2,
    this.duration = const Duration(milliseconds: 420),
    this.enabled = true,
  });

  final Widget child;
  final double amplitude;
  final int cycles;
  final Duration duration;
  final bool enabled;

  @override
  State<AppShake> createState() => _AppShakeState();
}

class _AppShakeState extends State<AppShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.enabled) _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) && !_controller.isCompleted) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || AppMotion.reduced(context)) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        // Damped sine: biggest at the start, settles to exactly 0.
        final dx =
            math.sin(t * math.pi * 2 * widget.cycles) *
            widget.amplitude *
            (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Roll-up animation for numeric statistics.
///
/// Renders the same [Text] the page would render, just counting towards
/// [value]; the final frame is identical to the static value.
class AppCountUp extends StatelessWidget {
  const AppCountUp({
    super.key,
    required this.value,
    this.style,
    this.duration = AppMotion.counter,
    this.prefix = '',
    this.suffix = '',
    this.formatter,
    this.fallback = '—',
  });

  final num? value;
  final TextStyle? style;
  final Duration duration;
  final String prefix;
  final String suffix;

  /// Optional custom number formatter (e.g. one decimal place).
  final String Function(double value)? formatter;

  /// Shown when [value] is null (keeps the existing "—" placeholder).
  final String fallback;

  String _format(double v) {
    if (formatter != null) return formatter!(v);
    final rounded = v.roundToDouble();
    return (v - rounded).abs() < 0.001
        ? rounded.toInt().toString()
        : v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    if (value == null) return Text(fallback, style: style);

    final target = value!.toDouble();
    if (AppMotion.reduced(context)) {
      return Text('$prefix${_format(target)}$suffix', style: style);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: duration,
      curve: AppMotion.pop,
      builder: (context, animated, _) =>
          Text('$prefix${_format(animated)}$suffix', style: style),
    );
  }
}

/// Staggered "AI is thinking" dots. Only animate while a request is actually
/// in flight, so idle screens stay completely static.
class AppTypingDots extends StatefulWidget {
  const AppTypingDots({
    super.key,
    this.color,
    this.dotSize = 5,
    this.spacing = 4,
  });

  final Color? color;
  final double dotSize;
  final double spacing;

  @override
  State<AppTypingDots> createState() => _AppTypingDotsState();
}

class _AppTypingDotsState extends State<AppTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    if (AppMotion.reduced(context)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            _dot(1, color),
          ],
        ],
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: widget.spacing),
            _animatedDot(i, color),
          ],
        ],
      ),
    );
  }

  Widget _animatedDot(int index, Color color) {
    final phase = (_controller.value - index * 0.16) % 1.0;
    // 0 → 1 → 0 bell around the middle of the cycle.
    final wave = math.sin((phase.clamp(0.0, 1.0)) * math.pi);
    final opacity = 0.35 + 0.65 * math.max(wave, 0.0);
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -2 * math.max(wave, 0.0)),
        child: _dot(1, color),
      ),
    );
  }

  Widget _dot(double opacity, Color color) => Container(
    width: widget.dotSize,
    height: widget.dotSize,
    decoration: BoxDecoration(
      color: color.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}
