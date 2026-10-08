import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';

/// Screen 13 - Final settlement: who owes whom, and marking payments as paid.
class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  late Future<SettlementPlan> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<SettlementPlan> _load() async {
    final res = await context.api.get('/api/trips/${widget.trip.id}/settlements');
    return SettlementPlan.fromJson(res);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _calculate() async {
    setState(() => _busy = true);
    try {
      await context.api.post('/api/trips/${widget.trip.id}/settlements/generate');
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(Settlement s, String status) async {
    final paying = status == 'paid';
    final ok = await confirm(
      context,
      paying ? 'Mark as paid?' : 'Mark as pending?',
      paying
          ? '${s.payerName} paid ${money(s.amount)} to ${s.receiverName}.'
          : 'This payment will be counted as not yet paid.',
    );
    if (!ok || !mounted) return;
    try {
      await context.api.put('/api/settlements/${s.id}/pay', body: {'status': status});
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.auth.user?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Final settlement')),
      body: AsyncView<SettlementPlan>(
        future: _future,
        onRetry: _refresh,
        builder: (context, plan) {
          final pending = plan.settlements.where((s) => !s.isPaid).toList();
          final paid = plan.settlements.where((s) => s.isPaid).toList();
          final owe = pending.where((s) => s.payerId == myId).toList();
          final receive = pending.where((s) => s.receiverId == myId).toList();

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (plan.allSettled)
                  Card(
                    color: Colors.green.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('Everyone is settled up'),
                      subtitle: Text('No money is owed in this trip.'),
                    ),
                  ),
                if (plan.needsCalculation)
                  Card(
                    color: Colors.amber.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.calculate_outlined),
                      title: Text('Settlement not calculated yet'),
                      subtitle: Text('Expenses changed since the last calculation.'),
                    ),
                  ),
                if (!widget.trip.isCompleted)
                  FilledButton.icon(
                    onPressed: _busy ? null : _calculate,
                    icon: _busy
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.calculate),
                    label: Text(pending.isEmpty ? 'Calculate settlement' : 'Recalculate settlement'),
                  ),
                if (pending.isNotEmpty) ...[
                  const SectionTitle('You owe'),
                  if (owe.isEmpty) const _Hint('You don\'t owe anyone.'),
                  for (final s in owe) _line(s.receiverName, s.amount, Colors.red.shade700),
                  const SectionTitle('You receive'),
                  if (receive.isEmpty) const _Hint('Nobody owes you.'),
                  for (final s in receive) _line(s.payerName, s.amount, Colors.green.shade700),
                  const SectionTitle('Suggested payments'),
                  for (final s in pending) _paymentCard(s, myId),
                ],
                if (paid.isNotEmpty) ...[
                  const SectionTitle('Settlement history'),
                  for (final s in paid) _paymentCard(s, myId),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _line(String name, double amount, Color color) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          title: Text(name),
          trailing: Text(money(amount), style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ),
      );

  Widget _paymentCard(Settlement s, int? myId) {
    final involved = s.payerId == myId || s.receiverId == myId || widget.trip.isAdmin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${s.payerName}  →  ${s.receiverName}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Text(money(s.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              s.isPaid
                  ? const StatusChip(label: 'Paid', color: Colors.green)
                  : const StatusChip(label: 'Pending', color: Colors.orange),
              if (s.isPaid && s.paidAt != null) ...[
                const SizedBox(width: 8),
                Text(formatDateTime(s.paidAt!), style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
              const Spacer(),
              if (involved)
                s.isPaid
                    ? TextButton(onPressed: () => _setStatus(s, 'pending'), child: const Text('Undo'))
                    : FilledButton.tonal(onPressed: () => _setStatus(s, 'paid'), child: const Text('Mark paid')),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(text, style: TextStyle(color: Colors.grey.shade700)),
      );
}
