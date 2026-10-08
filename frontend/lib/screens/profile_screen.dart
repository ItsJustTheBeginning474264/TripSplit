import 'package:flutter/material.dart';

import '../services/auth_provider.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

/// Screen 14 - Profile: view / edit name, change password, log out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _current = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.text = context.auth.user?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _current.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (!_profileKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.auth.updateProfile(name: _name.text.trim());
      if (mounted) showMessage(context, 'Profile updated');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.auth.updateProfile(currentPassword: _current.text, newPassword: _new.text);
      _current.clear();
      _new.clear();
      if (mounted) showMessage(context, 'Password changed');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ok = await confirm(context, 'Log out?', 'You will need to log in again.', action: 'Log out');
    if (!ok || !mounted) return;
    await context.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              child: Text((user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32)),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(user?.email ?? '', style: TextStyle(color: Colors.grey.shade700))),
          const SectionTitle('Your details'),
          Form(
            key: _profileKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => validateRequired(v, 'Name'),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _busy ? null : _saveName, child: const Text('Save name')),
              ],
            ),
          ),
          const SectionTitle('Change password'),
          Form(
            key: _passwordKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _current,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                  validator: (v) => validateRequired(v, 'Current password'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _new,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password (min 6 characters)'),
                  validator: validatePassword,
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _busy ? null : _changePassword, child: const Text('Change password')),
              ],
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
          ),
        ],
      ),
    );
  }
}
