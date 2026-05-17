import 'dart:async';
import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/finwise_mvp.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:http/http.dart' as http;

const String finWiseAiBaseUrlSettingKey = "finWiseAiBaseUrl";

String getDefaultFinWiseAiBaseUrl() {
  if (kIsWeb) return "http://localhost:8000";
  return "http://192.168.1.36:8000";  // your PC's IP
}

class FinWiseFinancialSnapshot {
  FinWiseFinancialSnapshot({
    required this.periodStart,
    required this.periodEnd,
    required this.income,
    required this.expenses,
    required this.savings,
    required this.savingsRate,
    required this.transactionCount,
    required this.topCategories,
    required this.recentTransactions,
    required this.budgetStatuses,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final double income;
  final double expenses;
  final double savings;
  final double savingsRate;
  final int transactionCount;
  final List<FinWiseCategoryTotal> topCategories;
  final List<FinWiseRecentTransaction> recentTransactions;
  final List<FinWiseBudgetStatus> budgetStatuses;

  bool get hasTransactions => transactionCount > 0;

  Map<String, dynamic> toJson() {
    return {
      "periodStart": periodStart.toIso8601String(),
      "periodEnd": periodEnd.toIso8601String(),
      "income": income,
      "expenses": expenses,
      "savings": savings,
      "savingsRate": savingsRate,
      "transactionCount": transactionCount,
      "topCategories": topCategories.map((item) => item.toJson()).toList(),
      "recentTransactions": recentTransactions
          .map((item) => item.toJson())
          .toList(),
      "budgetStatuses": budgetStatuses.map((item) => item.toJson()).toList(),
    };
  }
}

class FinWiseCategoryTotal {
  FinWiseCategoryTotal({
    required this.name,
    required this.amount,
    required this.transactionCount,
  });

  final String name;
  final double amount;
  final int transactionCount;

  Map<String, dynamic> toJson() => {
    "name": name,
    "amount": amount,
    "transactionCount": transactionCount,
  };
}

class FinWiseRecentTransaction {
  FinWiseRecentTransaction({
    required this.title,
    required this.category,
    required this.amount,
    required this.income,
    required this.date,
  });

  final String title;
  final String category;
  final double amount;
  final bool income;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    "title": title,
    "category": category,
    "amount": amount,
    "income": income,
    "date": date.toIso8601String(),
  };
}

class FinWiseBudgetStatus {
  FinWiseBudgetStatus({
    required this.name,
    required this.limit,
    required this.spent,
  });

  final String name;
  final double limit;
  final double spent;

  double get remaining => limit - spent;
  double get percentUsed => limit <= 0 ? 0 : spent / limit;

  Map<String, dynamic> toJson() => {
    "name": name,
    "limit": limit,
    "spent": spent,
    "remaining": remaining,
    "percentUsed": percentUsed,
  };
}

class FinWiseAiInsight {
  FinWiseAiInsight({
    required this.summary,
    required this.recommendations,
    required this.investmentLessons,
    required this.scenario,
    required this.riskFlags,
    required this.source,
  });

  final String summary;
  final List<String> recommendations;
  final List<String> investmentLessons;
  final FinWiseScenario scenario;
  final List<String> riskFlags;
  final String source;

