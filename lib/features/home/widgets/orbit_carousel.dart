import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';

/// 一张环形轮播卡片的数据。
class OrbitCardData {
  const OrbitCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.path,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String path;
}

/// 3D 环形卡片轮播（参考 Jitter ORBIT 模板）。
///
/// 卡片围成一圈绕竖轴匀速旋转：正面的卡片最大最清晰，越往两侧越扁、
/// 越暗、越小，背面卡片淡出。可横向拖拽手动转动（带松手惯性），
/// 悬停暂停自动旋转，点击任意卡片进入对应功能。
///
/// 只使用 [Transform] + [Matrix4] 做透视，没有引入任何 3D 依赖。
class OrbitCarousel extends StatefulWidget {
  const OrbitCarousel({
    super.key,
    required this.items,
    required this.onOpen,
    this.height = 392,
    this.cardWidth = 220,
    this.cardHeight = 298,
    this.radius = 296,
    this.period = const Duration(seconds: 30),
    this.autoPlay = true,
  });

  final List<OrbitCardData> items;
  final ValueChanged<int> onOpen;

  /// 轮播整体高度（含地面留白）。
  final double height;
  final double cardWidth;
  final double cardHeight;

  /// 环形半径：越大卡片之间越松散。
  final double radius;

  /// 转满一圈所需时间。
  final Duration period;
  final bool autoPlay;

  @override
  State<OrbitCarousel> createState() => _OrbitCarouselState();
}

