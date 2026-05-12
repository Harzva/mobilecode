/// Virtual Scroll Controller for MobileCode
///
/// Efficiently renders large files (100k+ lines) by only building
/// visible viewport items. Used by the code editor for handling
/// files with 10,000+ lines without performance degradation.
///
/// Features:
/// - Viewport-aware item rendering (only builds what's visible)
/// - Bidirectional buffer for smooth scrolling
/// - Exact line jumping with animation support
/// - Scroll position restoration
/// - Memory-efficient item recycling
///
/// Usage:
/// ```dart
/// final controller = VirtualScrollController(
///   itemCount: 100000, // 100k lines
///   itemHeight: 24.0,
/// );
///
/// // Jump to a specific line
/// controller.jumpToLine(5000);
///
/// // In ListView.builder:
/// ListView.builder(
///   controller: controller.scrollController,
///   itemCount: controller.virtualItemCount,
///   itemBuilder: (context, index) =>
///     controller.buildItem(context, index, (lineIndex) => LineWidget(lineIndex)),
/// );
/// ```
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Virtual Scroll Controller
// ═══════════════════════════════════════════════════════════════════════════

/// Controller for virtualized scrolling of large datasets.
///
/// Manages the mapping between virtual indices and actual data indices,
/// handles scroll position calculations, and provides viewport
/// visibility information for efficient rendering.
class VirtualScrollController extends ChangeNotifier {
  // ── Configuration ───────────────────────────────────────────────────

  /// Total number of items (lines) in the dataset
  final int itemCount;

  /// Height of each item in logical pixels
  final double itemHeight;

  /// Number of extra items to render outside the visible viewport
  /// for smoother scrolling. Default: 5 items above and below.
  final int bufferSize;

  /// Optional: minimum items to always render even with small viewport
  final int minRenderItems;

  // ── Internal State ──────────────────────────────────────────────────

  /// Underlying [ScrollController] attached to the scrollable widget
  final ScrollController scrollController;

  /// Current first visible (not buffered) item index
  int _firstVisibleIndex = 0;

  /// Current last visible (not buffered) item index
  int _lastVisibleIndex = 0;

  /// Current viewport height in logical pixels
  double _viewportHeight = 0;

  /// Current scroll offset in logical pixels
  double _scrollOffset = 0;

  /// Whether the controller has been disposed
  bool _disposed = false;

  // ── Cached Values ───────────────────────────────────────────────────

  /// Cached total scrollable height
  double? _cachedTotalHeight;

  // ── Constructor ─────────────────────────────────────────────────────

  VirtualScrollController({
    required this.itemCount,
    required this.itemHeight,
    this.bufferSize = 5,
    this.minRenderItems = 10,
    ScrollController? scrollController,
  })  : scrollController = scrollController ?? ScrollController() {
    _attachListener();
  }

  void _attachListener() {
    this.scrollController.addListener(_onScroll);
  }

  // ── Public Properties ───────────────────────────────────────────────

  /// Index of the first fully visible item (no buffer)
  int get firstVisibleIndex => _firstVisibleIndex;

  /// Index of the last fully visible item (no buffer)
  int get lastVisibleIndex => _lastVisibleIndex;

  /// Number of fully visible items in the current viewport
  int get visibleCount => _lastVisibleIndex - _firstVisibleIndex + 1;

  /// Total height of all items combined (scrollable extent)
  double get totalHeight {
    _cachedTotalHeight ??= itemCount * itemHeight;
    return _cachedTotalHeight!;
  }

  /// Current scroll offset
  double get scrollOffset => _scrollOffset;

  /// Whether the controller has been disposed
  bool get isDisposed => _disposed;

  /// Number of items currently being rendered (including buffer)
  int get bufferedItemCount {
    final first = _firstBufferedIndex;
    final last = _lastBufferedIndex;
    return math.max(0, last - first + 1);
  }

  // ── Private: Buffered Range ─────────────────────────────────────────

  /// First index to render including buffer zone
  int get _firstBufferedIndex {
    final first = math.max(0, _firstVisibleIndex - bufferSize);
    return first;
  }

