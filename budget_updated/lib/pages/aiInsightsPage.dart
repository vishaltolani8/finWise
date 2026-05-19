import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/aiInsightsService.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AiInsightsPage extends StatefulWidget {
  const AiInsightsPage({super.key});

  @override
  State<AiInsightsPage> createState() => AiInsightsPageState();
}

class AiInsightsPageState extends State<AiInsightsPage> {
  final ScrollController _scrollController = ScrollController();
  late Future<FinWiseAiBundle> _insightsFuture;
  double? _scenarioMonthlySaving;
  int? _scenarioYears;
  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _insightsFuture = _loadInsights();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void scrollToTop({int duration = 900}) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: duration),
      curve: Curves.easeOutCubic,
    );
  }

  Future<FinWiseAiBundle> _loadInsights() {
    return FinWiseAiInsightsService().loadInsights(
      Provider.of<AllWallets>(context, listen: false),
    );
  }

  void _refresh() {
    setState(() {
      _scenarioMonthlySaving = null;
      _scenarioYears = null;
      _selectedCategoryIndex = 0;
      _insightsFuture = _loadInsights();
    });
  }

  void _setScenarioMonthlySaving(double value) {
    setState(() {
      _scenarioMonthlySaving = value;
    });
  }

  void _setScenarioYears(double value) {
    setState(() {
      _scenarioYears = value.round();
    });
  }

  void _setSelectedCategoryIndex(int index) {
    setState(() {
      _selectedCategoryIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "AI Insights",
      backButton: false,
      scrollController: _scrollController,
      actions: [
        IconButton(
          tooltip: "Refresh insights",
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      listWidgets: [
        FutureBuilder<FinWiseAiBundle>(
          future: _insightsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _AiInsightsLoading();
            }
            if (snapshot.hasError) {
              return _AiMessageCard(
                icon: Icons.error_outline_rounded,
                title: "Could not prepare insights",
                message: snapshot.error.toString(),
                actionLabel: "Try again",
                onAction: _refresh,
              );
            }

            final FinWiseAiBundle bundle = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (bundle.error != null)
                  _AiMessageCard(
                    icon: Icons.cloud_off_rounded,
                    title: "Using local fallback",
                    message:
                        "The AI service did not respond, so FinWise is showing rule-based guidance for now.",
                    compact: true,
                  ),
                if (!bundle.snapshot.hasTransactions)
                  _AiMessageCard(
                    icon: Icons.receipt_long_outlined,
                    title: "Add this month's activity",
                    message:
                        "AI guidance becomes useful after FinWise has income and expense entries to analyze.",
                    compact: true,
                  ),
                _InsightHero(bundle: bundle),
                const SizedBox(height: 12),
                _SnapshotSummary(snapshot: bundle.snapshot),
                const SizedBox(height: 12),
                _InsightSummaryCard(bundle: bundle),
                const SizedBox(height: 12),
                _RecommendationsCard(insight: bundle.insight),
                const SizedBox(height: 12),
                _ScenarioCard(
                  bundle: bundle,
                  monthlySavingOverride: _scenarioMonthlySaving,
                  yearsOverride: _scenarioYears,
                  onMonthlySavingChanged: _setScenarioMonthlySaving,
                  onYearsChanged: _setScenarioYears,
                ),
                const SizedBox(height: 12),
                _TopCategoriesCard(
                  snapshot: bundle.snapshot,
                  selectedIndex: _selectedCategoryIndex,
                  onSelected: _setSelectedCategoryIndex,
                ),
                const SizedBox(height: 12),
                _BudgetVarianceCard(snapshot: bundle.snapshot),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SnapshotSummary extends StatelessWidget {
  const _SnapshotSummary({required this.snapshot});

  final FinWiseFinancialSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 650 ? 4 : 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      childAspectRatio: 1.8,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _MetricTile(
          label: "Income",
          value: convertToMoney(allWallets, snapshot.income),
          color: getColor(context, "incomeAmount"),
        ),
        _MetricTile(
          label: "Expenses",
          value: convertToMoney(allWallets, snapshot.expenses),
          color: getColor(context, "expenseAmount"),
        ),
        _MetricTile(
          label: "Savings",
          value: convertToMoney(allWallets, snapshot.savings),
          color: snapshot.savings >= 0
              ? getColor(context, "incomeAmount")
              : getColor(context, "expenseAmount"),
        ),
        _MetricTile(
          label: "Savings rate",
          value: "${(snapshot.savingsRate * 100).toStringAsFixed(1)}%",
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}

class _InsightHero extends StatelessWidget {
  const _InsightHero({required this.bundle});

  final FinWiseAiBundle bundle;

  @override
  Widget build(BuildContext context) {
    final FinWiseFinancialSnapshot snapshot = bundle.snapshot;
    final double savingsRate = snapshot.savingsRate.isFinite
        ? snapshot.savingsRate.clamp(-1, 1).toDouble()
        : 0;
    final int score = ((savingsRate + 0.2) / 0.5 * 100).clamp(0, 100).round();
    final Color scoreColor = score >= 70
        ? getColor(context, "incomeAmount")
        : score >= 40
        ? Theme.of(context).colorScheme.primary
        : getColor(context, "expenseAmount");
    final String focus = snapshot.topCategories.isEmpty
        ? "add a few expenses"
        : "watch ${snapshot.topCategories.first.name}";
    final String status = score >= 70
        ? "Strong month"
        : score >= 40
        ? "Room to improve"
        : "Needs attention";

    return _AiCard(
      padding: const EdgeInsetsDirectional.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 82,
                width: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 8,
                      color: scoreColor,
                      backgroundColor: getColor(context, "lightDarkAccent"),
                    ),
                    TextFont(
                      text: score.toString(),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      textColor: scoreColor,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFont(
                      text: status,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 6),
                    TextFont(
                      text:
                          "Savings rate ${(snapshot.savingsRate * 100).toStringAsFixed(1)}%. This month, $focus.",
                      fontSize: 14,
                      textColor: getColor(context, "textLight"),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroPill(
                  icon: bundle.insight.source == "groq"
                      ? Icons.bolt_rounded
                      : Icons.offline_bolt_rounded,
                  label:
                      bundle.insight.source == "groq" ? "Groq AI" : "Fallback",
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroPill(
                  icon: Icons.receipt_long_rounded,
                  label: "${snapshot.transactionCount} entries",
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroPill(
                  icon: Icons.flag_rounded,
                  label: snapshot.budgetStatuses.isEmpty
                      ? "No budgets"
                      : "${snapshot.budgetStatuses.length} budgets",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: TextFont(
              text: label,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              maxLines: 1,
              autoSizeText: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AiCard(
      padding: const EdgeInsetsDirectional.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextFont(
            text: label,
            fontSize: 13,
            textColor: getColor(context, "textLight"),
            maxLines: 1,
          ),
          const SizedBox(height: 7),
          TextFont(
            text: value,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            textColor: color,
            maxLines: 1,
            autoSizeText: true,
          ),
        ],
      ),
    );
  }
}

class _InsightSummaryCard extends StatelessWidget {
  const _InsightSummaryCard({required this.bundle});

  final FinWiseAiBundle bundle;

  @override
  Widget build(BuildContext context) {
    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.auto_awesome_rounded,
            title: bundle.insight.source == "groq"
                ? "Groq insight"
                : bundle.insight.source == "local-fallback"
                ? "Financial guidance"
                : "Local guidance",
          ),
          const SizedBox(height: 12),
          TextFont(
            text: bundle.insight.summary,
            fontSize: 15,
            textColor: getColor(context, "black"),
            maxLines: 8,
          ),
          if (bundle.insight.riskFlags.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final String flag in bundle.insight.riskFlags)
              _BulletLine(text: flag, icon: Icons.warning_amber_rounded),
          ],
        ],
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.insight});

  final FinWiseAiInsight insight;

  @override
  Widget build(BuildContext context) {
    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.task_alt_rounded,
            title: "Recommended actions",
          ),
          const SizedBox(height: 12),
          for (final String recommendation in insight.recommendations)
            _BulletLine(text: recommendation),
          if (insight.investmentLessons.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 20),
            const _SectionHeader(
              icon: Icons.school_rounded,
              title: "Investment learning",
            ),
            const SizedBox(height: 10),
            for (final String lesson in insight.investmentLessons)
              _BulletLine(text: lesson, icon: Icons.lightbulb_outline_rounded),
          ],
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.bundle,
    required this.monthlySavingOverride,
    required this.yearsOverride,
    required this.onMonthlySavingChanged,
    required this.onYearsChanged,
  });

  final FinWiseAiBundle bundle;
  final double? monthlySavingOverride;
  final int? yearsOverride;
  final ValueChanged<double> onMonthlySavingChanged;
  final ValueChanged<double> onYearsChanged;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final FinWiseScenario scenario = bundle.insight.scenario;
    final double baselineSaving = scenario.monthlySaving > 0
        ? scenario.monthlySaving
        : (bundle.snapshot.savings > 0 ? bundle.snapshot.savings : 1000);
    final double selectedMonthlySaving = (monthlySavingOverride ?? baselineSaving)
        .clamp(0, baselineSaving * 2)
        .toDouble();
    final int selectedYears = (yearsOverride ?? scenario.years)
        .clamp(1, 20)
        .toInt();
    final double assumedAnnualReturn = scenario.assumedAnnualReturn > 0
        ? scenario.assumedAnnualReturn
        : 0.12;
    final double projectedAmount = _futureValueMonthly(
      monthlySaving: selectedMonthlySaving,
      annualReturn: assumedAnnualReturn,
      years: selectedYears,
    );
    final double sliderMax = baselineSaving <= 0 ? 10000 : baselineSaving * 2;
    final double projectionProgress = projectedAmount <= 0
        ? 0.04
        : (projectedAmount / (sliderMax * selectedYears * 18))
              .clamp(0.08, 1)
              .toDouble();

    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.trending_up_rounded,
            title: "Savings growth scenario",
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: "Monthly saving",
                  value: convertToMoney(allWallets, selectedMonthlySaving),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniMetric(
                  label: "$selectedYears year projection",
                  value: convertToMoney(allWallets, projectedAmount),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SliderBlock(
            label: "Monthly saving",
            value: selectedMonthlySaving,
            min: 0,
            max: sliderMax <= 0 ? 10000 : sliderMax,
            divisions: 20,
            displayValue: convertToMoney(allWallets, selectedMonthlySaving),
            onChanged: onMonthlySavingChanged,
          ),
          const SizedBox(height: 8),
          _SliderBlock(
            label: "Time horizon",
            value: selectedYears.toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            displayValue: "$selectedYears years",
            onChanged: onYearsChanged,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: projectionProgress,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 12),
          TextFont(
            text:
                "Assumes ${(assumedAnnualReturn * 100).toStringAsFixed(0)}% annual return. This is an educational projection, not a guaranteed result.",
            fontSize: 14,
            textColor: getColor(context, "textLight"),
            maxLines: 6,
          ),
        ],
      ),
    );
  }
}

class _SliderBlock extends StatelessWidget {
  const _SliderBlock({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFont(
                text: label,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                maxLines: 1,
              ),
            ),
            TextFont(
              text: displayValue,
              fontSize: 13,
              textColor: getColor(context, "textLight"),
              maxLines: 1,
              autoSizeText: true,
            ),
          ],
        ),
        Slider(
          min: min,
          max: max <= min ? min + 1 : max,
          value: value.clamp(min, max <= min ? min + 1 : max).toDouble(),
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

double _futureValueMonthly({
  required double monthlySaving,
  required double annualReturn,
  required int years,
}) {
  if (monthlySaving <= 0) return 0;
  final double monthlyRate = annualReturn / 12;
  double value = 0;
  for (int i = 0; i < years * 12; i++) {
    value = (value + monthlySaving) * (1 + monthlyRate);
  }
  return value;
}

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({
    required this.snapshot,
    required this.selectedIndex,
    required this.onSelected,
  });

  final FinWiseFinancialSnapshot snapshot;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    if (snapshot.topCategories.isEmpty) {
      return const SizedBox.shrink();
    }
    final double maxAmount = snapshot.topCategories.first.amount;
    final int safeSelectedIndex = selectedIndex
        .clamp(0, snapshot.topCategories.length - 1)
        .toInt();
    final FinWiseCategoryTotal selected =
        snapshot.topCategories[safeSelectedIndex];
    final double monthlyImpact = selected.amount * 0.10;
    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.pie_chart_rounded,
            title: "Top spending categories",
          ),
          const SizedBox(height: 12),
          for (final MapEntry<int, FinWiseCategoryTotal> entry in snapshot
              .topCategories
              .take(5)
              .toList()
              .asMap()
              .entries)
            Tappable(
              onTap: () => onSelected(entry.key),
              borderRadius: 8,
              child: Container(
                margin: const EdgeInsetsDirectional.only(bottom: 10),
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: entry.key == safeSelectedIndex
                      ? Theme.of(context).colorScheme.primary.withValues(
                            alpha: 0.08,
                          )
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFont(
                            text: entry.value.name,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            maxLines: 1,
                          ),
                        ),
                        TextFont(
                          text: convertToMoney(allWallets, entry.value.amount),
                          fontSize: 13,
                          textColor: getColor(context, "textLight"),
                          maxLines: 1,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: maxAmount <= 0
                            ? 0
                            : entry.value.amount / maxAmount,
                        color: entry.key == safeSelectedIndex
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        backgroundColor: getColor(context, "lightDarkAccent"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsetsDirectional.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.savings_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFont(
                    text:
                        "Cut ${selected.name} by 10% to free about ${convertToMoney(allWallets, monthlyImpact)} monthly, or ${convertToMoney(allWallets, monthlyImpact * 12)} yearly.",
                    fontSize: 13.5,
                    maxLines: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetVarianceCard extends StatelessWidget {
  const _BudgetVarianceCard({required this.snapshot});

  final FinWiseFinancialSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    if (snapshot.budgetStatuses.isEmpty) {
      return const SizedBox.shrink();
    }
    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.donut_small_rounded,
            title: "Budget variance",
          ),
          const SizedBox(height: 12),
          for (final FinWiseBudgetStatus budget in snapshot.budgetStatuses.take(
            4,
          ))
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFont(
                          text: budget.name,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          maxLines: 1,
                        ),
                      ),
                      TextFont(
                        text:
                            "${(budget.percentUsed * 100).clamp(0, 999).toStringAsFixed(0)}%",
                        fontSize: 13,
                        textColor: budget.percentUsed > 1
                            ? getColor(context, "expenseAmount")
                            : getColor(context, "textLight"),
                        maxLines: 1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  TextFont(
                    text:
                        "${convertToMoney(allWallets, budget.spent)} of ${convertToMoney(allWallets, budget.limit)}",
                    fontSize: 12.5,
                    textColor: getColor(context, "textLight"),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: budget.percentUsed.clamp(0, 1).toDouble(),
                      color: budget.percentUsed > 1
                          ? getColor(context, "expenseAmount")
                          : null,
                      backgroundColor: getColor(context, "lightDarkAccent"),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFont(
            text: label,
            fontSize: 12,
            textColor: getColor(context, "textLight"),
            maxLines: 1,
          ),
          const SizedBox(height: 5),
          TextFont(
            text: value,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            maxLines: 1,
            autoSizeText: true,
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({
    required this.text,
    this.icon = Icons.check_circle_outline_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: TextFont(
              text: text,
              fontSize: 14,
              maxLines: 6,
              textColor: getColor(context, "black"),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
        const SizedBox(width: 9),
        Expanded(
          child: TextFont(
            text: title,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: getColor(context, "lightDarkAccent")),
      ),
      child: child,
    );
  }
}

class _AiMessageCard extends StatelessWidget {
  const _AiMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: compact ? 12 : 0),
      child: _AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(icon: icon, title: title),
            const SizedBox(height: 10),
            TextFont(
              text: message,
              fontSize: 14,
              textColor: getColor(context, "textLight"),
              maxLines: 5,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              Button(label: actionLabel!, onTap: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiInsightsLoading extends StatelessWidget {
  const _AiInsightsLoading();

  @override
  Widget build(BuildContext context) {
    return _AiCard(
      child: Column(
        children: [
          const SizedBox(height: 16),
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          TextFont(
            text: "Analyzing your spending patterns...",
            fontSize: 15,
            textAlign: TextAlign.center,
            textColor: getColor(context, "textLight"),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
