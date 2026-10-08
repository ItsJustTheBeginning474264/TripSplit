import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import 'trip_dashboard_screen.dart';

/// Screen 5 - Create Trip.
class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _destination = TextEditingController();
  DateTimeRange? _range;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_range == null) {
      showMessage(context, 'Please choose the trip dates');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await context.api.post('/api/trips', body: {
        'trip_name': _name.text.trim(),
        'destination': _destination.text.trim(),
        'start_date': isoDate(_range!.start),
        'end_date': isoDate(_range!.end),
      });
      final trip = Trip.fromJson(res['trip'] as Map<String, dynamic>);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripDashboardScreen(tripId: trip.id, justCreated: true)),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create trip')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Trip name', hintText: 'Goa Trip 2026'),
                  validator: (v) => validateRequired(v, 'Trip name'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _destination,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.place_outlined)),
                  validator: (v) => validateRequired(v, 'Destination'),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDates,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Dates',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(
                      _range == null
                          ? 'Tap to choose start and end date'
                          : '${formatDate(_range!.start)} – ${formatDate(_range!.end)}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You become the trip admin. An invite code is generated so friends can join.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create trip'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