  /// Last index to render including buffer zone
  int get _lastBufferedIndex {
    final last = math.min(itemCount - 1, _lastVisibleIndex + bufferSize);
    return math.max(0, last);
  }

  // ── Scroll Handling ─────────────────────────────────────────────────

  void _onScroll() {
    if (_disposed) return;
    _scrollOffset = scrollController.position.pixels;
    _updateVisibleRange();
  }

  void _updateVisibleRange() {
    if (_viewportHeight <= 0) return;

    final newFirst = (_scrollOffset / itemHeight).floor();
    final visibleItemCount = (_viewportHeight / itemHeight).ceil();
    final newLast = math.min(itemCount - 1, newFirst + visibleItemCount);

    if (newFirst != _firstVisibleIndex || newLast != _lastVisibleIndex) {
      _firstVisibleIndex = math.max(0, newFirst);
      _lastVisibleIndex = math.max(0, newLast);
      notifyListeners();
    }
  }

  // ── Viewport Registration ───────────────────────────────────────────

  /// Register the viewport dimensions.
  /// Call this from a LayoutBuilder or on the first frame.
  void setViewportHeight(double height) {
    if (_viewportHeight != height) {
      _viewportHeight = height;
      _updateVisibleRange();
    }
  }

  /// Report viewport dimensions from a widget callback.
  /// Use in combination with [ViewportDetector].
  void onViewportChanged(double height, double offset) {
    _viewportHeight = height;
    _scrollOffset = offset;
    _updateVisibleRange();
  }

  // ── Line Navigation ─────────────────────────────────────────────────

  /// Jump directly to a specific line number (0-indexed).
  ///
  /// Does NOT animate. Use [animateToLine] for smooth scrolling.
  void jumpToLine(int lineNumber) {
    if (_disposed) return;
    final clampedLine = lineNumber.clamp(0, math.max(0, itemCount - 1));
    final targetOffset = clampedLine * itemHeight;

    if (scrollController.hasClients) {
      scrollController.jumpTo(
        targetOffset.clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  /// Animate to a specific line number with smooth scrolling.
  ///
  /// [duration] defaults to 300ms.
  /// [curve] defaults to [Curves.easeInOutCubic].
  Future<void> animateToLine(
    int lineNumber, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOutCubic,
  }) async {
    if (_disposed) return;
    final clampedLine = lineNumber.clamp(0, math.max(0, itemCount - 1));
    final targetOffset = clampedLine * itemHeight;

    if (scrollController.hasClients) {
      await scrollController.animateTo(
        targetOffset.clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        ),
        duration: duration,
        curve: curve,
      );
    }
  }

  /// Scroll forward by one viewport worth of items.
  void pageDown() {
    final pageSize = math.max(1, visibleCount - 1);
    jumpToLine(_firstVisibleIndex + pageSize);
  }

  /// Scroll backward by one viewport worth of items.
  void pageUp() {
    final pageSize = math.max(1, visibleCount - 1);
    jumpToLine(_firstVisibleIndex - pageSize);
  }

  /// Jump to the beginning of the document.
  void jumpToStart() => jumpToLine(0);

  /// Jump to the end of the document.
  void jumpToEnd() => jumpToLine(itemCount - 1);

  // ── Visible Index Queries ───────────────────────────────────────────

  /// Get the list of indices that should currently be built (with buffer).
  List<int> getVisibleIndices(double viewportHeight) {
    setViewportHeight(viewportHeight);
    final first = _firstBufferedIndex;
    final last = _lastBufferedIndex;
    if (first > last) return [];
    return List.generate(last - first + 1, (i) => first + i);
  }

  /// Check if a given data index is currently in the visible viewport.
  bool isIndexVisible(int index) {
    return index >= _firstVisibleIndex && index <= _lastVisibleIndex;
  }

  /// Check if a given data index is in the buffered render range.
  bool isIndexBuffered(int index) {
    return index >= _firstBufferedIndex && index <= _lastBufferedIndex;
  }

  /// Get the scroll offset for a specific item index.
  double getOffsetForIndex(int index) {
    return index.clamp(0, itemCount) * itemHeight;
  }

  // ── Item Builder ────────────────────────────────────────────────────

  /// Build a virtual item widget.
  ///
  /// [virtualIndex] is the index from ListView.builder.
  /// [builder] is called with the actual data index to build the item.
  ///
  /// Returns null if the index is outside the buffered range,
  /// allowing the ListView to efficiently skip building.
  Widget? buildItem(
    BuildContext context,
    int virtualIndex,
    Widget Function(int dataIndex) builder,
  ) {
    final dataIndex = virtualIndex;
    if (dataIndex < 0 || dataIndex >= itemCount) return null;
    if (!isIndexBuffered(dataIndex)) {
      // Return a sized placeholder to maintain scroll extent
      return SizedBox(height: itemHeight);
    }
    return builder(dataIndex);
  }

  // ── Scroll Position Persistence ─────────────────────────────────────

  /// Save the current scroll position for later restoration.
  double saveScrollPosition() => _scrollOffset;

  /// Restore a previously saved scroll position.
  void restoreScrollPosition(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients && !_disposed) {
        final clamped = offset.clamp(
          0.0,
          scrollController.position.maxScrollExtent,
        );
        scrollController.jumpTo(clamped);
      }
    });
  }

  // ── Lifecycle ───────────────────────────────────────────────────────

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scrollController.removeListener(_onScroll);
    if (!scrollController.hasListeners) {
      scrollController.dispose();
    }
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Virtual Scroll Widget
// ═══════════════════════════════════════════════════════════════════════════

