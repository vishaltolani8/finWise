import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/aiInsightsService.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
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
      _insightsFuture = _loadInsights();
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
                _SnapshotSummary(snapshot: bundle.snapshot),
                const SizedBox(height: 12),
                _InsightSummaryCard(bundle: bundle),
                const SizedBox(height: 12),
                _RecommendationsCard(insight: bundle.insight),
                const SizedBox(height: 12),
                _ScenarioCard(bundle: bundle),
                const SizedBox(height: 12),
                _TopCategoriesCard(snapshot: bundle.snapshot),
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
            title: bundle.insight.source == "local-fallback"
                ? "Financial guidance"
                : "Gemini insight",
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
  const _ScenarioCard({required this.bundle});

  final FinWiseAiBundle bundle;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    final FinWiseScenario scenario = bundle.insight.scenario;
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
                  value: convertToMoney(allWallets, scenario.monthlySaving),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniMetric(
                  label: "${scenario.years} year projection",
                  value: convertToMoney(allWallets, scenario.projectedAmount),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: scenario.monthlySaving <= 0 ? 0.05 : 0.72,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 12),
          TextFont(
            text: scenario.explanation,
            fontSize: 14,
            textColor: getColor(context, "textLight"),
            maxLines: 6,
          ),
        ],
      ),
    );
  }
}

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({required this.snapshot});

  final FinWiseFinancialSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final AllWallets allWallets = Provider.of<AllWallets>(context);
    if (snapshot.topCategories.isEmpty) {
      return const SizedBox.shrink();
    }
    final double maxAmount = snapshot.topCategories.first.amount;
    return _AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.pie_chart_rounded,
            title: "Top spending categories",
          ),
          const SizedBox(height: 12),
          for (final FinWiseCategoryTotal category
              in snapshot.topCategories.take(5))
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFont(
                          text: category.name,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          maxLines: 1,
                        ),
                      ),
                      TextFont(
                        text: convertToMoney(allWallets, category.amount),
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
                      value: maxAmount <= 0 ? 0 : category.amount / maxAmount,
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
