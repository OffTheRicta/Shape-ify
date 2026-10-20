import 'package:flutter/material.dart';

/// Keep the current action in the same place at the top of each workflow.
/// A new step returns to the top; ordinary status updates preserve the user's
/// scroll position so incoming readings never interrupt inspection.
class ActionFirstScroll extends StatefulWidget {
  final String? actionId;
  final Widget Function(ScrollController controller) builder;
  const ActionFirstScroll({super.key, required this.actionId,
    required this.builder});
  @override State<ActionFirstScroll> createState() => _ActionFirstScrollState();
}

class _ActionFirstScrollState extends State<ActionFirstScroll> {
  final controller = ScrollController();

  @override void didUpdateWidget(covariant ActionFirstScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.actionId != oldWidget.actionId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpTo(0);
      });
    }
  }

  @override void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) => widget.builder(controller);
}
