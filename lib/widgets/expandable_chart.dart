import 'package:flutter/material.dart';

/// A chart with an explicit expand button. The full-screen route subscribes
/// independently, so sampling continues to appear while the source is covered.
class ExpandableChart extends StatelessWidget {
  const ExpandableChart({
    super.key,
    required this.title,
    required this.listenable,
    required this.height,
    required this.builder,
    this.detailsBuilder,
  });

  final String title;
  final Listenable listenable;
  final double height;
  final Widget Function(BuildContext context, Size size, bool expanded) builder;
  final WidgetBuilder? detailsBuilder;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          builder(context, Size(box.maxWidth, height), false),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filledTonal(
              tooltip: 'Expand $title',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.fullscreen, size: 20),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => _ChartViewer(
                    title: title,
                    listenable: listenable,
                    builder: builder,
                    detailsBuilder: detailsBuilder,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChartViewer extends StatefulWidget {
  const _ChartViewer({
    required this.title,
    required this.listenable,
    required this.builder,
    this.detailsBuilder,
  });

  final String title;
  final Listenable listenable;
  final Widget Function(BuildContext context, Size size, bool expanded) builder;
  final WidgetBuilder? detailsBuilder;

  @override
  State<_ChartViewer> createState() => _ChartViewerState();
}

class _ChartViewerState extends State<_ChartViewer> {
  final _transformation = TransformationController();

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Close chart',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Reset zoom',
          icon: const Icon(Icons.zoom_out_map),
          onPressed: () => _transformation.value = Matrix4.identity(),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => InteractiveViewer(
                  transformationController: _transformation,
                  minScale: 1,
                  maxScale: 8,
                  child: SizedBox(
                    width: box.maxWidth,
                    height: box.maxHeight,
                    child: ListenableBuilder(
                      listenable: widget.listenable,
                      builder: (context, _) => widget.builder(
                        context,
                        Size(box.maxWidth, box.maxHeight),
                        true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.detailsBuilder != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 96),
                child: SingleChildScrollView(
                  child: ListenableBuilder(
                    listenable: widget.listenable,
                    builder: (context, _) => widget.detailsBuilder!(context),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Pinch to zoom · drag to pan',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
