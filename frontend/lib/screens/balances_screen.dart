import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';

/// Screen 12 - Balances (paid / share / balance per member).
class BalancesScreen extends StatefulWidget {
  const BalancesScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> {
  late Future<List<MemberBalance>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MemberBalance>> _load() async {
    final res = await context.api.get('/api/trips/${widget.trip.id}/balances');
    return (res['balances'] as List).map((e) => MemberBalance.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.auth.user?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Balances')),
      body: AsyncView<List<MemberBalance>>(
        future: _future,
        onRetry: _refresh,
        builder: (context, balances) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Positive balance: should receive money. Negative balance: owes money.',
                  style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              for (final b in balances)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(b.userId == myId ? '${b.name} (you)' : b.name,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                          Text(signedMoney(b.balance),
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800, color: balanceColor(b.balance))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _stat('Paid', money(b.paid))),
                          Expanded(child: _stat('Share', money(b.share))),
                          Expanded(child: _stat('Still to settle', signedMoney(b.remaining))),
                        ]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}
