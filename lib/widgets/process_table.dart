import 'package:flutter/material.dart';

import '../models/readings.dart';
import '../services/format.dart';
import '../services/process_list.dart';
import '../theme.dart';

/// A paged view of the complete live sample. Controls survive new samples.
class ProcessTable extends StatefulWidget {
  const ProcessTable({super.key, required this.processes});

  final List<ProcessInfo> processes;

  @override
  State<ProcessTable> createState() => _ProcessTableState();
}

class _ProcessTableState extends State<ProcessTable>
    with AutomaticKeepAliveClientMixin<ProcessTable> {
  @override
  bool get wantKeepAlive => true;
  final _search = TextEditingController();
  final _table = GlobalKey<PaginatedDataTableState>();
  final _source = _ProcessSource();
  ProcessFilters _filters = const ProcessFilters();
  ProcessSort _sort = ProcessSort.cpu;
  bool _ascending = false;
  int _pageSize = 10;
  int _firstRow = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(ProcessTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  void _refresh({bool resetPage = false}) {
    _source.update(
      selectProcesses(
        widget.processes,
        query: _search.text,
        filters: _filters,
        sort: _sort,
        ascending: _ascending,
      ),
    );
    if (resetPage || _firstRow >= _source.rowCount) {
      _table.currentState?.pageTo(0);
      _firstRow = 0;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _editFilters() async {
    final result = await showDialog<ProcessFilters>(
      context: context,
      builder: (_) => _FilterDialog(filters: _filters),
    );
    if (!mounted || result == null) return;
    setState(() {
      _filters = result;
      _refresh(resetPage: true);
    });
  }

  void _setSort(ProcessSort field, bool ascending) => setState(() {
    _sort = field;
    _ascending = ascending;
    _refresh(resetPage: true);
  });

  String _sortLabel(ProcessSort field) => switch (field) {
    ProcessSort.rss => 'Memory (RSS)',
    ProcessSort.battery => 'Battery (mAh)',
    _ => field.label,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search processes',
            hintText: 'Name, PID, user, UID or state',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _search.clear();
                      _refresh(resetPage: true);
                    }),
                  ),
          ),
          onChanged: (_) => setState(() => _refresh(resetPage: true)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ProcessSort>(
                    value: _sort,
                    isExpanded: true,
                    items: [
                      for (final field in ProcessSort.values)
                        DropdownMenuItem(
                          value: field,
                          child: Text(
                            _sortLabel(field),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (field) {
                      if (field != null) _setSort(field, _ascending);
                    },
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _setSort(_sort, !_ascending),
              icon: Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              label: Text(_ascending ? 'Ascending' : 'Descending'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _editFilters,
              icon: Icon(
                _filters.active ? Icons.filter_alt : Icons.filter_alt_outlined,
              ),
              label: Text(_filters.active ? 'Filters applied' : 'Filters'),
            ),
            if (_filters.active)
              TextButton(
                onPressed: () => setState(() {
                  _filters = const ProcessFilters();
                  _refresh(resetPage: true);
                }),
                child: const Text('Clear filters'),
              ),
            Text('${_source.rowCount} of ${widget.processes.length} processes'),
          ],
        ),
        Text(
          'Choose a sort field and order, or tap a column heading. Swipe sideways for all columns. RSS is resident memory; mAh is estimated per UID.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_source.rowCount == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              widget.processes.isEmpty
                  ? 'No process readings available yet.'
                  : 'No processes match these filters.',
            ),
          )
        else
          PaginatedDataTable(
            key: _table,
            source: _source,
            sortColumnIndex: _sort.index,
            sortAscending: _ascending,
            rowsPerPage: _pageSize,
            availableRowsPerPage: const [10, 25, 50, 100],
            showEmptyRows: false,
            showFirstLastButtons: true,
            columnSpacing: 20,
            horizontalMargin: 12,
            onRowsPerPageChanged: (value) {
              if (value != null) setState(() => _pageSize = value);
            },
            onPageChanged: (row) => _firstRow = row,
            columns: [
              for (final field in ProcessSort.values)
                DataColumn(
                  label: Text(field.label),
                  numeric: const {
                    ProcessSort.pid,
                    ProcessSort.uid,
                    ProcessSort.cpu,
                    ProcessSort.rss,
                    ProcessSort.battery,
                  }.contains(field),
                  onSort: (_, ascending) => _setSort(field, ascending),
                ),
            ],
          ),
      ],
    );
  }
}

