import 'package:flutter/widgets.dart';

class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({super.key, required this.index, required this.itemCount, required this.itemBuilder});

  final int index;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late List<Widget?> _children;

  @override
  void initState() {
    super.initState();
    _children = List<Widget?>.filled(widget.itemCount, null);
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      _children = List<Widget?>.generate(widget.itemCount, (index) => index < oldWidget.itemCount ? _children[index] : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.index >= 0 && widget.index < widget.itemCount);
    _children[widget.index] ??= widget.itemBuilder(context, widget.index);
    return IndexedStack(
      index: widget.index,
      children: List<Widget>.generate(widget.itemCount, (index) => _children[index] ?? const SizedBox.shrink()),
    );
  }
}
