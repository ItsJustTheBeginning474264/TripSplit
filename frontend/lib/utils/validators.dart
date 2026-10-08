/// Form validators (mirror the server-side rules so users get instant feedback).

final RegExp _emailRe = RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');

String? validateRequired(String? value, String label) {
  if (value == null || value.trim().isEmpty) return '$label is required';
  return null;
}

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Email is required';
  if (!_emailRe.hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Password is required';
  if (value.length < 6) return 'Password must be at least 6 characters';
  return null;
}

/// Parses a rupee amount with at most two decimals. Returns null if invalid.
double? parseAmount(String? text) {
  if (text == null) return null;
  final t = text.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
  return double.tryParse(t);
}

String? validateAmount(String? value) {
  if (value == null || value.trim().isEmpty) return 'Amount is required';
  final amount = parseAmount(value);
  if (amount == null) return 'Enter a valid amount (max 2 decimals)';
  if (amount <= 0) return 'Amount must be greater than zero';
  return null;
}

/// Converts rupees to whole paise so that sums can be compared without float error.
int toPaise(double rupees) => (rupees * 100).round();
