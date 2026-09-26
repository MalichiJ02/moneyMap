# MoneyMap

Flutter app for tracking income, expenses, daily/weekly/monthly balances,
monthly category limits, upcoming expenses, and financial tasks.

## Install in an existing Flutter project

Copy `lib/main.dart`, `lib/models.dart`, `lib/storage.dart`, and `lib/home.dart`
into the project's `lib` folder. The supplied `pubspec.yaml` is complete, but
you can keep your existing one and run `flutter pub add path_provider` instead.

From the project root:

```bash
flutter pub get
flutter run
```

For Android, iOS, and desktop. Local file storage does not work in Flutter web.
Do not uninstall the app if you need its local data: this version has no export,
account sync, or backup feature.

If the earlier single-file version saved `moneymap_data.json`, this version
imports its balance and transactions once. Imported transactions are assigned
the category `Other`; review the starting date and edit categories as needed.

## Example check

1. Set starting balance to K500.00.
2. Add K200.00 income, K80.00 Transport, and K50.00 Food expenses.
3. Current balance should be K570.00 (500 + 200 - 80 - 50).
4. Plan a K300.00 Rent expense due tomorrow. Current balance stays K570.00;
   the projected balance after that payment is K270.00.
5. Mark Rent paid. Current balance becomes K270.00 and one Rent transaction
   appears. Closing and reopening the app should preserve everything.
6. Set a K40.00 Food monthly limit. Potential savings should be K10.00.
7. Switch the trend display among Daily, Weekly, and Monthly.

Transactions are recorded only on or before today. Planned expenses may have
future dates and do not change the actual balance until marked paid. The
starting balance is a snapshot and is not counted as income.
# moneymap-
