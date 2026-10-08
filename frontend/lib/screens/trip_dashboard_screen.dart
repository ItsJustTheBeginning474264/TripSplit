import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';
import 'add_expense_screen.dart';
import 'balances_screen.dart';
import 'expenses_screen.dart';
import 'members_screen.dart';
import 'settlement_screen.dart';

class _DashboardData {
  _DashboardData(this.detail, this.balances);

  final TripDetail detail;
  final List<MemberBalance> balances;
}

/// Screen 7 - Trip Dashboard.
class TripDashboardScreen extends StatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId, this.justCreated = false});

  final int tripId;
  final bool justCreated;

  @override
  State<TripDashboardScreen> createState() => _TripDashboardScreenState();
}

class _TripDashboardScreenState extends State<TripDashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final api = context.api;
    final detail = TripDetail.fromJson(await api.get('/api/trips/${widget.tripId}'));
    final bal = await api.get('/api/trips/${widget.tripId}/balances');
    final balances =
        (bal['balances'] as List).map((e) => MemberBalance.fromJson(e as Map<String, dynamic>)).toList();
    return _DashboardData(detail, balances);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  Future<void> _toggleStatus(Trip trip) async {
    final completing = !trip.isCompleted;
    final ok = await confirm(
      context,
      completing ? 'Mark trip as completed?' : 'Reopen trip?',
      completing
          ? 'Expenses and new members will be locked. You can reopen the trip later.'
          : 'Members will be able to add and edit expenses again.',
    );
    if (!ok || !mounted) return;
    try {
      await context.api.put('/api/trips/${trip.id}', body: {'status': completing ? 'completed' : 'active'});
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteTrip(Trip trip) async {
    final ok = await confirm(
      context,
      'Delete this trip?',
      'All expenses, members and settlements of "${trip.name}" will be permanently deleted.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.api.delete('/api/trips/${trip.id}');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final trip = data?.detail.trip;
        return Scaffold(
          appBar: AppBar(
            title: Text(trip?.name ?? 'Trip'),
            actions: [
              IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
              if (trip != null && trip.isAdmin)
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'status' ? _toggleStatus(trip) : _deleteTrip(trip),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'status',
                      child: Text(trip.isCompleted ? 'Reopen trip' : 'Mark as completed'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete trip')),
                  ],
                ),
            ],
          ),
          floatingActionButton: trip == null || trip.isCompleted
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _go(AddExpenseScreen(tripId: trip.id)),
                  icon: const Icon(Icons.add),
                  label: const Text('Add expense'),
                ),
          body: AsyncView<_DashboardData>(
            future: _future,
            onRetry: _refresh,
            builder: (context, d) => _buildBody(context, d),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, _DashboardData d) {
    final trip = d.detail.trip;
    final s = d.detail.summary;
    final maxCat = d.detail.byCategory.isEmpty
        ? 1.0
        : d.detail.byCategory.map((c) => c.total).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (widget.justCreated)
            Card(
              color: Colors.teal.shade50,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text('Trip created! Share the invite code below with your friends so they can join.'),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.place_outlined, size: 18),
                    const SizedBox(width: 4),
                    Text(trip.destination, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (trip.isCompleted) const StatusChip(label: 'Completed', color: Colors.grey),
                  ]),
                  const SizedBox(height: 4),
                  Text('${formatDate(trip.startDate)} – ${formatDate(trip.endDate)}',
                      style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Text('Invite code  '),
                    SelectableText(trip.inviteCode,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3)),
                    IconButton(
                      tooltip: 'Copy code',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: trip.inviteCode));
                        showMessage(context, 'Invite code copied');
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: [
              InfoTile(label: 'Total members', value: '${s.totalMembers}'),
              InfoTile(label: 'Total expenses', value: money(s.totalExpenses)),
              InfoTile(label: 'Your contribution', value: money(s.myPaid)),
              InfoTile(label: 'Your share', value: money(s.myShare)),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            color: balanceColor(s.myBalance) == Colors.green.shade700
                ? Colors.green.shade50
                : (s.myBalance < -0.005 ? Colors.red.shade50 : null),
            child: ListTile(
              title: const Text('Your balance'),
              subtitle: Text(s.myBalance > 0.005
                  ? 'You should receive money'
                  : (s.myBalance < -0.005 ? 'You owe money' : 'You are all square')),
              trailing: Text(
                signedMoney(s.myBalance),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: balanceColor(s.myBalance)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _NavButton(Icons.groups_outlined, 'Members', () => _go(MembersScreen(trip: trip)))),
            const SizedBox(width: 8),
            Expanded(child: _NavButton(Icons.receipt_long_outlined, 'Expenses', () => _go(ExpensesScreen(trip: trip)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NavButton(Icons.balance_outlined, 'Balances', () => _go(BalancesScreen(trip: trip)))),
            const SizedBox(width: 8),
            Expanded(
              child: _NavButton(Icons.handshake_outlined, 'Final settlement', () => _go(SettlementScreen(trip: trip))),
            ),
          ]),
          const SectionTitle('Member summary'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  const _SummaryRow(cells: ['Member', 'Paid', 'Share', 'Balance'], header: true),
                  const Divider(height: 8),
                  for (final b in d.balances)
                    _SummaryRow(
                      cells: [b.name, money(b.paid), money(b.share), signedMoney(b.balance)],
                      balanceValue: b.balance,
                    ),
                ],
              ),
            ),
          ),
          if (d.detail.byCategory.isNotEmpty) ...[
            const SectionTitle('Spending by category'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    for (final c in d.detail.byCategory)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Icon(categoryIcon(c.category), size: 20),
                          const SizedBox(width: 10),
                          SizedBox(width: 96, child: Text(c.category, overflow: TextOverflow.ellipsis)),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: maxCat <= 0 ? 0 : c.total / maxCat,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(money(c.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, overflow: TextOverflow.ellipsis),
      );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.cells, this.header = false, this.balanceValue});

  final List<String> cells;
  final bool header;
  final double? balanceValue;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700, fontSize: 12)
        : const TextStyle(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(cells[0], style: style, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text(cells[1], style: style, textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text(cells[2], style: style, textAlign: TextAlign.right)),
          Expanded(
            flex: 3,
            child: Text(
              cells[3],
              textAlign: TextAlign.right,
              style: balanceValue == null
                  ? style
                  : style.copyWith(color: balanceColor(balanceValue!), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
