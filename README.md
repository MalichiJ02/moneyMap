# MoneyMap

MoneyMap is a Flutter app for tracking how money moves over time. It helps users record income and expenses, see whether their balance is improving, plan upcoming payments, and identify spending above limits they set for themselves.

**Project status:** Working MVP under development.

## Features

- Set a starting balance and tracking date
- Add, edit, and delete income and expense transactions
- Categorize transactions and choose their dates
- View daily, weekly, and monthly balance trends
- Compare income, expenses, and balance movement with the previous period
- Set monthly spending limits by category
- See spending above a limit as *potential savings*
- Plan upcoming expenses with amounts and due dates
- Mark a planned expense paid to create an expense transaction
- Manage a financial to-do list
- Save data locally on the device

Planned expenses do not reduce the current balance until they are marked paid.

## Built with

- **Flutter and Dart** for the app
- **path_provider** to locate the device's app documents directory
- **JSON file storage** for local data
- **Git and GitHub** for version control

Money amounts are stored internally as whole ngwee to avoid floating-point rounding in calculations.

## Getting started

Install Flutter, then clone and run the project:

```bash
git clone https://github.com/MalichiJ02/moneyMap.git
cd moneyMap
flutter pub get
flutter run
```

To check the Dart and Flutter code:

```bash
flutter analyze
```

This version is intended for Android, iOS, and Flutter desktop. Its local file storage is not implemented for Flutter web.

## How the balance works

```text
Current balance = Starting balance + Recorded income − Recorded expenses
```

The starting balance is a snapshot of money the user already has. It is not counted again as income.

For example:

| Entry | Amount |
|---|---:|
| Starting balance | K500.00 |
| Income | +K200.00 |
| Transport | −K80.00 |
| Food | −K50.00 |
| **Current balance** | **K570.00** |

If the user then plans a K300 rent payment, the current balance remains K570.00. Once the payment is marked paid, MoneyMap records the expense and the balance becomes K270.00.

## Spending limits

Users can set a monthly limit for an expense category. If Food has a K40 limit and recorded Food spending reaches K50, MoneyMap shows **K10 potential savings**.

This amount means spending exceeded the user's chosen limit. It does not assume the purchase was unnecessary.

## Project structure

```text
lib/
├── main.dart      # App entry point and theme
├── home.dart      # Screens, forms, reports, and interactions
├── models.dart    # Data models and money helpers
└── storage.dart   # Local data loading and saving
```

## Current limitations

- Data is stored on one device; there is no account sync or backup yet.
- Uninstalling the app may remove its local data.
- Reports use recorded transactions; they depend on the user entering accurate information.
- The app has not yet completed a full release test across supported devices.

## Next improvements

- Automated tests for money calculations and reports
- Data export and backup
- Recurring income and expenses
- Better charts and more detailed financial insights
- Accessibility and interface improvements

## About this project

I am building MoneyMap as a practical software development and learning project. It grew from a real need to understand cash flow, upcoming obligations, and whether financial habits are improving. I use development tools and AI assistance while working on the app, and I review, test, and continue learning from the code.
