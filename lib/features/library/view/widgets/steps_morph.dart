import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The three steps of a scan, laid out two ways and anything in between. Running, they go down a rail with their words
/// beside them. Stopped, a header sits on top and they go side by side along a line with their words under them.
///
/// [progress] runs from 0 for the rail to 1 for the row. The circles, the edges between them and the words all move from
/// one place to the other, so the card changes shape instead of swapping one picture for another. Words that only one of
/// the two layouts has fade out or in on the way.
class StepsMorph extends MultiChildRenderObjectWidget {
  StepsMorph({
    super.key,
    required this.progress,
    required Widget header,
    required List<Widget> nodes,
    required List<Widget> titles,
    required List<Widget> details,
    required List<Widget> extras,
    required List<Widget> rowTitles,
    required List<Widget> rowDetails,
    required List<Widget> edges,
  }) : assert(nodes.length == stepCount && edges.length == stepCount - 1),
       super(
         children: [
           header,
           for (var i = 0; i < stepCount; i++) ...[nodes[i], titles[i], details[i], extras[i], rowTitles[i], rowDetails[i]],
           ...edges,
         ],
       );

  static const stepCount = 3;

  /// The width and height of a circle, which the layouts are built around.
  static const nodeSize = 46.0;

  final Animation<double> progress;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderStepsMorph(progress);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderStepsMorph).progress = progress;
  }
}

class _MorphParentData extends ContainerBoxParentData<RenderBox> {}

/// Where each child sits in the list the widget gives.
abstract final class _Slot {
  static const header = 0;
  static const perStep = 6;
  static int node(int i) => 1 + i * perStep;
  static int title(int i) => 2 + i * perStep;
  static int detail(int i) => 3 + i * perStep;
  static int extra(int i) => 4 + i * perStep;
  static int rowTitle(int i) => 5 + i * perStep;
  static int rowDetail(int i) => 6 + i * perStep;
  static int edge(int i) => 1 + StepsMorph.stepCount * perStep + i;
  static const count = 1 + StepsMorph.stepCount * perStep + StepsMorph.stepCount - 1;
}

const _nodeSize = StepsMorph.nodeSize;
const _steps = StepsMorph.stepCount;

/// The room beside a circle for its words, and the gap above the words that sit under it.
const _textLeft = _nodeSize + 12;
const _textTop = 8.0;
const _titleGap = 2.0;
const _rowGap = 20.0;
const _underNodeGap = 8.0;

/// How tall a step is at least on the rail, so the circles keep an even distance and a step only grows when its words
/// need the room, as at a large text size.
const _stepHeight = 86.0;

/// The gap left between a circle and the edge that leaves it.
const _edgeGap = 4.0;

const _edgeThickness = 2.0;

typedef _Layouter = Size Function(RenderBox child, BoxConstraints constraints);

/// What was measured of the children: the same in every frame of the change, as the words keep their widths.
class _Metrics {
  _Metrics(this.width);

  final double width;
  double headerHeight = 0;
  double railHeight = 0;
  double rowHeight = 0;
  double rowTop = 0;
  final stepTop = List<double>.filled(_steps, 0);
  final titleHeight = List<double>.filled(_steps, 0);
  final detailHeight = List<double>.filled(_steps, 0);
  final extraHeight = List<double>.filled(_steps, 0);
  final rowTitleHeight = List<double>.filled(_steps, 0);

  double get column => width / _steps;
  double get textWidth => math.max(0, width - _textLeft);
}

class _RenderStepsMorph extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _MorphParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _MorphParentData> {
  _RenderStepsMorph(this._progress);

