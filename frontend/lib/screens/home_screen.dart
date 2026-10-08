import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../widgets/common.dart';
import 'create_trip_screen.dart';
import 'join_trip_screen.dart';
import 'profile_screen.dart';
import 'trip_dashboard_screen.dart';

/// Screen 4 - Home / My Trips.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Trip>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Trip>> _load() async {
    final res = await context.api.get('/api/trips');
    return (res['trips'] as List).map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
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
    final name = context.auth.user?.name ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _open(const ProfileScreen()),
          ),
        ],
      ),
      body: AsyncView<List<Trip>>(
        future: _future,
        onRetry: _refresh,
        builder: (context, trips) {
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: trips.isEmpty
                ? ListView(children: [
                    SizedBox(
                      height: 420,
                      child: EmptyState(
                        icon: Icons.map_outlined,
                        title: 'Hi $name, no trips yet',
                        subtitle: 'Create a trip, or join a friend\'s trip with their invite code.',
                      ),
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: trips.length,
                    itemBuilder: (context, i) => _TripCard(
                      trip: trips[i],
                      onTap: () => _open(TripDashboardScreen(tripId: trips[i].id)),
                    ),
                  ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(const JoinTripScreen()),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join trip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _open(const CreateTripScreen()),
                  icon: const Icon(Icons.add),
                  label: const Text('Create trip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap});

  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(trip.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (trip.isCompleted)
                    const StatusChip(label: 'Completed', color: Colors.grey)
                  else if (trip.isAdmin)
                    const StatusChip(label: 'Admin', color: Colors.teal),
                ],
              ),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 4),
                Text(trip.destination),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_outlined, size: 14),
                const SizedBox(width: 4),
                Flexible(child: Text('${formatDate(trip.startDate)} – ${formatDate(trip.endDate)}')),
              ]),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${trip.memberCount} member${trip.memberCount == 1 ? '' : 's'}'),
                  Text('Total ${money(trip.totalExpenses)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
