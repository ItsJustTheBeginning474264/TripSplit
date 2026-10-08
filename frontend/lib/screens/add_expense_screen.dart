import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';

/// Screen 10 - Add expense (also used to edit an existing expense).
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, required this.tripId, this.existing});

  final int tripId;
  final Expense? existing;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final Map<int, TextEditingController> _customCtrls = {};
  final Map<int, TextEditingController> _pctCtrls = {};
  final Set<int> _selected = {};

  List<Member> _members = [];
  bool _loading = true;
  String? _loadError;
  bool _busy = false;

  String _category = 'Food';
  String _splitType = 'equal';
  int? _paidBy;
  DateTime _date = DateTime.now();

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {})); // live remaining / preview
    _loadMembers();
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final c in [..._customCtrls.values, ..._pctCtrls.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await context.api.get('/api/trips/${widget.tripId}/members');
      if (!mounted) return;
      final members = (res['members'] as List).map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
      for (final m in members) {
        _customCtrls.putIfAbsent(m.id, () => TextEditingController()..addListener(_rebuild));
        _pctCtrls.putIfAbsent(m.id, () => TextEditingController()..addListener(_rebuild));
      }
      final e = widget.existing;
      if (e != null) {
        _description.text = e.description;
        _amount.text = e.amount.toStringAsFixed(2);
        _category = e.category;
        _splitType = e.splitType;
        _paidBy = e.paidBy;
        _date = e.date;
        for (final s in e.splits) {
          _selected.add(s.userId);
          _customCtrls[s.userId]?.text = s.amount.toStringAsFixed(2);
          if (s.percentage != null) _pctCtrls[s.userId]?.text = s.percentage!.toString();
        }
      } else {
        _paidBy = context.auth.user?.id;
        _selected.addAll(members.map((m) => m.id)); // everyone participates by default
      }
      _members = members;
    } catch (err) {
      _loadError = err.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // ---- calculations (all in paise so the totals can be compared exactly) ----
  int? get _totalPaise {
    final a = parseAmount(_amount.text);
    return (a == null || a <= 0) ? null : toPaise(a);
  }

  List<Member> get _participants => _members.where((m) => _selected.contains(m.id)).toList();

  int? _paiseOf(TextEditingController c) {
    final v = parseAmount(c.text);
    return v == null ? null : toPaise(v);
  }

  int _customSum() => _participants.fold(0, (sum, m) => sum + (_paiseOf(_customCtrls[m.id]!) ?? 0));

  /// Percentage in hundredths of a percent (33.33 -> 3333), null if invalid.
  int? _pctHundredths(TextEditingController c) {
    final t = c.text.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
    return (double.parse(t) * 100).round();
  }

  int _pctSum() => _participants.fold(0, (sum, m) => sum + (_pctHundredths(_pctCtrls[m.id]!) ?? 0));

  /// Equal-split preview identical to the server's rule: remainder paise go to the first people.
  Map<int, int> _equalShares() {
    final total = _totalPaise;
    final people = _participants;
    if (total == null || people.isEmpty) return {};
    final base = total ~/ people.length;
    final rem = total % people.length;
    return {for (var i = 0; i < people.length; i++) people[i].id: base + (i < rem ? 1 : 0)};
  }

  double _fromPaise(int p) => p / 100.0;

  // ---- UI actions ----
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  String? _splitProblem() {
    if (_participants.isEmpty) return 'Select at least one person who shared this expense';
    final total = _totalPaise;
    if (total == null) return null; // the amount field shows its own error
    if (_splitType == 'custom') {
      for (final m in _participants) {
        if (_paiseOf(_customCtrls[m.id]!) == null) return 'Enter a valid amount for ${m.name}';
      }
      final diff = total - _customSum();
      if (diff != 0) {
        return diff > 0
            ? 'Shares are ${money(_fromPaise(diff))} short of the expense amount'
            : 'Shares exceed the expense amount by ${money(_fromPaise(-diff))}';
      }
    } else if (_splitType == 'percentage') {
      for (final m in _participants) {
        final p = _pctHundredths(_pctCtrls[m.id]!);
        if (p == null || p <= 0 || p > 10000) return 'Enter a valid percentage for ${m.name}';
      }
      if (_pctSum() != 10000) {
        return 'Percentages add up to ${(_pctSum() / 100).toStringAsFixed(2)} % - they must total 100 %';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final problem = _splitProblem();
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    final splits = <Map<String, dynamic>>[
      for (final m in _participants)
        {
          'user_id': m.id,
          if (_splitType == 'custom') 'amount': parseAmount(_customCtrls[m.id]!.text),
          if (_splitType == 'percentage') 'percentage': double.parse(_pctCtrls[m.id]!.text.trim()),
        },
    ];
    final body = {
      'description': _description.text.trim(),
      'amount': parseAmount(_amount.text),
      'category': _category,
      'paid_by': _paidBy,
      'split_type': _splitType,
      'splits': splits,
      'expense_date': isoDateTime(_date),
    };
    setState(() => _busy = true);
    try {
      if (_editing) {
        await context.api.put('/api/expenses/${widget.existing!.id}', body: body);
      } else {
        await context.api.post('/api/trips/${widget.tripId}/expenses', body: body);
      }
      if (!mounted) return;
      showMessage(context, _editing ? 'Expense updated' : 'Expense added');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit expense' : 'Add expense')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _loadMembers, child: const Text('Try again')),
                    ]),
                  ),
                )
              : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description', hintText: 'Dinner'),
              validator: (v) => validateRequired(v, 'Description'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              validator: validateAmount,
            ),
            const SizedBox(height: 14),
            LabeledDropdown<String>(
              label: 'Category',
              value: _category,
              items: [
                for (final c in expenseCategories)
                  DropdownMenuItem(
                    value: c,
                    child: Row(children: [Icon(categoryIcon(c), size: 18), const SizedBox(width: 10), Text(c)]),
                  ),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 14),
            LabeledDropdown<int>(
              label: 'Paid by',
              value: _paidBy ?? _members.first.id,
              items: [for (final m in _members) DropdownMenuItem(value: m.id, child: Text(m.name))],
              onChanged: (v) => setState(() => _paidBy = v),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.event_outlined)),
                child: Text(formatDate(_date)),
              ),
            ),
            const SectionTitle('Split'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'equal', label: Text('Equal')),
                ButtonSegment(value: 'custom', label: Text('Custom')),
                ButtonSegment(value: 'percentage', label: Text('Percent')),
              ],
              selected: {_splitType},
              onSelectionChanged: (s) => setState(() => _splitType = s.first),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Shared by', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected
                    ..clear()
                    ..addAll(_members.map((m) => m.id))),
                  child: const Text('Select all'),
                ),
              ],
            ),
            ..._members.map(_participantRow),
            const SizedBox(height: 8),
            _splitSummary(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_editing ? 'Save changes' : 'Add expense'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _participantRow(Member m) {
    final selected = _selected.contains(m.id);
    final equal = _equalShares();
    Widget? trailing;
    if (selected) {
      if (_splitType == 'equal') {
        trailing = Text(equal[m.id] == null ? '–' : money(_fromPaise(equal[m.id]!)),
            style: const TextStyle(fontWeight: FontWeight.w600));
      } else {
        final custom = _splitType == 'custom';
        trailing = SizedBox(
          width: 110,
          child: TextField(
            controller: custom ? _customCtrls[m.id] : _pctCtrls[m.id],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              prefixText: custom ? '₹ ' : null,
              suffixText: custom ? null : '%',
            ),
          ),
        );
      }
    }
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      onChanged: (v) => setState(() => v == true ? _selected.add(m.id) : _selected.remove(m.id)),
      title: Row(children: [
        Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis)),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _splitSummary() {
    final total = _totalPaise;
    if (_splitType == 'equal') {
      return Text(
        total == null || _participants.isEmpty
            ? 'Enter the amount to see each person\'s share.'
            : 'Split equally between ${_participants.length} ${_participants.length == 1 ? 'person' : 'people'}.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }
    if (_splitType == 'custom') {
      final remaining = total == null ? null : total - _customSum();
      final ok = remaining == 0;
      return Text(
        remaining == null
            ? 'Enter the amount first.'
            : ok
                ? 'Shares match the expense amount ✓'
                : (remaining > 0
                    ? '${money(_fromPaise(remaining))} still to assign'
                    : '${money(_fromPaise(-remaining))} over the expense amount'),
        style: TextStyle(color: ok ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600),
      );
    }
    final sum = _pctSum();
    final ok = sum == 10000;
    return Text(
      ok ? 'Percentages total 100 % ✓' : 'Percentages total ${(sum / 100).toStringAsFixed(2)} % (must be 100 %)',
      style: TextStyle(color: ok ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600),
    );
  }
}
