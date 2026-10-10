import 'package:flutter/material.dart';

import '../theme.dart';

/// A labelled horizontal bar, like one row of htop's header.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.label,
    required this.percent,
    this.trailing,
    this.color,
    this.labelWidth = 44,
  });

  final String label;
  final double? percent;
  final String? trailing;
  final Color? color;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = percent;
    return Semantics(
      label:
          '$label ${trailing ?? (value == null ? 'unknown' : '${value.round()} percent')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(label, style: theme.textTheme.labelMedium),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value == null ? 0 : (value / 100).clamp(0, 1),
                  minHeight: 10,
                  color: color ?? loadColor(value),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(
                trailing ??
                    (value == null ? '–' : '${value.toStringAsFixed(0)} %'),
                textAlign: TextAlign.end,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
