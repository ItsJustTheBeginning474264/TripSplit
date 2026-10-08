import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';
import 'add_expense_screen.dart';

/// Screen 11 - Expense details (with edit / delete for the creator or trip admin).
class ExpenseDetailsScreen extends StatefulWidget {
  const ExpenseDetailsScreen({super.key, required this.trip, required this.expenseId});

  final Trip trip;
  final int expenseId;

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  late Future<Expense> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Expense> _load() async {
    final res = await context.api.get('/api/expenses/${widget.expenseId}');
    return Expense.fromJson(res['expense'] as Map<String, dynamic>);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  bool _canEdit(Expense e) =>
      !widget.trip.isCompleted && (widget.trip.isAdmin || e.createdBy == context.auth.user?.id);

  Future<void> _edit(Expense e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddExpenseScreen(tripId: widget.trip.id, existing: e)),
    );
    if (mounted) _refresh();
  }

  Future<void> _delete(Expense e) async {
    final ok = await confirm(context, 'Delete expense?', '"${e.description}" will be removed for everyone.',
        action: 'Delete');
    if (!ok || !mounted) return;
    try {
      await context.api.delete('/api/expenses/${e.id}');
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  String _splitLabel(String type) =>
      {'equal': 'Equal split', 'custom': 'Custom amounts', 'percentage': 'Percentage split'}[type] ?? type;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Expense>(
      future: _future,
      builder: (context, snapshot) {
        final e = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Expense details'),
            actions: [
              if (e != null && _canEdit(e)) ...[
                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(e)),
                IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(e)),
              ],
            ],
          ),
          body: AsyncView<Expense>(
            future: _future,
            onRetry: _refresh,
            builder: (context, e) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(child: Icon(categoryIcon(e.category))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(e.description,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Text(money(e.amount),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                        const Divider(height: 28),
                        _row('Paid by', e.paidByName),
                        _row('Category', e.category),
                        _row('Date', formatDateTime(e.date)),
                        _row('Split', _splitLabel(e.splitType)),
                        _row('Added by', e.createdByName),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Shared by'),
                Card(
                  child: Column(
                    children: [
                      for (final s in e.splits)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                                style: const TextStyle(fontSize: 12)),
                          ),
                          title: Text(s.name),
                          subtitle: s.percentage == null ? null : Text('${s.percentage!.toStringAsFixed(2)} %'),
                          trailing: Text(money(s.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade700)),
            Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
          ],
        ),
      );
}