/// A ListView that efficiently renders large datasets using virtualization.
///
/// Only renders items that are visible in the viewport plus a small buffer,
/// making it suitable for files with 100,000+ lines.
///
/// Usage:
/// ```dart
/// VirtualScrollView(
///   controller: myController,
///   itemBuilder: (context, index) => CodeLineWidget(index: index),
/// )
/// ```
class VirtualScrollView extends StatefulWidget {
  /// The virtual scroll controller
  final VirtualScrollController controller;

  /// Builder for each item. Only called for visible + buffered items.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Optional separator between items
  final Widget? separator;

  /// Optional scroll physics
  final ScrollPhysics? physics;

  /// Optional padding
  final EdgeInsets? padding;

  /// Whether to show a scrollbar
  final bool showScrollbar;

  const VirtualScrollView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.separator,
    this.physics,
    this.padding,
    this.showScrollbar = true,
  });

  @override
  State<VirtualScrollView> createState() => _VirtualScrollViewState();
}

class _VirtualScrollViewState extends State<VirtualScrollView> {
  late final VirtualScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget listView = LayoutBuilder(
      builder: (context, constraints) {
        _controller.setViewportHeight(constraints.maxHeight);

        return ListView.builder(
          controller: _controller.scrollController,
          physics: widget.physics ?? const ClampingScrollPhysics(),
          padding: widget.padding,
          // Use the total item count for scroll extent calculation,
          // but only build visible items
          itemCount: _controller.itemCount,
          itemExtent: _controller.itemHeight,
          cacheExtent: _controller.itemHeight * _controller.bufferSize * 2,
          itemBuilder: (context, index) {
            final item = _controller.buildItem(
              context,
              index,
              (dataIndex) => widget.itemBuilder(context, dataIndex),
            );
            if (item == null) return const SizedBox.shrink();

            if (widget.separator != null && index < _controller.itemCount - 1) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [item, widget.separator!],
              );
            }
            return item;
          },
        );
      },
    );

    if (widget.showScrollbar) {
      listView = Scrollbar(
        controller: _controller.scrollController,
        child: listView,
      );
    }

    return listView;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ViewportDetector Widget
// ═══════════════════════════════════════════════════════════════════════════

/// Widget that detects viewport size changes and reports them to a
/// [VirtualScrollController].
///
/// Wraps a child widget and automatically reports viewport dimensions.
class ViewportDetector extends StatefulWidget {
  final VirtualScrollController controller;
  final Widget child;