  Animation<double> _progress;

  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(markNeedsLayout);
    _progress = value;
    if (attached) _progress.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  final _alpha = List<double>.filled(_Slot.count, 1);
  final _edgeStart = List<Offset>.filled(_steps - 1, Offset.zero);
  final _edgeAngle = List<double>.filled(_steps - 1, 0);
  List<RenderBox> _kids = const [];

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MorphParentData) child.parentData = _MorphParentData();
  }

  List<RenderBox> _children() {
    final list = <RenderBox>[];
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      list.add(child);
    }
    return list;
  }

  _Metrics _measure(BoxConstraints constraints, List<RenderBox> kids, _Layouter layout) {
    final m = _Metrics(constraints.maxWidth);
    final inRail = BoxConstraints(minWidth: m.textWidth, maxWidth: m.textWidth);
    final inColumn = BoxConstraints(minWidth: m.column, maxWidth: m.column);
    m.headerHeight = layout(kids[_Slot.header], BoxConstraints(minWidth: m.width, maxWidth: m.width)).height;
    var y = 0.0;
    var tallestUnder = 0.0;
    for (var i = 0; i < _steps; i++) {
      layout(kids[_Slot.node(i)], BoxConstraints.tight(const Size.square(_nodeSize)));
      m.titleHeight[i] = layout(kids[_Slot.title(i)], inRail).height;
      m.detailHeight[i] = layout(kids[_Slot.detail(i)], inRail).height;
      m.extraHeight[i] = layout(kids[_Slot.extra(i)], inRail).height;
      m.rowTitleHeight[i] = layout(kids[_Slot.rowTitle(i)], inColumn).height;
      final rowDetail = layout(kids[_Slot.rowDetail(i)], inColumn).height;
      tallestUnder = math.max(tallestUnder, m.rowTitleHeight[i] + _titleGap + rowDetail);
      final words = _textTop + m.titleHeight[i] + _titleGap + m.detailHeight[i] + m.extraHeight[i];
      m.stepTop[i] = y;
      y += math.max(i < _steps - 1 ? _stepHeight : 0, math.max(_nodeSize, words));
    }
    m.railHeight = y;
    m.rowTop = m.headerHeight + _rowGap;
    m.rowHeight = m.rowTop + _nodeSize + _underNodeGap + tallestUnder;
    return m;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final m = _measure(constraints, _children(), ChildLayoutHelper.dryLayoutChild);
    final e = Curves.easeInOutCubic.transform(_progress.value.clamp(0.0, 1.0));
    return constraints.constrain(Size(m.width, lerpDouble(m.railHeight, m.rowHeight, e)!));
  }

  @override
  void performLayout() {
    final kids = _kids = _children();
    final m = _measure(constraints, kids, ChildLayoutHelper.layoutChild);
    final t = _progress.value.clamp(0.0, 1.0);
    final e = Curves.easeInOutCubic.transform(t);
    size = constraints.constrain(Size(m.width, lerpDouble(m.railHeight, m.rowHeight, e)!));

    final leaving = 1 - _fraction(t, 0, 0.4);
    final arriving = _fraction(t, 0.5, 1);
    final headerIn = _fraction(t, 0.6, 1);

    void place(int slot, Offset at, double alpha) {
      (kids[slot].parentData! as _MorphParentData).offset = at;
      _alpha[slot] = alpha;
    }

    Offset between(Offset a, Offset b) => Offset.lerp(a, b, e)!;

    place(_Slot.header, between(const Offset(0, -12), Offset.zero), headerIn);

    final centers = <Offset>[];
    for (var i = 0; i < _steps; i++) {
      final top = m.stepTop[i];
      final underX = m.column * i;
      final underY = m.rowTop + _nodeSize + _underNodeGap;
      final node = between(Offset(0, top), Offset(underX + (m.column - _nodeSize) / 2, m.rowTop));
      centers.add(node + const Offset(_nodeSize / 2, _nodeSize / 2));
      place(_Slot.node(i), node, 1);

      final titleAt = top + _textTop;
      final detailAt = titleAt + m.titleHeight[i] + _titleGap;
      place(_Slot.title(i), between(Offset(_textLeft, titleAt), Offset(underX, underY)), leaving);
      place(
        _Slot.detail(i),
        between(Offset(_textLeft, detailAt), Offset(underX, underY + m.rowTitleHeight[i] + _titleGap)),
        leaving,
      );
      place(
        _Slot.extra(i),
        between(Offset(_textLeft, detailAt + m.detailHeight[i]), Offset(underX, underY + m.rowTitleHeight[i] + _titleGap)),
        leaving,
      );
      place(_Slot.rowTitle(i), between(Offset(_textLeft, titleAt), Offset(underX, underY)), arriving);
      place(
        _Slot.rowDetail(i),
        between(Offset(_textLeft, detailAt), Offset(underX, underY + m.rowTitleHeight[i] + _titleGap)),
        arriving,
      );
    }

    for (var i = 0; i < _steps - 1; i++) {
      final apart = centers[i + 1] - centers[i];
      final distance = apart.distance;
      final along = distance == 0 ? const Offset(0, 1) : apart / distance;
      final reach = _nodeSize / 2 + _edgeGap;
      final length = math.max(0.0, distance - 2 * reach);
      kids[_Slot.edge(i)].layout(BoxConstraints.tight(Size(_edgeThickness, length)));
      _edgeStart[i] = centers[i] + along * reach;
      _edgeAngle[i] = math.atan2(-along.dx, along.dy);
      (kids[_Slot.edge(i)].parentData! as _MorphParentData).offset = _edgeStart[i];
      _alpha[_Slot.edge(i)] = 1;
    }
  }

  static double _fraction(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var slot = 0; slot < _kids.length; slot++) {
      final alpha = _alpha[slot];
      if (alpha <= 0.003) continue;
      final child = _kids[slot];
      final isEdge = slot >= _Slot.edge(0);
      void draw(PaintingContext inner, Offset at) {
        if (isEdge) {
          final i = slot - _Slot.edge(0);
          final turn = Matrix4.translationValues(_edgeStart[i].dx, _edgeStart[i].dy, 0)..rotateZ(_edgeAngle[i]);
          inner.pushTransform(
            needsCompositing,
            at,
            turn,
            (rotated, spot) => rotated.paintChild(child, spot + const Offset(-_edgeThickness / 2, 0)),
          );
        } else {
          inner.paintChild(child, at + (child.parentData! as _MorphParentData).offset);
        }
      }

      if (alpha >= 0.997) {
        draw(context, offset);
      } else {
        context.pushOpacity(offset, (alpha * 255).round(), draw);
      }
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