class _ProcessSource extends DataTableSource {
  List<ProcessInfo> _rows = const [];

  void update(List<ProcessInfo> rows) {
    _rows = rows;
    notifyListeners();
  }

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final p = _rows[index];
    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text('${p.pid}')),
        DataCell(
          SizedBox(
            width: 220,
            child: Tooltip(
              message: p.name,
              child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        DataCell(Text(p.user)),
        DataCell(Text('${p.uid ?? '–'}')),
        DataCell(
          Text(
            p.cpuPercent.toStringAsFixed(1),
            style: TextStyle(color: loadColor(p.cpuPercent)),
          ),
        ),
        DataCell(Text(formatBytes(p.rssBytes))),
        DataCell(Text(p.state)),
        DataCell(Text(p.batteryMah?.toStringAsFixed(1) ?? '–')),
      ],
    );
  }

  @override
  int get rowCount => _rows.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.filters});
  final ProcessFilters filters;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _text;
  late final Map<String, (TextEditingController, TextEditingController)>
  _ranges;

  @override
  void initState() {
    super.initState();
    final f = widget.filters;
    _text = {
      'Name contains': TextEditingController(text: f.name),
      'User contains': TextEditingController(text: f.user),
      'State contains': TextEditingController(text: f.state),
    };
    _ranges = {
      for (final entry in {
        'PID': f.pid,
        'UID': f.uid,
        'CPU %': f.cpu,
        'RSS (MiB)': f.rssMiB,
        'Battery (mAh)': f.battery,
      }.entries)
        entry.key: (
          TextEditingController(text: entry.value.min?.toString() ?? ''),
          TextEditingController(text: entry.value.max?.toString() ?? ''),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    for (final pair in _ranges.values) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
    super.dispose();
  }

  String? _validate(String? input, {required bool integer}) {
    if (input == null || input.trim().isEmpty) return null;
    final number = num.tryParse(input.trim());
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        (integer && number != number.roundToDouble())) {
      return integer
          ? 'Enter a non-negative whole number'
          : 'Enter a non-negative number';
    }
    return null;
  }

  ProcessRange _range(String label) {
    final pair = _ranges[label]!;
    return ProcessRange(
      min: num.tryParse(pair.$1.text.trim()),
      max: num.tryParse(pair.$2.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filter processes'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filters combine. Leave a bound blank for no limit. Missing readings do not match a numeric filter.',
              ),
              for (final entry in _text.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: entry.value,
                    decoration: InputDecoration(labelText: entry.key),
                  ),
                ),
              for (final entry in _ranges.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final isMin in [true, false]) ...[
                        if (!isMin) const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: isMin ? entry.value.$1 : entry.value.$2,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  '${isMin ? 'Min' : 'Max'} ${entry.key}',
                            ),
                            validator: (value) {
                              final error = _validate(
                                value,
                                integer:
                                    entry.key == 'PID' || entry.key == 'UID',
                              );
                              if (error != null) return error;
                              if (!isMin && !_range(entry.key).valid) {
                                return 'Maximum must be at least minimum';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _form.currentState?.reset();
          for (final c in _text.values) {
            c.clear();
          }
          for (final pair in _ranges.values) {
            pair.$1.clear();
            pair.$2.clear();
          }
        },
        child: const Text('Reset'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            ProcessFilters(
              name: _text['Name contains']!.text,
              user: _text['User contains']!.text,
              state: _text['State contains']!.text,
              pid: _range('PID'),
              uid: _range('UID'),
              cpu: _range('CPU %'),
              rssMiB: _range('RSS (MiB)'),
              battery: _range('Battery (mAh)'),
            ),
          );
        },
        child: const Text('Apply'),
      ),
    ],
  );
}
