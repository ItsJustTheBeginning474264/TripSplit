import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_provider.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import 'trip_dashboard_screen.dart';

/// Screen 6 - Join Trip with an invite code.
class JoinTripScreen extends StatefulWidget {
  const JoinTripScreen({super.key});

  @override
  State<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends State<JoinTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await context.api.post('/api/trips/join', body: {'invite_code': _code.text.trim()});
      final trip = Trip.fromJson(res['trip'] as Map<String, dynamic>);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripDashboardScreen(tripId: trip.id)),
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
      appBar: AppBar(title: const Text('Join a trip')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ask the trip admin for the 6-character invite code.',
                    style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'Invite code', hintText: 'GOA26X'),
                  validator: (v) {
                    final req = validateRequired(v, 'Invite code');
                    if (req != null) return req;
                    return v!.trim().length != 6 ? 'The code has 6 characters' : null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Join trip'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
