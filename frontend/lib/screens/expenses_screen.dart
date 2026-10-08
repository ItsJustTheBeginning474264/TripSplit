import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';
import 'add_expense_screen.dart';
import 'expense_details_screen.dart';

class _ExpenseList {
  _ExpenseList(this.expenses, this.total);

  final List<Expense> expenses;
  final double total;
}

/// Screen 9 - Expenses list (with category filter).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<_ExpenseList> _future;
  String? _category;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExpenseList> _load() async {
    final res = await context.api.get(
      '/api/trips/${widget.trip.id}/expenses',
      query: _category == null ? null : {'category': _category!},
    );
    final list = (res['expenses'] as List).map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
    return _ExpenseList(list, (res['total'] as num).toDouble());
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: widget.trip.isCompleted
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open(AddExpenseScreen(tripId: widget.trip.id)),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) {
                      _category = null;
                      _refresh();
                    },
                  ),
                ),
                for (final c in expenseCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(categoryIcon(c), size: 16),
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) {
                        _category = c;
                        _refresh();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<_ExpenseList>(
              future: _future,
              onRetry: _refresh,
              builder: (context, data) {
                if (data.expenses.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No expenses yet',
                    subtitle: 'Tap "Add expense" to record the first one.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: data.expenses.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${data.expenses.length} expense${data.expenses.length == 1 ? '' : 's'}  ·  Total ${money(data.total)}',
                            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                        );
                      }
                      final e = data.expenses[i - 1];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(categoryIcon(e.category))),
                          title: Text(e.description),
                          subtitle: Text('Paid by ${e.paidByName} · ${formatDate(e.date)}'),
                          trailing: Text(money(e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                          onTap: () => _open(ExpenseDetailsScreen(trip: widget.trip, expenseId: e.id)),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
