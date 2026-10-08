import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';

/// Screen 8 - Members of a trip.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late Future<List<Member>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Member>> _load() async {
    final res = await context.api.get('/api/trips/${widget.trip.id}/members');
    return (res['members'] as List).map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
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
      appBar: AppBar(title: const Text('Members')),
      body: AsyncView<List<Member>>(
        future: _future,
        onRetry: _refresh,
        builder: (context, members) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Colors.teal.shade50,
                child: ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: Text(widget.trip.inviteCode,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3)),
                  subtitle: const Text('Invite code - share it so friends can join'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.trip.inviteCode));
                      showMessage(context, 'Invite code copied');
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final m in members)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
                    title: Text(m.id == myId ? '${m.name} (you)' : m.name),
                    subtitle: Text(m.email),
                    trailing: m.isAdmin ? const StatusChip(label: 'Admin', color: Colors.teal) : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
