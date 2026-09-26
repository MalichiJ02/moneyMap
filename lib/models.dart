// All amounts are integer ngwee: K12.50 is 1250.
String money(int ngwee) {
  final absolute = ngwee.abs();
  final sign = ngwee < 0 ? '-' : '';
  return '${sign}K${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
}

int? parseMoney(String input, {bool allowZero = false}) {
  final value = input.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  final cents = parts.length == 2 ? int.tryParse(parts.last.padRight(2, '0')) : 0;
  if (whole == null || cents == null) return null;
  final amount = whole * 100 + cents;
  if (amount < 0 || (!allowZero && amount == 0)) return null;
  return amount;
}

String inputMoney(int ngwee) => (ngwee / 100).toStringAsFixed(2);

DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);

String shortDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

const monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String monthName(DateTime date) => '${monthNames[date.month - 1]} ${date.year}';

const expenseCategories = [
  'Food', 'Transport', 'Rent', 'Bills', 'Education',
  'Shopping', 'Health', 'Entertainment', 'Other',
];

const incomeCategories = ['Salary', 'Business', 'Allowance', 'Gift', 'Other'];

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.isIncome,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
  });

  final String id;
  final bool isIncome;
  final String category;
  final String description;
  final int amount;
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': isIncome ? 'income' : 'expense',
        'category': category,
        'description': description,
        'amount': amount,
        'date': date.toIso8601String(),
      };

  factory MoneyTransaction.fromJson(Map<String, dynamic> json) => MoneyTransaction(
        id: json['id'] as String,
        isIncome: (json['type'] as String) == 'income',
        category: json['category'] as String,
        description: json['description'] as String,
        amount: (json['amount'] as num).toInt(),
        date: DateTime.parse(json['date'] as String),
      );
}

class PlannedExpense {
  const PlannedExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.dueDate,
  });

  final String id;
  final String title;
  final String category;
  final int amount;
  final DateTime dueDate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'amount': amount,
        'dueDate': dueDate.toIso8601String(),
      };

  factory PlannedExpense.fromJson(Map<String, dynamic> json) => PlannedExpense(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String,
        amount: (json['amount'] as num).toInt(),
        dueDate: DateTime.parse(json['dueDate'] as String),
      );
}

class RecurringEntry {
  const RecurringEntry({
    required this.id,
    required this.title,
    required this.isIncome,
    required this.category,
    required this.amount,
    required this.nextDate,
    required this.frequency,
  });

  final String id;
  final String title;
  final bool isIncome;
  final String category;
  final int amount;
  final DateTime nextDate;
  final String frequency; // weekly or monthly

  RecurringEntry next() {
    final maxDay = DateTime(nextDate.year, nextDate.month + 2, 0).day;
    final newDate = frequency == 'weekly'
        ? nextDate.add(const Duration(days: 7))
        : DateTime(nextDate.year, nextDate.month + 1,
            nextDate.day > maxDay ? maxDay : nextDate.day);
    return RecurringEntry(id: id, title: title, isIncome: isIncome,
      category: category, amount: amount, nextDate: newDate, frequency: frequency);
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'isIncome': isIncome, 'category': category,
    'amount': amount, 'nextDate': nextDate.toIso8601String(), 'frequency': frequency,
  };

  factory RecurringEntry.fromJson(Map<String, dynamic> json) => RecurringEntry(
    id: json['id'] as String, title: json['title'] as String,
    isIncome: json['isIncome'] as bool, category: json['category'] as String,
    amount: (json['amount'] as num).toInt(),
    nextDate: DateTime.parse(json['nextDate'] as String),
    frequency: json['frequency'] as String,
  );
}

class MoneyTask {
  const MoneyTask({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.isDone,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final bool isDone;

  MoneyTask copyWith({bool? isDone}) => MoneyTask(
        id: id,
        title: title,
        dueDate: dueDate,
        isDone: isDone ?? this.isDone,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dueDate': dueDate.toIso8601String(),
        'isDone': isDone,
      };

  factory MoneyTask.fromJson(Map<String, dynamic> json) => MoneyTask(
        id: json['id'] as String,
        title: json['title'] as String,
        dueDate: DateTime.parse(json['dueDate'] as String),
        isDone: json['isDone'] as bool,
      );
}

class MoneyData {
  MoneyData({DateTime? startingDate}) : startingDate = startingDate ?? day(DateTime.now());

  int startingBalance = 0;
  DateTime startingDate;
  final List<MoneyTransaction> transactions = [];
  final List<PlannedExpense> plannedExpenses = [];
  final List<RecurringEntry> recurring = [];
  final List<MoneyTask> tasks = [];
  final Map<String, int> monthlyLimits = {};

  Map<String, dynamic> toJson() => {
        'startingBalance': startingBalance,
        'startingDate': startingDate.toIso8601String(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'plannedExpenses': plannedExpenses.map((e) => e.toJson()).toList(),
        'recurring': recurring.map((e) => e.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'monthlyLimits': monthlyLimits,
      };

  factory MoneyData.fromJson(Map<String, dynamic> json) {
    final data = MoneyData(
      startingDate: DateTime.tryParse(json['startingDate'] as String? ?? ''),
    );
    data.startingBalance = (json['startingBalance'] as num? ?? 0).toInt();
    for (final item in json['transactions'] as List<dynamic>? ?? []) {
      data.transactions.add(MoneyTransaction.fromJson(item as Map<String, dynamic>));
    }
    for (final item in json['plannedExpenses'] as List<dynamic>? ?? []) {
      data.plannedExpenses.add(PlannedExpense.fromJson(item as Map<String, dynamic>));
    }
    for (final item in json['recurring'] as List<dynamic>? ?? []) {
      data.recurring.add(RecurringEntry.fromJson(item as Map<String, dynamic>));
    }
    for (final item in json['tasks'] as List<dynamic>? ?? []) {
      data.tasks.add(MoneyTask.fromJson(item as Map<String, dynamic>));
    }
    final limits = json['monthlyLimits'] as Map<String, dynamic>? ?? {};
    data.monthlyLimits.addAll(limits.map((key, value) => MapEntry(key, (value as num).toInt())));
    return data;
  }
}