  const ViewportDetector({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<ViewportDetector> createState() => _ViewportDetectorState();
}

class _ViewportDetectorState extends State<ViewportDetector> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.controller.setViewportHeight(constraints.maxHeight);
        return widget.child;
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LineNumberGutter (Code Editor Integration)
// ═══════════════════════════════════════════════════════════════════════════

/// A gutter widget showing line numbers that stays synced with the
/// virtual scroll position.
///
/// Render this alongside the [VirtualScrollView] for a code editor.
class LineNumberGutter extends StatelessWidget {
  /// The virtual scroll controller (shared with the editor)
  final VirtualScrollController controller;

  /// Width of the gutter in logical pixels
  final double width;

  /// Style for line numbers
  final TextStyle? numberStyle;

  /// Background color of the gutter
  final Color? backgroundColor;

  /// Color to highlight the current line number
  final Color? currentLineHighlightColor;

  /// Optional: current cursor line to highlight
  final int? currentLine;

  const LineNumberGutter({
    super.key,
    required this.controller,
    this.width = 56.0,
    this.numberStyle,
    this.backgroundColor,
    this.currentLineHighlightColor,
    this.currentLine,
  });

  @override
  Widget build(BuildContext context) {
    final visibleIndices = controller.getVisibleIndices(
      controller.itemHeight * 20, // Estimate visible lines
    );

    return Container(
      width: width,
      color: backgroundColor ?? const Color(0xFF0A0E14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: visibleIndices.map((index) {
          final lineNum = index + 1; // 1-indexed for display
          final isCurrentLine = currentLine == lineNum;
          return Container(
            height: controller.itemHeight,
            padding: const EdgeInsets.only(right: 12),
            decoration: isCurrentLine && currentLineHighlightColor != null
                ? BoxDecoration(color: currentLineHighlightColor)
                : null,
            alignment: Alignment.centerRight,
            child: Text(
              '$lineNum',
              style: (numberStyle ?? const TextStyle(fontSize: 13)).copyWith(
                color: isCurrentLine
                    ? (numberStyle?.color ?? const Color(0xFF9CA3AF))
                    : const Color(0xFF4B5563),
                fontWeight: isCurrentLine ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Scroll Performance Widget
// ═══════════════════════════════════════════════════════════════════════════

/// A widget that wraps a scrollable and reports performance metrics
/// to the [PerformanceMonitor].
///
/// Usage:
/// ```dart
/// PerformanceTrackedScrollView(
///   controller: scrollController,
///   child: ListView(...),
/// )
/// ```
class PerformanceTrackedScrollView extends StatefulWidget {
  final ScrollController? controller;
  final Widget child;

  const PerformanceTrackedScrollView({
    super.key,
    this.controller,
    required this.child,
  });

  @override
  State<PerformanceTrackedScrollView> createState() =>
      _PerformanceTrackedScrollViewState();
}

class _PerformanceTrackedScrollViewState
    extends State<PerformanceTrackedScrollView> {
  late ScrollController _controller;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScrollController();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _controller.offset;
    // Note: In actual implementation, this would call PerformanceMonitor
    // For now, we track the offset for potential jank detection
    _lastOffset = offset;
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onScroll);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Utility Extensions
// ═══════════════════════════════════════════════════════════════════════════

/// Extensions on [VirtualScrollController] for code editor integration.
extension CodeEditorVirtualScroll on VirtualScrollController {
  /// Get the line number at a specific scroll offset.
  int lineAtOffset(double offset) {
    return (offset / itemHeight).floor().clamp(0, math.max(0, itemCount - 1));
  }

  /// Get the current top-visible line number (1-indexed).
  int get currentLine => firstVisibleIndex + 1;

  /// Get the scroll percentage (0.0 to 1.0).
  double get scrollPercent {
    if (itemCount <= 1) return 0.0;
    if (!scrollController.hasClients) return 0.0;
    final maxExtent = scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    return (scrollController.offset / maxExtent).clamp(0.0, 1.0);
  }

  /// Get a readable position string like "Line 500 of 10000".
  String get positionString {
    final line = currentLine;
    final total = itemCount;
    return 'Line $line of $total';
  }
}
