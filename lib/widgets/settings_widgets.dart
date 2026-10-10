import 'package:flutter/material.dart';

/// Section title in a settings list.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

/// A compact dropdown for a small set of values.
class ChoiceDropdown<T> extends StatelessWidget {
  const ChoiceDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<T>(
    value: options.contains(value) ? value : options.first,
    underline: const SizedBox.shrink(),
    items: [
      for (final o in options)
        DropdownMenuItem(value: o, child: Text(label(o))),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}
