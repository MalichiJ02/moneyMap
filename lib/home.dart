import 'package:flutter/material.dart';

import 'models.dart';
import 'storage.dart';

class MoneyMapHome extends StatefulWidget {
  const MoneyMapHome({super.key});

  @override
  State<MoneyMapHome> createState() => _MoneyMapHomeState();
}

class _MoneyMapHomeState extends State<MoneyMapHome> {
  final MoneyStorage _storage = MoneyStorage();
  MoneyData _data = MoneyData();
  Future<void> _writeQueue = Future<void>.value();
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;
  int _range = 1; // 0 daily, 1 weekly, 2 monthly
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _storage.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loadFailed = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _error = 'Saved data could not be opened: $error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    _writeQueue = _writeQueue.catchError((Object _) {}).then((_) => _storage.save(_data));
    try {
      await _writeQueue;
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Changes could not be saved: $error');
        _message('Save failed. Check the error shown above.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  int get _income => _data.transactions
      .where((t) => t.isIncome)
      .fold<int>(0, (sum, t) => sum + t.amount);

  int get _expenses => _data.transactions
      .where((t) => !t.isIncome)
      .fold<int>(0, (sum, t) => sum + t.amount);

  int get _balance => _data.startingBalance + _income - _expenses;

  int _balanceBefore(DateTime end) {
    var amount = _data.startingDate.isBefore(end) ? _data.startingBalance : 0;
    for (final transaction in _data.transactions) {
      if (transaction.date.isBefore(end)) {
        amount += transaction.isIncome ? transaction.amount : -transaction.amount;
      }
    }
    return amount;
  }

  DateTime _periodStart(DateTime value) {
    if (_range == 0) return day(value);
    if (_range == 1) {
      return day(value).subtract(Duration(days: value.weekday - 1));
    }
    return DateTime(value.year, value.month);
  }

  DateTime _nextPeriod(DateTime value) {
    if (_range == 0) return DateTime(value.year, value.month, value.day + 1);
    if (_range == 1) return value.add(const Duration(days: 7));
    return DateTime(value.year, value.month + 1);
  }

  DateTime _previousPeriod(DateTime value) {
    if (_range == 0) return DateTime(value.year, value.month, value.day - 1);
    if (_range == 1) return value.subtract(const Duration(days: 7));
    return DateTime(value.year, value.month - 1);
  }

  String _periodLabel(DateTime value) {
    if (_range == 0) return '${value.day} ${monthNames[value.month - 1]}';
    if (_range == 2) return monthName(value);
    final end = value.add(const Duration(days: 6));
    return '${value.day} ${monthNames[value.month - 1]}–'
        '${end.day} ${monthNames[end.month - 1]}';
  }

  int _periodSum(DateTime start, DateTime end, {required bool income}) =>
      _data.transactions
          .where((t) => t.isIncome == income &&
              !t.date.isBefore(start) && t.date.isBefore(end))
          .fold<int>(0, (sum, t) => sum + t.amount);

  Future<DateTime?> _pickDate(DateTime initial, {bool future = true}) {
    final today = day(DateTime.now());
    return showDatePicker(
      context: context,
      initialDate: !future && initial.isAfter(today) ? today : initial,
      firstDate: DateTime(2000),
      lastDate: future ? DateTime(2100) : today,
    );
  }

  Future<void> _startingBalanceDialog() async {
    final controller = TextEditingController(text: inputMoney(_data.startingBalance));
    var date = _data.startingDate;
    final result = await showDialog<(int, DateTime)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Starting balance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount in kwacha'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('As of ${shortDate(date)}'),
                onPressed: () async {
                  final picked = await _pickDate(date, future: false);
                  if (picked != null && dialogContext.mounted) update(() => date = picked);
                },
              ),
              const Text('This is a snapshot. Do not also record it as income.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final parsed = parseMoney(controller.text, allowZero: true);
                if (parsed == null) {
                  _message('Enter an amount such as 500 or 500.25.');
                  return;
                }
                Navigator.pop(dialogContext, (parsed, date));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _data.startingBalance = result.$1;
      _data.startingDate = result.$2;
    });
    await _save();
  }

