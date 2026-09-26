import 'package:flutter/material.dart';

import 'models.dart';
import 'password.dart';
import 'storage.dart';

class MoneyMapHome extends StatefulWidget {
  const MoneyMapHome({super.key, required this.onLock, required this.passwords});

  final VoidCallback onLock;
  final LocalPassword passwords;

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
  int _page = 0;
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
    final route = DialogRoute<(int, DateTime)>(
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
    final result = await Navigator.of(context).push(route);
    await route.completed;
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
    final route = DialogRoute<MoneyTransaction>(
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
    final result = await Navigator.of(context).push(route);
    await route.completed;
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
    final route = DialogRoute<PlannedExpense>(
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
    final result = await Navigator.of(context).push(route);
    await route.completed;
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
    final route = DialogRoute<(String, int)>(
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
    final result = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => _data.monthlyLimits[result.$1] = result.$2);
    await _save();
  }

  Future<void> _taskDialog([MoneyTask? existing]) async {
    final controller = TextEditingController(text: existing?.title ?? '');
    var due = existing?.dueDate ?? day(DateTime.now());
    final route = DialogRoute<MoneyTask>(
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
    final result = await Navigator.of(context).push(route);
    await route.completed;
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

  Future<void> _recurringDialog([RecurringEntry? existing]) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final amount = TextEditingController(text: existing == null ? '' : inputMoney(existing.amount));
    var income = existing?.isIncome ?? false;
    var category = existing?.category ?? expenseCategories.first;
    var frequency = existing?.frequency ?? 'monthly';
    var due = existing?.nextDate ?? day(DateTime.now());
    final route = DialogRoute<RecurringEntry>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Add repeating item' : 'Edit repeating item'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            DropdownButtonFormField<bool>(
              initialValue: income, decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: false, child: Text('Expense')),
                DropdownMenuItem(value: true, child: Text('Income')),
              ],
              onChanged: (value) { if (value != null) {
                update(() {
                income = value;
                category = income ? incomeCategories.first : expenseCategories.first;
              });
              } },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: ValueKey(income), initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: (income ? incomeCategories : expenseCategories)
                .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (value) { if (value != null) update(() => category = value); },
            ),
            const SizedBox(height: 10),
            TextField(controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount in kwacha')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: frequency, decoration: const InputDecoration(labelText: 'Repeats'),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (value) { if (value != null) update(() => frequency = value); },
            ),
            TextButton.icon(icon: const Icon(Icons.calendar_today),
              label: Text('Next due ${shortDate(due)}'),
              onPressed: () async {
                final picked = await _pickDate(due);
                if (picked != null && dialogContext.mounted) update(() => due = picked);
              }),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final parsed = parseMoney(amount.text);
              if (parsed == null || title.text.trim().isEmpty) {
                _message('Enter a name and an amount above K0.'); return;
              }
              Navigator.pop(dialogContext, RecurringEntry(
                id: existing?.id ?? _id(), title: title.text.trim(), isIncome: income,
                category: category, amount: parsed, nextDate: due, frequency: frequency,
              ));
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    title.dispose(); amount.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _data.recurring.add(result);
      } else {
        final index = _data.recurring.indexWhere((e) => e.id == existing.id);
        if (index >= 0) _data.recurring[index] = result;
      }
    });
    await _save();
  }

  Future<void> _recordRecurring(RecurringEntry entry) async {
    final label = entry.isIncome ? 'received' : 'paid';
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark $label?'),
        content: Text('Record ${money(entry.amount)} as ${entry.isIncome ? 'income' : 'an expense'} today?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('Mark $label')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    final index = _data.recurring.indexWhere((e) => e.id == entry.id);
    if (index < 0) return;
    setState(() {
      _data.transactions.add(MoneyTransaction(id: _id(), isIncome: entry.isIncome,
        category: entry.category, description: entry.title, amount: entry.amount,
        date: day(DateTime.now())));
      _data.recurring[index] = entry.next();
    });
    await _save();
  }

  Widget _recurring() {
    final items = [..._data.recurring]..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return _section('Repeating money', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (items.isEmpty) const Text('Add rent, salary, subscriptions, or other repeating items.'),
      ...items.map((entry) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(entry.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
          color: entry.isIncome ? Colors.greenAccent : Colors.orangeAccent),
        title: Text('${entry.title} · ${money(entry.amount)}'),
        subtitle: Text('${entry.frequency} · Next ${shortDate(entry.nextDate)}'),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'record') { await _recordRecurring(entry); return; }
            if (action == 'edit') { await _recurringDialog(entry); return; }
            setState(() => _data.recurring.removeWhere((e) => e.id == entry.id));
            await _save();
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'record', child: Text(entry.isIncome ? 'Mark received' : 'Mark paid')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
      )),
    ]), action: IconButton(tooltip: 'Add repeating item',
      icon: const Icon(Icons.add), onPressed: () => _recurringDialog()));
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
      const Text('Ending balance curve'),
      const SizedBox(height: 8),
      SizedBox(height: 190, width: double.infinity,
        child: CustomPaint(painter: _BalanceLinePainter(values))),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var index = 0; index < starts.length; index++)
          Expanded(child: Text(_periodLabel(starts[index]), textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9))),
      ]),
      Text('From ${money(values.first)} to ${money(values.last)}',
        style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      const Text('Upcoming expenses have not yet been deducted from the curve.',
        style: TextStyle(fontSize: 12)),
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

  Widget _forecast() {
    final today = day(DateTime.now());
    final cutoff = today.add(const Duration(days: 30));
    final events = <(DateTime, int, String)>[];
    for (final expense in _data.plannedExpenses) {
      if (!day(expense.dueDate).isAfter(cutoff)) {
        events.add((day(expense.dueDate).isBefore(today) ? today : day(expense.dueDate),
          -expense.amount, expense.title));
      }
    }
    for (final entry in _data.recurring) {
      var next = entry;
      for (var count = 0; count < 60 && !day(next.nextDate).isAfter(cutoff); count++) {
        events.add((day(next.nextDate).isBefore(today) ? today : day(next.nextDate),
          entry.isIncome ? entry.amount : -entry.amount, entry.title));
        next = next.next();
      }
    }
    events.sort((a, b) => a.$1.compareTo(b.$1));
    var projected = _balance;
    var lowest = projected;
    DateTime? shortfall;
    for (final event in events) {
      projected += event.$2;
      if (projected < lowest) lowest = projected;
      if (projected < 0 && shortfall == null) shortfall = event.$1;
    }
    return _section('Next 30 days', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Projected closing balance: ${money(projected)}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Text('Lowest projected balance: ${money(lowest)}'),
      if (shortfall != null) Text('Possible shortfall on ${shortDate(shortfall)}',
        style: const TextStyle(color: Color(0xFFFF8D9B), fontWeight: FontWeight.bold))
      else Text(events.isEmpty ? 'Plan income and bills to see a forecast.'
          : 'No shortfall indicated by the amounts entered.',
        style: const TextStyle(color: Color(0xFF6DE7C0))),
      const SizedBox(height: 8),
      const Text('This forecast includes planned and repeating items, not unplanned spending. '
        'Expected income is not guaranteed.', style: TextStyle(fontSize: 12)),
    ]));
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

  Future<void> _changePassword() async {
    final old = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final route = DialogRoute<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change password'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: old, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 12),
          TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
          const SizedBox(height: 12),
          TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (next.text.length < 8 || next.text != confirm.text) {
              _message('Use 8+ characters and make sure the new passwords match.');
              return;
            }
            Navigator.pop(dialogContext, (old.text, next.text));
          }, child: const Text('Change')),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    old.dispose(); next.dispose(); confirm.dispose();
    if (result == null || !mounted) return;
    try {
      final changed = await widget.passwords.change(result.$1, result.$2);
      _message(changed ? 'Password changed.' : 'Current password was incorrect.');
    } catch (error) {
      _message('Password change failed: $error');
    }
  }

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(14), children: [
    if (_error != null) Card(color: const Color(0xFF632939),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
    _summary(),
    _forecast(),
    _section('Quick actions', Wrap(spacing: 10, runSpacing: 8, children: [
      FilledButton.icon(onPressed: () => _transactionDialog(),
        icon: const Icon(Icons.add), label: const Text('Record money')),
      OutlinedButton.icon(onPressed: () => _plannedDialog(),
        icon: const Icon(Icons.event), label: const Text('Plan payment')),
    ])),
    _upcoming(),
  ]);

  Widget _settings() => ListView(padding: const EdgeInsets.all(14), children: [
    _section('Security', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('A password locks MoneyMap on this device.'),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: _changePassword,
        icon: const Icon(Icons.password), label: const Text('Change password')),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: widget.onLock,
        icon: const Icon(Icons.lock_outline), label: const Text('Lock now')),
    ])),
    _section('Your data', const Text(
      'Your records are currently saved in this device’s app files. '
      'The password locks the interface; it does not encrypt the financial data file. '
      'Uninstalling the app may erase the data. There is no online account or recovery service yet.'
    )),
  ]);

  Widget _pageContent() {
    switch (_page) {
      case 0: return _dashboard();
      case 1: return ListView(padding: const EdgeInsets.all(14), children: [_transactions()]);
      case 2: return ListView(padding: const EdgeInsets.all(14), children: [_reports(), _limits()]);
      case 3: return ListView(padding: const EdgeInsets.all(14), children: [_forecast(), _upcoming(), _recurring(), _tasks()]);
      default: return _settings();
    }
  }

  void _selectPage(int page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(const ['Overview', 'Transactions', 'Trends', 'Planner', 'Settings'][_page]), actions: [
        if (_saving) const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ]),
      drawer: Drawer(child: SafeArea(child: ListView(children: [
        const DrawerHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end, children: [
            Icon(Icons.account_balance_wallet_outlined, size: 42, color: Color(0xFF62C4FF)),
            SizedBox(height: 10),
            Text('MoneyMap', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            Text('See where your money moves'),
          ])),
        for (final (index, label, icon) in const [
          (0, 'Overview', Icons.home_outlined),
          (1, 'Transactions', Icons.receipt_long_outlined),
          (2, 'Trends and limits', Icons.show_chart),
          (3, 'Planner', Icons.event_note_outlined),
          (4, 'Settings and security', Icons.settings_outlined),
        ])
          ListTile(leading: Icon(icon), title: Text(label), selected: _page == index,
            onTap: () { Navigator.pop(context); _selectPage(index); }),
      ]))),
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
              : SafeArea(child: _pageContent()),
      bottomNavigationBar: _loading || _loadFailed || _page == 4 ? null : NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: _selectPage,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Trends'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), label: 'Plan'),
        ],
      ),
    );
  }
}

