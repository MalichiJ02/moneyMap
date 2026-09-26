import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

class MoneyStorage {
  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/moneymap.json');
  }

  Future<MoneyData> load() async {
    final file = await _file();
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return MoneyData.fromJson(decoded);
    }

    // Import the earlier single-file prototype once. That version stored
    // amounts in kwacha as doubles and used a different filename.
    final directory = await getApplicationDocumentsDirectory();
    final oldFile = File('${directory.path}/moneymap_data.json');
    if (!await oldFile.exists()) return MoneyData();

    final old = jsonDecode(await oldFile.readAsString()) as Map<String, dynamic>;
    final data = MoneyData();
    data.startingBalance = ((old['startingBalance'] as num? ?? 0) * 100).round();
    final oldTransactions = old['transactions'] as List<dynamic>? ?? [];
    for (var index = 0; index < oldTransactions.length; index++) {
      final item = oldTransactions[index] as Map<String, dynamic>;
      final date = DateTime.parse(item['date'] as String);
      if (date.isBefore(data.startingDate)) data.startingDate = day(date);
      data.transactions.add(MoneyTransaction(
        id: 'imported-$index',
        isIncome: item['isIncome'] as bool,
        category: 'Other',
        description: item['description'] as String,
        amount: ((item['amount'] as num) * 100).round(),
        date: date,
      ));
    }
    await save(data);
    return data;
  }

  Future<void> save(MoneyData data) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(data.toJson()), flush: true);
  }
}