class _OrbitCarouselState extends State<OrbitCarousel>
    with TickerProviderStateMixin {
  late final AnimationController _auto;
  late final AnimationController _inertia;

  /// 每张卡独立的"抽牌 / 回阵"控制器，允许卡片之间平滑接力。
  late List<AnimationController> _drawControllers;

  /// 拖拽累计的额外角度（弧度）。
  double _dragAngle = 0;
  double _inertiaFrom = 0;
  double _inertiaTo = 0;

  /// 指针当前停在哪张卡上：>=0 表示在某张卡上，-1 表示在轮播内但不在卡上，
  /// null 表示已经离开轮播。
  int? _hovered;

  /// 指针在卡片上"停滞"够久 -> 暂停自动旋转。
  bool _dwelling = false;
  Timer? _dwellTimer;

  /// 停滞计时开始时指针所在的功能卡，避免卡片旋转离开指针时丢掉暂停意图。
  int? _dwellCandidate;

  /// 停滞判定的移动锚点，过滤浏览器在鼠标静止时产生的 1–2px 抖动。
  Offset? _hoverAnchor;

  /// 判定"停滞"的阈值：鼠标停住超过这个时间才暂停。
  static const Duration _dwellDelay = Duration(milliseconds: 300);

  /// 指针位移小于该值视为静止，避免微小抖动反复打断悬停。
  static const double _dwellMoveThreshold = 2.5;

  /// 每像素拖拽对应的旋转弧度。
  static const double _dragToRadians = 0.0072;

  /// 转过这个 cos 值就完全不绘制（已经到背面了）。
  static const double _cullCos = -0.28;

  /// 到这里卡片已完全淡出，中间是平滑过渡区。
  static const double _fadeOutCos = 0.30;

  /// 悬停时沿卡片法线向观察者抽出至少 1/3 卡高。
  static const double _drawDistanceFactor = 0.36;

  /// 抽牌时轻微上提，形成"从牌阵里拿起来"的动作。
  static const double _drawLiftFactor = 0.09;

  /// 抽出后略微放大、回正并散开，悬停位比环形位更醒目。
  static const double _drawScaleFactor = 0.055;
  static const double _drawStraightenFactor = 0.16;
  static const double _drawFanFactor = 0.045;

  /// 抽牌分两段：前 58% 快速离阵并轻微过冲，后 42% 落稳到悬停位。
  static final Animatable<double> _drawSequence = TweenSequence<double>([
    TweenSequenceItem<double>(
      tween: Tween<double>(
        begin: 0,
        end: 1.075,
      ).chain(CurveTween(curve: AppMotion.cardDrawCurve)),
      weight: 58,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(
        begin: 1.075,
        end: 1,
      ).chain(CurveTween(curve: AppMotion.cardSettleCurve)),
      weight: 42,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _auto = AnimationController(vsync: this, duration: widget.period);
    _inertia = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _createDrawControllers();
  }

  void _createDrawControllers() {
    _drawControllers = List<AnimationController>.generate(
      widget.items.length,
      (_) => AnimationController(
        vsync: this,
        duration: AppMotion.cardDraw,
        reverseDuration: AppMotion.cardReturn,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAutoPlay();
  }

  @override
  void didUpdateWidget(OrbitCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      for (final controller in _drawControllers) {
        controller.dispose();
      }
      _createDrawControllers();
      if (_hovered != null && _hovered! >= widget.items.length) {
        _hovered = null;
      }
    }
    if (oldWidget.period != widget.period) {
      _auto.duration = widget.period;
    }
    _syncAutoPlay();
  }

  /// 自动旋转开关：配置关闭、系统要求减少动效、或鼠标悬停时都停。
  void _syncAutoPlay() {
    // 只有"停住不动"才暂停：只是划过不会打断旋转
    final shouldSpin =
        widget.autoPlay && !AppMotion.reduced(context) && !_dwelling;
    if (shouldSpin && !_auto.isAnimating) {
      _auto.repeat();
    } else if (!shouldSpin && _auto.isAnimating) {
      _auto.stop();
    }
  }

  /// 指针一旦移动，就取消"停滞"状态并重新计时；停住超过阈值才真正暂停。
  void _onPointerMove(PointerHoverEvent event) {
    final anchor = _hoverAnchor;
    if (anchor != null &&
        (event.localPosition - anchor).distance < _dwellMoveThreshold) {
      return;
    }
    _hoverAnchor = event.localPosition;
    _dwellTimer?.cancel();
    _setDwelling(false);
    final hovered = _hovered;
    _dwellCandidate = hovered != null && hovered >= 0 ? hovered : null;
    _restartDwellTimer();
  }

  void _restartDwellTimer() {
    _dwellTimer?.cancel();
    _dwellTimer = Timer(_dwellDelay, () {
      _dwellTimer = null;
      // 计时期间指针必须确实从某张卡上开始停滞；空白处停住不影响旋转。
      if (!mounted || _dwellCandidate == null) return;
      _setDwelling(true);
    });
  }

  void _setDwelling(bool value) {
    if (_dwelling == value) return;
    setState(() => _dwelling = value);
    _syncAutoPlay();
  }

  /// 抽牌曲线的瞬时值。正向带轻微过冲，返回时平滑收回。
  double _drawValue(int index) {
    if (index < 0 || index >= _drawControllers.length) return 0;
    final controller = _drawControllers[index];
    final value = controller.value;
    if (value <= 0) return 0;
    if (value >= 1) return 1;
    if (controller.status == AnimationStatus.reverse) {
      return Curves.easeInOutCubic.transform(value);
    }
    return _drawSequence.transform(value);
  }

  void _onCardEnter(int index) {
    setState(() => _hovered = index);
    _dwellCandidate = index;
    if (_dwellTimer == null) _restartDwellTimer();
    final controller = _drawControllers[index];
    if (AppMotion.reduced(context)) {
      controller.value = 1;
    } else if (controller.value < 1) {
      controller.forward();
    }
  }

  void _onCardExit(int index) {
    if (_hovered == index) {
      setState(() => _hovered = -1);
    }
    _releaseDraw(index);
  }

  void _releaseDraw(int index) {
    if (index < 0 || index >= _drawControllers.length) return;
    final controller = _drawControllers[index];
    if (AppMotion.reduced(context)) {
      controller.value = 0;
    } else if (controller.isAnimating || controller.value > 0) {
      controller.reverse();
    }
  }

  void _releaseAllDraws() {
    for (var i = 0; i < _drawControllers.length; i++) {
      _releaseDraw(i);
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    for (final controller in _drawControllers) {
      controller.dispose();
    }
    _auto.dispose();
    _inertia.dispose();
    super.dispose();
  }

  /// 当前拖拽产生的角度（含惯性动画中的瞬时值）。
  double _currentDrag() {
    final t = Curves.easeOutCubic.transform(_inertia.value);
    return _dragAngle + (_inertiaTo - _inertiaFrom) * t;
  }

  void _onDragStart(DragStartDetails _) {
    _dragAngle = _currentDrag();
    _inertia.stop();
    _inertiaFrom = _dragAngle;
    _inertiaTo = _dragAngle;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragAngle += details.delta.dx * _dragToRadians);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx * _dragToRadians;
    // 松手后继续滑行一小段，方向与拖拽一致，距离封顶避免飞太远。
    final travel = (velocity * 0.45).clamp(-1.8, 1.8);
    _inertiaFrom = _dragAngle;
    _inertiaTo = _dragAngle + travel;
    _inertia.forward(from: 0);
  }

  /// 把任意角度归一化到 [-π, π]，方便判断"是不是正面那张"。
  static double _wrap(double radians) {
    var value = radians % (2 * math.pi);
    if (value > math.pi) value -= 2 * math.pi;
    if (value < -math.pi) value += 2 * math.pi;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 窄屏整体等比缩小，保证卡片不会被挤出可视区
        final k = (width / 1080).clamp(0.62, 1.0);
        final cardWidth = widget.cardWidth * k;
        final cardHeight = widget.cardHeight * k;
        final radius = math.min(widget.radius * k, width * 0.31);
        final height = widget.height * (0.72 + 0.28 * k);

        return MouseRegion(
          onHover: _onPointerMove,
          onEnter: (event) {
            _hoverAnchor = event.localPosition;
            setState(() => _hovered = -1);
          },
          onExit: (_) {
            _dwellTimer?.cancel();
            _dwellCandidate = null;
            _hoverAnchor = null;
            setState(() => _hovered = null);
            _setDwelling(false);
            _releaseAllDraws();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _auto,
                  _inertia,
                  ..._drawControllers,
                ]),
                builder: (context, _) {
                  final angle = _auto.value * 2 * math.pi + _currentDrag();
                  final step = 2 * math.pi / widget.items.length;

                  // 先算出每张卡的角度与深度，按深度排序后再绘制：
                  // 这样近处的卡片一定盖住远处的，符合视觉预期。
                  final layers = <_OrbitLayer>[];
                  for (var i = 0; i < widget.items.length; i++) {
                    final raw = i * step + angle;
                    final theta = _wrap(raw);
                    final cos = math.cos(theta);
                    // 转到侧后方就不再绘制，避免看到背面的镜像文字；
                    // 但透明度会在到达阈值前先平滑降到 0，所以循环一圈不会有"突然消失"的跳变
                    if (cos <= _cullCos) continue;
                    final depth = (cos + 1) / 2; // 1 = 正面，0 = 侧面
                    final fade = ((cos - _cullCos) / (_fadeOutCos - _cullCos))
                        .clamp(0.0, 1.0);
                    final pull = _drawValue(i);
                    layers.add(
                      _OrbitLayer(
                        index: i,
                        theta: theta,
                        depth: depth,
                        z: cos + pull * 4,
                        fade: fade,
                        pull: pull,
                      ),
                    );
                  }
                  layers.sort((a, b) => a.z.compareTo(b.z));

                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // 地面：一圈浅色椭圆，让卡片有"站在环形台上"的感觉
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: height * 0.06,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              width: radius * 2.5,
                              height: height * 0.2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.zero,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.13),
                                    const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final layer in layers)
                        _buildCard(
                          layer,
                          cardWidth: cardWidth,
                          cardHeight: cardHeight,
                          radius: radius,
                          height: height,
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _dwelling ? 1 : 0,
                            duration: AppMotion.resolve(
                              context,
                              AppMotion.fast,
                            ),
                            child: const Center(
                              child: Text(
                                '已暂停 · 移动鼠标继续',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF8A8F99),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(
    _OrbitLayer layer, {
    required double cardWidth,
    required double cardHeight,
    required double radius,
    required double height,
  }) {
    final data = widget.items[layer.index];
    final depth = layer.depth;
    final pull = layer.pull;
    final dx = math.sin(layer.theta) * radius;
    // 远处的卡片略微抬高，模拟站在环形台上的透视
    final restDy = -22 * (1 - depth);
    final lift = -cardHeight * _drawLiftFactor * pull;
    final scale = (0.60 + 0.40 * depth) * (1 + _drawScaleFactor * pull);
    final turn = layer.theta * (1 - _drawStraightenFactor * pull);
    final fan = layer.theta * _drawFanFactor * pull;
    final isFront = turn.abs() < 0.42 || pull > 0.55;

    // 抽出的卡片会脱离原本的远近层级，成为最上面、最亮的一张。
    final focusDepth = math
        .max(depth, (depth + 0.36 * pull).clamp(0.0, 1.0))
        .toDouble();

    final visualTransform = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..translateByDouble(0, lift, 0, 1)
      ..rotateY(turn)
      // 沿着卡片自身的朝外方向抽出：至少 1/3 卡高。
      ..translateByDouble(0, 0, -cardHeight * _drawDistanceFactor * pull, 1)
      ..rotateX(-0.045 * pull)
      ..rotateZ(fan)
      ..scaleByDouble(scale, scale, scale, 1);

    // 命中区域固定留在牌阵位置，抽牌过程中的上提/放大不会把鼠标甩出卡片。
    return Transform.translate(
      offset: Offset(dx, restDy),
      child: Opacity(
        opacity: ((0.34 + 0.66 * focusDepth) * layer.fade).clamp(0.0, 1.0),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          // 进入卡片即开始抽出；是否暂停仍由外面的停滞计时器决定。
          onEnter: (_) => _onCardEnter(layer.index),
          onExit: (_) => _onCardExit(layer.index),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOpen(layer.index),
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: visualTransform,
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _OrbitCardSurface(
                            data: data,
                            isFront: isFront,
                            depth: depth,
                            lift: pull,
                          ),
                          // 侧后方的卡片压一层暗色，抽出的悬停卡会同步变亮。
                          IgnorePointer(
                            child: ColoredBox(
                              color: const Color(
                                0xFF070A12,
                              ).withValues(alpha: 0.42 * (1 - focusDepth)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitLayer {
  const _OrbitLayer({
    required this.index,
    required this.theta,
    required this.depth,
    required this.z,
    required this.fade,
    required this.pull,
  });

  final int index;
  final double theta;
  final double depth;
  final double z;

  /// 0 = 刚好要转到背面（全透明），1 = 完全朝向观察者。
  final double fade;

  /// 0 = 仍在环形牌阵，1 = 已完整抽出到悬停位。
  final double pull;
}

/// 卡片本体：渐变海报 + 漆面高光 + 斜向光带 + 细颗粒，直角。
///
/// 材质感来自四层叠加：受光渐变（上亮下暗）→ 顶部镜面反光条 →
/// 斜向高光带 → 细颗粒噪点。颗粒层用 [RepaintBoundary] 缓存，
/// 旋转时不参与逐帧重绘。
class _OrbitCardSurface extends StatelessWidget {
  const _OrbitCardSurface({
    required this.data,
    required this.isFront,
    required this.depth,
    required this.lift,
  });

  final OrbitCardData data;
  final bool isFront;
  final double depth;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final focus = math.max(isFront ? 1.0 : 0.0, lift);
    return DecoratedBox(
      decoration: BoxDecoration(
        // 上亮下暗的三段渐变：模拟有光源从左上打过来的漆面
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(data.color, Colors.white, 0.06 + 0.12 * focus)!,
            data.color,
            Color.lerp(data.color, const Color(0xFF05070E), 0.46)!,
          ],
          stops: const [0, 0.46, 1],
        ),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18 + 0.18 * focus),
        ),
        boxShadow: [
          BoxShadow(
            color: data.color.withValues(
              alpha: (0.32 * depth + 0.22 * lift).clamp(0.0, 1.0),
            ),
            blurRadius: 32 + 20 * lift,
            offset: Offset(0, 16 * depth - 8 * lift),
            spreadRadius: -10 - 2 * lift,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 材质 1：顶部镜面反光条
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.26 + 0.24 * focus),
            ),
          ),
          // 材质 2：斜向高光带（左上更亮，右下有一点回光）
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.20),
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.07),
                ],
                stops: const [0, 0.44, 1],
              ),
            ),
          ),
          // 材质 3：细颗粒噪点
          RepaintBoundary(
            child: CustomPaint(
              painter: _GrainPainter(seed: data.path.hashCode),
            ),
          ),
          // 右下角大号图标水印，增加海报感
          Positioned(
            right: -14,
            bottom: -10,
            child: Icon(
              data.icon,
              size: 132,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.zero,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                        spreadRadius: -3,
                      ),
                    ],
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 24),
                ),
                const Spacer(),
                Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 12.5,
                    height: 1.4,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.22),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 细颗粒：用固定种子生成一批大小不一的亮点/暗点，给平面渐变加"砂面"质感。
class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final light = Paint()..color = Colors.white.withValues(alpha: 0.075);
    final dark = Paint()
      ..color = const Color(0xFF05070E).withValues(alpha: 0.07);

    // 密度随卡片面积走，但设上下限，避免大卡片变糊、小卡片太稀
    final count = (size.width * size.height / 780).round().clamp(48, 150);
    for (var i = 0; i < count; i++) {
      final offset = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(
        offset,
        0.5 + random.nextDouble() * 0.95,
        random.nextBool() ? light : dark,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) => oldDelegate.seed != seed;
}