  Future<void> _transactionDialog([MoneyTransaction? existing]) async {
    final title = TextEditingController(text: existing?.description ?? '');
    final amount = TextEditingController(text: existing == null ? '' : inputMoney(existing.amount));
    var income = existing?.isIncome ?? false;
    var category = existing?.category ?? expenseCategories.first;
    var date = existing?.date ?? day(DateTime.now());
    final result = await showDialog<MoneyTransaction>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final categories = income ? incomeCategories : expenseCategories;
          return AlertDialog(
            title: Text(existing == null ? 'Add transaction' : 'Edit transaction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<bool>(
                    initialValue: income,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Income')),
                      DropdownMenuItem(value: false, child: Text('Expense')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      update(() {
                        income = value;
                        category = income ? incomeCategories.first : expenseCategories.first;
                      });
                    },
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(income),
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (value) { if (value != null) update(() => category = value); },
                  ),
                  TextField(controller: title, decoration: const InputDecoration(labelText: 'Description')),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount in kwacha'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(shortDate(date)),
                    onPressed: () async {
                      final picked = await _pickDate(date, future: false);
                      if (picked != null && dialogContext.mounted) update(() => date = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final parsed = parseMoney(amount.text);
                  if (parsed == null || title.text.trim().isEmpty) {
                    _message('Add a description and an amount above K0.');
                    return;
                  }
                  Navigator.pop(dialogContext, MoneyTransaction(
                    id: existing?.id ?? _id(), isIncome: income, category: category,
                    description: title.text.trim(), amount: parsed, date: date,
                  ));
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    title.dispose();
    amount.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _data.transactions.add(result);
      } else {
        final index = _data.transactions.indexWhere((t) => t.id == existing.id);
        if (index >= 0) _data.transactions[index] = result;
      }
    });
    await _save();
  }

