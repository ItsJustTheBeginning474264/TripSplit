double _num(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

const List<String> expenseCategories = [
  'Food',
  'Hotel',
  'Transportation',
  'Activities',
  'Shopping',
  'Tickets',
  'Fuel',
  'Other',
];

class AppUser {
  AppUser({required this.id, required this.name, required this.email, this.profileImage});

  final int id;
  final String name;
  final String email;
  final String? profileImage;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['user_id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        profileImage: j['profile_image'] as String?,
      );
}

class Trip {
  Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.inviteCode,
    required this.status,
    required this.role,
    this.memberCount = 0,
    this.totalExpenses = 0,
  });

  final int id;
  final String name;
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final String inviteCode;
  final String status; // active | completed
  final String role; // admin | member
  final int memberCount;
  final double totalExpenses;

  bool get isAdmin => role == 'admin';
  bool get isCompleted => status == 'completed';

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['trip_id'] as int,
        name: j['trip_name'] as String,
        destination: j['destination'] as String,
        startDate: _date(j['start_date']) ?? DateTime.now(),
        endDate: _date(j['end_date']) ?? DateTime.now(),
        inviteCode: j['invite_code'] as String,
        status: j['status'] as String,
        role: (j['role'] as String?) ?? 'member',
        memberCount: (j['member_count'] as int?) ?? 0,
        totalExpenses: _num(j['total_expenses']),
      );
}

class TripSummary {
  TripSummary({
    required this.totalMembers,
    required this.expenseCount,
    required this.totalExpenses,
    required this.myPaid,
    required this.myShare,
    required this.myBalance,
    required this.myRemaining,
  });

  final int totalMembers;
  final int expenseCount;
  final double totalExpenses;
  final double myPaid;
  final double myShare;
  final double myBalance;
  final double myRemaining;

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
        totalMembers: j['total_members'] as int,
        expenseCount: j['expense_count'] as int,
        totalExpenses: _num(j['total_expenses']),
        myPaid: _num(j['my_paid']),
        myShare: _num(j['my_share']),
        myBalance: _num(j['my_balance']),
        myRemaining: _num(j['my_remaining']),
      );
}

class CategoryTotal {
  CategoryTotal({required this.category, required this.count, required this.total});

  final String category;
  final int count;
  final double total;

  factory CategoryTotal.fromJson(Map<String, dynamic> j) => CategoryTotal(
        category: j['category'] as String,
        count: j['expense_count'] as int,
        total: _num(j['total']),
      );
}

class TripDetail {
  TripDetail({required this.trip, required this.summary, required this.byCategory});

  final Trip trip;
  final TripSummary summary;
  final List<CategoryTotal> byCategory;

  factory TripDetail.fromJson(Map<String, dynamic> j) => TripDetail(
        trip: Trip.fromJson(j['trip'] as Map<String, dynamic>),
        summary: TripSummary.fromJson(j['summary'] as Map<String, dynamic>),
        byCategory: (j['by_category'] as List)
            .map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Member {
  Member({required this.id, required this.name, required this.email, required this.role, this.joinedAt});

  final int id;
  final String name;
  final String email;
  final String role;
  final DateTime? joinedAt;

  bool get isAdmin => role == 'admin';

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['user_id'] as int,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        joinedAt: _date(j['joined_at']),
      );
}

class SplitShare {
  SplitShare({required this.userId, required this.name, required this.amount, this.percentage});

  final int userId;
  final String name;
  final double amount;
  final double? percentage;

  factory SplitShare.fromJson(Map<String, dynamic> j) => SplitShare(
        userId: j['user_id'] as int,
        name: j['name'] as String,
        amount: _num(j['amount']),
        percentage: j['percentage'] == null ? null : _num(j['percentage']),
      );
}

class Expense {
  Expense({
    required this.id,
    required this.tripId,
    required this.paidBy,
    required this.paidByName,
    required this.createdBy,
    required this.createdByName,
    required this.description,
    required this.amount,
    required this.category,
    required this.splitType,
    required this.date,
    required this.splits,
  });

  final int id;
  final int tripId;
  final int paidBy;
  final String paidByName;
  final int createdBy;
  final String createdByName;
  final String description;
  final double amount;
  final String category;
  final String splitType; // equal | custom | percentage
  final DateTime date;
  final List<SplitShare> splits;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['expense_id'] as int,
        tripId: j['trip_id'] as int,
        paidBy: j['paid_by'] as int,
        paidByName: j['paid_by_name'] as String,
        createdBy: j['created_by'] as int,
        createdByName: j['created_by_name'] as String,
        description: j['description'] as String,
        amount: _num(j['amount']),
        category: j['category'] as String,
        splitType: j['split_type'] as String,
        date: _date(j['expense_date']) ?? DateTime.now(),
        splits: (j['splits'] as List)
            .map((e) => SplitShare.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MemberBalance {
  MemberBalance({
    required this.userId,
    required this.name,
    required this.paid,
    required this.share,
    required this.balance,
    required this.settledOut,
    required this.settledIn,
    required this.remaining,
  });

  final int userId;
  final String name;
  final double paid;
  final double share;
  final double balance; // > 0 receives, < 0 owes
  final double settledOut;
  final double settledIn;
  final double remaining; // balance after payments already made

  factory MemberBalance.fromJson(Map<String, dynamic> j) => MemberBalance(
        userId: j['user_id'] as int,
        name: j['name'] as String,
        paid: _num(j['paid']),
        share: _num(j['share']),
        balance: _num(j['balance']),
        settledOut: _num(j['settled_out']),
        settledIn: _num(j['settled_in']),
        remaining: _num(j['remaining']),
      );
}

class Settlement {
  Settlement({
    required this.id,
    required this.payerId,
    required this.payerName,
    required this.receiverId,
    required this.receiverName,
    required this.amount,
    required this.status,
    this.paidAt,
  });

  final int id;
  final int payerId;
  final String payerName;
  final int receiverId;
  final String receiverName;
  final double amount;
  final String status; // pending | paid
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';

  factory Settlement.fromJson(Map<String, dynamic> j) => Settlement(
        id: j['settlement_id'] as int,
        payerId: j['payer_id'] as int,
        payerName: j['payer_name'] as String,
        receiverId: j['receiver_id'] as int,
        receiverName: j['receiver_name'] as String,
        amount: _num(j['amount']),
        status: j['status'] as String,
        paidAt: _date(j['paid_at']),
      );
}

class SettlementPlan {
  SettlementPlan({required this.settlements, required this.allSettled, required this.needsCalculation});

  final List<Settlement> settlements;
  final bool allSettled;
  final bool needsCalculation;

  factory SettlementPlan.fromJson(Map<String, dynamic> j) => SettlementPlan(
        settlements: (j['settlements'] as List)
            .map((e) => Settlement.fromJson(e as Map<String, dynamic>))
            .toList(),
        allSettled: (j['all_settled'] as bool?) ?? false,
        needsCalculation: (j['needs_calculation'] as bool?) ?? false,
      );
}
