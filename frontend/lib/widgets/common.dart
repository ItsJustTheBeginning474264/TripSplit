import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final NumberFormat _inrWhole = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _inrFull = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// ₹3,600 or ₹3,600.50 (decimals only when needed), Indian digit grouping.
String money(double value) {
  final v = value.abs() < 0.005 ? 0.0 : value;
  final isWhole = (v - v.roundToDouble()).abs() < 0.005;
  return isWhole ? _inrWhole.format(v.roundToDouble()) : _inrFull.format(v);
}

/// +₹1,100 / -₹500 / ₹0
String signedMoney(double value) {
  if (value.abs() < 0.005) return money(0);
  return value > 0 ? '+${money(value)}' : '-${money(value.abs())}';
}

String formatDate(DateTime d) => DateFormat('d MMM yyyy').format(d);
String formatDateTime(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String isoDateTime(DateTime d) => DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(d);

/// Green when money is to be received, red when owed.
Color balanceColor(double v) {
  if (v > 0.005) return Colors.green.shade700;
  if (v < -0.005) return Colors.red.shade700;
  return Colors.grey.shade700;
}

IconData categoryIcon(String category) {
  switch (category) {
    case 'Food':
      return Icons.restaurant;
    case 'Hotel':
      return Icons.hotel;
    case 'Transportation':
      return Icons.directions_bus;
    case 'Activities':
      return Icons.surfing;
    case 'Shopping':
      return Icons.shopping_bag;
    case 'Tickets':
      return Icons.confirmation_number;
    case 'Fuel':
      return Icons.local_gas_station;
    default:
      return Icons.receipt_long;
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, Object error) => showMessage(context, error.toString());

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'Confirm'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

/// FutureBuilder with a consistent loading / error / retry presentation.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.future, required this.builder, required this.onRetry});

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        return builder(context, snapshot.data as T);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(color: color.shade800, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Drop-down with a floating label that does not depend on DropdownButtonFormField.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(isExpanded: true, isDense: true, value: value, items: items, onChanged: onChanged),
      ),
    );
  }
}

class InfoTile extends StatelessWidget {
  const InfoTile({super.key, required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: valueColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