  Future<void> _plannedDialog([PlannedExpense? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final amount = TextEditingController(text: existing == null ? '' : inputMoney(existing.amount));
    var category = existing?.category ?? expenseCategories.first;
    var due = existing?.dueDate ?? day(DateTime.now());
    final result = await showDialog<PlannedExpense>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Plan an expense' : 'Edit upcoming expense'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Name, e.g. Rent')),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (value) { if (value != null) update(() => category = value); },
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Expected amount in kwacha'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text('Due ${shortDate(due)}'),
                onPressed: () async {
                  final picked = await _pickDate(due);
                  if (picked != null && dialogContext.mounted) update(() => due = picked);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final parsed = parseMoney(amount.text);
                if (parsed == null || title.text.trim().isEmpty) {
                  _message('Add a name and an amount above K0.');
                  return;
                }
                Navigator.pop(dialogContext, PlannedExpense(
                  id: existing?.id ?? _id(), title: title.text.trim(), category: category,
                  amount: parsed, dueDate: due,
                ));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    amount.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _data.plannedExpenses.add(result);
      } else {
        final index = _data.plannedExpenses.indexWhere((e) => e.id == existing.id);
        if (index >= 0) _data.plannedExpenses[index] = result;
      }
    });
    await _save();
  }

  Future<void> _pay(PlannedExpense expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record payment?'),
        content: Text('${expense.title} will be recorded as a ${money(expense.amount)} expense today.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Mark paid')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (!_data.plannedExpenses.any((e) => e.id == expense.id)) return;
    setState(() {
      _data.plannedExpenses.removeWhere((e) => e.id == expense.id);
      _data.transactions.add(MoneyTransaction(
        id: _id(), isIncome: false, category: expense.category,
        description: expense.title, amount: expense.amount, date: day(DateTime.now()),
      ));
    });
    await _save();
  }

  Future<void> _limitDialog() async {
    var category = expenseCategories.first;
    final controller = TextEditingController();
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Monthly spending limit'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              items: expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (value) { if (value != null) update(() => category = value); },
            ),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Limit in kwacha'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final parsed = parseMoney(controller.text);
                if (parsed == null) { _message('Enter a limit above K0.'); return; }
                Navigator.pop(dialogContext, (category, parsed));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => _data.monthlyLimits[result.$1] = result.$2);
    await _save();
  }

  Future<void> _taskDialog([MoneyTask? existing]) async {
    final controller = TextEditingController(text: existing?.title ?? '');
    var due = existing?.dueDate ?? day(DateTime.now());
    final result = await showDialog<MoneyTask>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Add task' : 'Edit task'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Task')),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('Due ${shortDate(due)}'),
              onPressed: () async {
                final picked = await _pickDate(due);
                if (picked != null && dialogContext.mounted) update(() => due = picked);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) { _message('Enter a task.'); return; }
                Navigator.pop(dialogContext, MoneyTask(
                  id: existing?.id ?? _id(), title: controller.text.trim(),
                  dueDate: due, isDone: existing?.isDone ?? false,
                ));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _data.tasks.add(result);
      } else {
        final index = _data.tasks.indexWhere((t) => t.id == existing.id);
        if (index >= 0) _data.tasks[index] = result;
      }
    });
    await _save();
  }

  Widget _section(String title, Widget body, {Widget? action}) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          if (action != null) action,
        ]),
        const SizedBox(height: 10),
        body,
      ]),
    ),
  );

  Widget _summary() {
    final upcoming = _data.plannedExpenses.fold<int>(0, (sum, e) => sum + e.amount);
    return _section('Overview', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Current balance'),
      Text(money(_balance), style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold, color: _balance < 0 ? Colors.red : const Color(0xFF183E90))),
      const SizedBox(height: 10),
      Text('Income: ${money(_income)}'),
      Text('Expenses: ${money(_expenses)}'),
      Text('Starting balance: ${money(_data.startingBalance)} as of ${shortDate(_data.startingDate)}'),
      Text('Upcoming expenses: ${money(upcoming)}'),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _startingBalanceDialog,
        icon: const Icon(Icons.edit),
        label: const Text('Set starting balance'),
      ),
    ]));
  }

  Widget _reports() {
    final now = day(DateTime.now());
    final start = _periodStart(now);
    final end = _nextPeriod(start);
    final before = _previousPeriod(start);
    final income = _periodSum(start, end, income: true);
    final expenses = _periodSum(start, end, income: false);
    final oldIncome = _periodSum(before, start, income: true);
    final oldExpenses = _periodSum(before, start, income: false);
    final change = _balanceBefore(end) - _balanceBefore(start);
    final previousChange = _balanceBefore(start) - _balanceBefore(before);

    final starts = <DateTime>[];
    var cursor = start;
    for (var index = 0; index < 7; index++) {
      starts.insert(0, cursor);
      cursor = _previousPeriod(cursor);
    }
    final values = starts.map((s) => _balanceBefore(_nextPeriod(s))).toList();
    final largest = values.fold<int>(1, (max, v) => v.abs() > max ? v.abs() : max);

    final trend = change > 0
        ? 'Balance improved by ${money(change)} this period.'
        : change < 0
            ? 'Balance fell by ${money(change.abs())} this period.'
            : 'Balance has not changed this period.';

    return _section('Trends', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Daily')),
          ButtonSegment(value: 1, label: Text('Weekly')),
          ButtonSegment(value: 2, label: Text('Monthly')),
        ],
        selected: {_range},
        onSelectionChanged: (values) => setState(() => _range = values.first),
      ),
      const SizedBox(height: 14),
      Text('Current ${_periodLabel(start)}: ${money(income)} in, ${money(expenses)} out'),
      Text('Previous ${_periodLabel(before)}: ${money(oldIncome)} in, ${money(oldExpenses)} out'),
      Text('Net movement: ${money(change)} (previous: ${money(previousChange)})'),
      const SizedBox(height: 10),
      Text(trend, style: TextStyle(fontWeight: FontWeight.bold,
        color: change < 0 ? Colors.red.shade700 : Colors.green.shade700)),
      const SizedBox(height: 14),
      const Text('Ending balance by period'),
      ...List.generate(starts.length, (index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 82, child: Text(_periodLabel(starts[index]), style: const TextStyle(fontSize: 11))),
          Expanded(child: LinearProgressIndicator(
            value: values[index].abs() / largest,
            minHeight: 14,
            backgroundColor: Colors.grey.shade200,
            color: values[index] < 0 ? Colors.red : Colors.blue,
          )),
          const SizedBox(width: 6),
          SizedBox(width: 90, child: Text(money(values[index]), textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11))),
        ]),
      )),
      const SizedBox(height: 8),
      const Text('The bars show the size of each ending balance; red means negative. '
        'Upcoming expenses have not yet been deducted.', style: TextStyle(fontSize: 12)),
    ]));
  }

  Widget _upcoming() {
    final items = [..._data.plannedExpenses]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final today = day(DateTime.now());
    final soon = items.where((e) => !day(e.dueDate).isAfter(today.add(const Duration(days: 7)))).toList();
    final soonTotal = soon.fold<int>(0, (sum, e) => sum + e.amount);
    final afterUpcoming = _balance - soonTotal;
    return _section('Upcoming expenses', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${soon.length} due within 7 days or overdue · ${money(soonTotal)} expected'),
      Text('Balance after these payments: ${money(afterUpcoming)}',
        style: TextStyle(color: afterUpcoming < 0 ? Colors.red.shade700 : null)),
      const Text('This is a projection. Mark an expense paid to record it.'),
      const SizedBox(height: 8),
      if (items.isEmpty) const Text('No upcoming expenses.'),
      ...items.map((expense) {
        final due = day(expense.dueDate);
        final label = due.isBefore(today) ? 'Overdue' : due == today ? 'Due today' : 'Due ${shortDate(due)}';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${expense.title} · ${money(expense.amount)}'),
          subtitle: Text('${expense.category} · $label'),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'paid') { await _pay(expense); return; }
              if (action == 'edit') { await _plannedDialog(expense); return; }
              setState(() => _data.plannedExpenses.removeWhere((e) => e.id == expense.id));
              await _save();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'paid', child: Text('Mark paid')),
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Remove')),
            ],
          ),
        );
      }),
    ]), action: IconButton(
      tooltip: 'Plan expense', icon: const Icon(Icons.add), onPressed: () => _plannedDialog()));
  }

  Widget _limits() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final categories = _data.monthlyLimits.keys.toList()..sort();
    return _section('Spending limits · ${monthName(now)}', Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (categories.isEmpty) const Text('Set a monthly limit to see potential savings.'),
        ...categories.map((category) {
          final limit = _data.monthlyLimits[category]!;
          final spent = _data.transactions.where((t) => !t.isIncome && t.category == category &&
              !t.date.isBefore(start) && t.date.isBefore(end))
              .fold<int>(0, (sum, t) => sum + t.amount);
          final over = spent > limit ? spent - limit : 0;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(category),
            subtitle: Text('Spent ${money(spent)} of ${money(limit)}'
              '${over > 0 ? ' · Potential savings ${money(over)}' : ''}'),
            trailing: IconButton(
              tooltip: 'Remove limit', icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                setState(() => _data.monthlyLimits.remove(category));
                await _save();
              },
            ),
          );
        }),
        const Text('Potential savings means spending above your own limit; '
          'it does not mean a purchase was unnecessary.', style: TextStyle(fontSize: 12)),
      ]), action: IconButton(
        tooltip: 'Set limit', icon: const Icon(Icons.add), onPressed: _limitDialog));
  }

  Widget _transactions() {
    final items = [..._data.transactions]..sort((a, b) => b.date.compareTo(a.date));
    return _section('Transactions', Column(children: [
      if (items.isEmpty) const Text('No transactions yet.'),
      ...items.map((t) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(t.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
          color: t.isIncome ? Colors.green : Colors.red),
        title: Text(t.description),
        subtitle: Text('${t.category} · ${shortDate(t.date)}'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions for ${t.description}',
          onSelected: (action) async {
            if (action == 'edit') { await _transactionDialog(t); return; }
            setState(() => _data.transactions.removeWhere((item) => item.id == t.id));
            await _save();
          },
          itemBuilder: (context) => [
            PopupMenuItem(enabled: false, child: Text('${t.isIncome ? '+' : '-'}${money(t.amount)}')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      )),
    ]), action: IconButton(
      tooltip: 'Add transaction', icon: const Icon(Icons.add), onPressed: () => _transactionDialog()));
  }

  Widget _tasks() {
    final items = [..._data.tasks]..sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      return a.dueDate.compareTo(b.dueDate);
    });
    return _section('Financial to-do list', Column(children: [
      if (items.isEmpty) const Text('No tasks yet.'),
      ...items.map((task) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: task.isDone,
        onChanged: (done) async {
          final index = _data.tasks.indexWhere((t) => t.id == task.id);
          if (index < 0) return;
          setState(() => _data.tasks[index] = task.copyWith(isDone: done ?? false));
          await _save();
        },
        title: Text(task.title, style: TextStyle(
          decoration: task.isDone ? TextDecoration.lineThrough : null)),
        subtitle: Text('Due ${shortDate(task.dueDate)}'),
        secondary: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'edit') { await _taskDialog(task); return; }
            setState(() => _data.tasks.removeWhere((t) => t.id == task.id));
            await _save();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      )),
    ]), action: IconButton(
      tooltip: 'Add task', icon: const Icon(Icons.add), onPressed: () => _taskDialog()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MoneyMap'), actions: [
        if (_saving) const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error ?? 'Could not load data.'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                ))
              : SafeArea(child: ListView(padding: const EdgeInsets.all(14), children: [
                  if (_error != null) Card(
                    color: Colors.red.shade50,
                    child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
                  ),
                  _summary(),
                  _reports(),
                  _upcoming(),
                  _limits(),
                  _transactions(),
                  _tasks(),
                ])),
    );
  }
}