  factory FinWiseAiInsight.fromJson(Map<String, dynamic> json) {
    return FinWiseAiInsight(
      summary: _stringValue(json["summary"]),
      recommendations: _stringList(json["recommendations"]),
      investmentLessons: _stringList(json["investmentLessons"]),
      scenario: FinWiseScenario.fromJson(
        (json["scenario"] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      riskFlags: _stringList(json["riskFlags"]),
      source: _stringValue(json["source"], fallback: "gemini"),
    );
  }
}

class FinWiseScenario {
  FinWiseScenario({
    required this.monthlySaving,
    required this.assumedAnnualReturn,
    required this.years,
    required this.projectedAmount,
    required this.explanation,
  });

  final double monthlySaving;
  final double assumedAnnualReturn;
  final int years;
  final double projectedAmount;
  final String explanation;

  factory FinWiseScenario.fromJson(Map<String, dynamic> json) {
    return FinWiseScenario(
      monthlySaving: _doubleValue(json["monthlySaving"]),
      assumedAnnualReturn: _doubleValue(json["assumedAnnualReturn"]),
      years: _intValue(json["years"], fallback: 10),
      projectedAmount: _doubleValue(json["projectedAmount"]),
      explanation: _stringValue(json["explanation"]),
    );
  }
}

class FinWiseAiBundle {
  FinWiseAiBundle({required this.snapshot, required this.insight, this.error});

  final FinWiseFinancialSnapshot snapshot;
  final FinWiseAiInsight insight;
  final String? error;
}

class FinWiseAiInsightsService {
  FinWiseAiInsightsService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<FinWiseAiBundle> loadInsights(AllWallets allWallets) async {
    final FinWiseFinancialSnapshot snapshot = await buildSnapshot(
      allWallets: allWallets,
    );
    if (!snapshot.hasTransactions) {
      return FinWiseAiBundle(
        snapshot: snapshot,
        insight: _fallbackInsight(snapshot),
      );
    }

    try {
      final http.Client client = _client ?? http.Client();
      final Uri uri = Uri.parse(
        "${_baseUrl().replaceAll(RegExp(r'/$'), '')}/api/insights",
      );
      final http.Response response = await client
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: json.encode({
              "app": finWiseAppName,
              "user": {
                "name": (appStateSettings["username"] ?? "").toString(),
                "email": sharedPreferences.getString(finWiseMockEmailKey) ?? "",
              },
              "snapshot": snapshot.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception("AI service returned ${response.statusCode}");
      }

      return FinWiseAiBundle(
        snapshot: snapshot,
        insight: FinWiseAiInsight.fromJson(
          (json.decode(response.body) as Map).cast<String, dynamic>(),
        ),
      );
    } catch (error) {
      return FinWiseAiBundle(
        snapshot: snapshot,
        insight: _fallbackInsight(snapshot),
        error: error.toString(),
      );
    }
  }

  Future<FinWiseFinancialSnapshot> buildSnapshot({
    required AllWallets allWallets,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime periodStart = DateTime(now.year, now.month, 1);
    final DateTime periodEnd = DateTime(
      now.year,
      now.month + 1,
      1,
    ).subtract(const Duration(milliseconds: 1));
    final List<Transaction> transactions =
        (await database
                .watchAllTransactions(
                  startDate: periodStart,
                  endDate: periodEnd,
                )
                .first)
            .where((transaction) => transaction.paid == true)
            .toList();
    final Map<String, TransactionCategory> categories = await database
        .getAllCategoriesIndexed();
    final List<Budget> budgets = await database.getAllBudgets();

    double income = 0;
    double expenses = 0;
    final Map<String, _MutableCategoryTotal> categoryTotals = {};
    final List<FinWiseRecentTransaction> recentTransactions = [];

    for (final Transaction transaction in transactions) {
      final double amount =
          transaction.amount.abs() *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, transaction.walletFk);
      if (transaction.income) {
        income += amount;
      } else {
        expenses += amount;
        final TransactionCategory? category =
            categories[transaction.categoryFk];
        final String categoryName = category?.name ?? "Uncategorized";
        final _MutableCategoryTotal total = categoryTotals.putIfAbsent(
          transaction.categoryFk,
          () => _MutableCategoryTotal(categoryName),
        );
        total.amount += amount;
        total.transactionCount++;
      }

      if (recentTransactions.length < 12) {
        recentTransactions.add(
          FinWiseRecentTransaction(
            title: transaction.name.trim().isEmpty
                ? categories[transaction.categoryFk]?.name ?? "Transaction"
                : transaction.name.trim(),
            category: categories[transaction.categoryFk]?.name ?? "Other",
            amount: amount,
            income: transaction.income,
            date: transaction.dateCreated,
          ),
        );
      }
    }

    final List<FinWiseCategoryTotal> topCategories =
        categoryTotals.values
            .map(
              (item) => FinWiseCategoryTotal(
                name: item.name,
                amount: item.amount,
                transactionCount: item.transactionCount,
              ),
            )
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    final List<FinWiseBudgetStatus> budgetStatuses = [];
    for (final Budget budget in budgets.where((budget) => !budget.income)) {
      final DateTimeRange range = getBudgetDate(budget, now);
      double spent = 0;
      for (final Transaction transaction in transactions) {
        final bool inRange =
            !transaction.dateCreated.isBefore(range.start) &&
            !transaction.dateCreated.isAfter(range.end);
        final bool categoryMatches =
            budget.categoryFks == null ||
            budget.categoryFks!.isEmpty ||
            budget.categoryFks!.contains(transaction.categoryFk);
        if (!transaction.income && inRange && categoryMatches) {
          spent +=
              transaction.amount.abs() *
              amountRatioToPrimaryCurrencyGivenPk(
                allWallets,
                transaction.walletFk,
              );
        }
      }
      budgetStatuses.add(
        FinWiseBudgetStatus(
          name: budget.name,
          limit:
              budget.amount.abs() *
              amountRatioToPrimaryCurrencyGivenPk(allWallets, budget.walletFk),
          spent: spent,
        ),
      );
    }
    budgetStatuses.sort((a, b) => b.percentUsed.compareTo(a.percentUsed));

    final double savings = income - expenses;
    return FinWiseFinancialSnapshot(
      periodStart: periodStart,
      periodEnd: periodEnd,
      income: income,
      expenses: expenses,
      savings: savings,
      savingsRate: income <= 0 ? 0 : savings / income,
      transactionCount: transactions.length,
      topCategories: topCategories.take(6).toList(),
      recentTransactions: recentTransactions,
      budgetStatuses: budgetStatuses.take(5).toList(),
    );
  }

  String _baseUrl() {
    final String? savedUrl = sharedPreferences.getString(
      finWiseAiBaseUrlSettingKey,
    );
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      return savedUrl.trim();
    }
    return getDefaultFinWiseAiBaseUrl();
  }

  FinWiseAiInsight _fallbackInsight(FinWiseFinancialSnapshot snapshot) {
    final double monthlySaving = snapshot.savings > 0 ? snapshot.savings : 0;
    final double projectedAmount = _futureValueMonthly(
      monthlySaving: monthlySaving,
    );
    final String topCategory = snapshot.topCategories.isEmpty
        ? "your largest expense category"
        : snapshot.topCategories.first.name;

    return FinWiseAiInsight(
      summary: snapshot.hasTransactions
          ? "This month you saved ${snapshot.savingsRate.isFinite ? (snapshot.savingsRate * 100).toStringAsFixed(1) : "0"}% of your income. Your highest spending pressure is $topCategory."
          : "Add income and expenses to unlock personalized AI guidance from FinWise.",
      recommendations: snapshot.hasTransactions
          ? [
              "Review $topCategory and set a small weekly reduction target.",
              "Protect your savings first by moving a fixed amount before flexible spending.",
              "Track one investment learning goal this week: SIP basics, compounding, or mutual fund risk.",
            ]
          : [
              "Create one income entry and a few expense entries for this month.",
              "Add categories to make future AI recommendations more specific.",
            ],
      investmentLessons: [
        "A SIP turns monthly savings into a habit and benefits from compounding over time.",
        "Higher returns usually come with higher risk, so compare investments by time horizon and volatility.",
      ],
      scenario: FinWiseScenario(
        monthlySaving: monthlySaving,
        assumedAnnualReturn: 0.12,
        years: 10,
        projectedAmount: projectedAmount,
        explanation:
            "If you invest your current monthly surplus for 10 years at an assumed 12% annual return, compounding can turn small consistent savings into long-term wealth.",
      ),
      riskFlags: snapshot.savings < 0
          ? ["Expenses are higher than income for this period."]
          : [],
      source: "local-fallback",
    );
  }
}

class _MutableCategoryTotal {
  _MutableCategoryTotal(this.name);

  final String name;
  double amount = 0;
  int transactionCount = 0;
}

double _futureValueMonthly({
  required double monthlySaving,
  double annualReturn = 0.12,
  int years = 10,
}) {
  if (monthlySaving <= 0) return 0;
  final double monthlyRate = annualReturn / 12;
  final int months = years * 12;
  double value = 0;
  for (int i = 0; i < months; i++) {
    value = (value + monthlySaving) * (1 + monthlyRate);
  }
  return value;
}

String _stringValue(dynamic value, {String fallback = ""}) {
  final String text = value?.toString() ?? "";
  return text.trim().isEmpty ? fallback : text.trim();
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return [];
}

double _doubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? "") ?? 0;
}

int _intValue(dynamic value, {required int fallback}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? "") ?? fallback;
}