class _BalanceLinePainter extends CustomPainter {
  const _BalanceLinePainter(this.values);
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const pad = 14.0;
    final low = values.reduce((a, b) => a < b ? a : b).toDouble();
    final high = values.reduce((a, b) => a > b ? a : b).toDouble();
    final spread = high == low ? 1.0 : high - low;
    final bottom = size.height - pad;
    final width = size.width - pad * 2;
    final height = size.height - pad * 2;
    final grid = Paint()..color = const Color(0xFF344E6B)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = pad + i * height / 3;
      canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y), grid);
    }
    final points = List<Offset>.generate(values.length, (index) {
      final x = pad + (values.length == 1 ? width / 2 : index * width / (values.length - 1));
      final y = bottom - ((values[index] - low) / spread) * height;
      return Offset(x, y);
    });
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) { path.lineTo(points[i].dx, points[i].dy); }
    final area = Path.from(path)..lineTo(points.last.dx, bottom)..lineTo(points.first.dx, bottom)..close();
    canvas.drawPath(area, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0x7754ADFF), Color(0x0054ADFF)],
    ).createShader(Offset.zero & size));
    final line = Paint()..color = const Color(0xFF62C4FF)..strokeWidth = 3
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);
    for (final point in points) {
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFFBCE8FF));
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceLinePainter oldDelegate) =>
      oldDelegate.values.length != values.length ||
      List.generate(values.length, (i) => values[i] != oldDelegate.values[i]).contains(true);
}
