import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/sync_status_badge.dart';
import '../../theme/app_colors.dart';
import '../sales/sales_history_screen.dart';
import '../inventory/low_stock_screen.dart';

class DashboardScreen extends StatelessWidget {
  final Function(int) onNavigateTab;
  final VoidCallback onScanBarcode;
  final VoidCallback onAddStock;
  final VoidCallback onAddExpense;

  const DashboardScreen({
    super.key,
    required this.onNavigateTab,
    required this.onScanBarcode,
    required this.onAddStock,
    required this.onAddExpense,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final data = provider.dashboard;
    final currency = provider.business?.currency ?? 'NGN';
    final storeName = provider.business?.name ?? 'My Provision Store';

    final outOfStockProducts = provider.products.where((p) => p.isOutOfStock).toList();
    final lowStockProducts = provider.products.where((p) => p.isLowStock).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await provider.syncNow();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // Premium Animated SliverAppBar
            SliverAppBar(
              expandedHeight: 120.0,
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              pinned: true,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ).animate().fade(duration: 400.ms),
                          Text(
                            storeName,
                            style: TextStyle(fontSize: 20, color: AppColors.textPrimary, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ).animate().fade(delay: 100.ms, duration: 400.ms),
                        ],
                      ),
                    ),
                    const SyncStatusBadge().animate().fade(delay: 200.ms),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Period Selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        _periodChip(context, provider, 'today', 'Today'),
                        const SizedBox(width: 8),
                        _periodChip(context, provider, 'yesterday', 'Yesterday'),
                        const SizedBox(width: 8),
                        _periodChip(context, provider, 'this_week', 'This Week'),
                        const SizedBox(width: 8),
                        _periodChip(context, provider, 'this_month', 'This Month'),
                      ],
                    ),
                  ).animate().fade(delay: 100.ms).slideX(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                  const SizedBox(height: 24),

                  // Financial Cards Grid
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _metricCard(
                          context,
                          title: 'Revenue',
                          value: CurrencyFormatter.format(data.todaySales, currency: currency),
                          icon: Icons.payments_rounded,
                          color: AppColors.primary,
                          bgColor: AppColors.primaryLight,
                          isHero: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SalesHistoryScreen(initialTabIndex: 0)),
                            );
                          },
                        ),
                        _metricCard(
                          context,
                          title: 'Transactions',
                          value: '${data.transactions} sales',
                          icon: Icons.receipt_long_rounded,
                          color: AppColors.info,
                          bgColor: AppColors.info.withValues(alpha: 0.1),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SalesHistoryScreen(initialTabIndex: 1)),
                            );
                          },
                        ),
                        _metricCard(
                          context,
                          title: 'Net Profit',
                          value: CurrencyFormatter.format(data.netProfit, currency: currency),
                          icon: Icons.insights_rounded,
                          color: data.netProfit >= 0 ? AppColors.success : AppColors.error,
                          bgColor: data.netProfit >= 0 ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                        ),
                        _metricCard(
                          context,
                          title: 'Expenses',
                          value: CurrencyFormatter.format(data.expenses, currency: currency),
                          icon: Icons.receipt_long_rounded,
                          color: AppColors.warning,
                          bgColor: AppColors.warning.withValues(alpha: 0.1),
                          onTap: onAddExpense,
                        ),
                        _metricCard(
                          context,
                          title: 'Outstanding Debt',
                          value: CurrencyFormatter.format(
                            data.outstandingDebt > 0
                                ? data.outstandingDebt
                                : provider.customers.fold(0.0, (s, c) => s + c.outstanding),
                            currency: currency,
                          ),
                          icon: Icons.group_off_rounded,
                          color: const Color(0xFFE74C3C),
                          bgColor: const Color(0xFFE74C3C).withValues(alpha: 0.1),
                        ),
                      ],
                    ).animate().fade(delay: 200.ms).slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),

                  const SizedBox(height: 32),

                  // Quick Actions
                  _sectionHeader('Quick Actions').animate().fade(delay: 300.ms),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        _quickActionButton(
                          icon: Icons.point_of_sale_rounded,
                          label: 'Sell',
                          color: AppColors.primary,
                          onTap: () => onNavigateTab(1),
                        ),
                        const SizedBox(width: 16),
                        _quickActionButton(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Scan',
                          color: AppColors.info,
                          onTap: onScanBarcode,
                        ),
                        const SizedBox(width: 16),
                        _quickActionButton(
                          icon: Icons.receipt_long_rounded,
                          label: 'Sales',
                          color: AppColors.primaryDark,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        _quickActionButton(
                          icon: Icons.inventory_2_rounded,
                          label: 'Add Stock',
                          color: AppColors.success,
                          onTap: onAddStock,
                        ),
                        const SizedBox(width: 16),
                        _quickActionButton(
                          icon: Icons.money_off_rounded,
                          label: 'Expense',
                          color: AppColors.warning,
                          onTap: onAddExpense,
                        ),
                      ],
                    ),
                  ).animate().fade(delay: 350.ms).slideX(begin: 0.05, end: 0),

                  const SizedBox(height: 32),

                  // Stock Alerts
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionHeader('Stock Alerts'),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LowStockScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        icon: const Icon(Icons.autorenew_rounded, size: 16),
                        label: const Text('Restock Hub'),
                      ),
                    ],
                  ).animate().fade(delay: 400.ms),
                  
                  if (outOfStockProducts.isEmpty && lowStockProducts.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.2), width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'All products have healthy stock levels.',
                              style: TextStyle(fontSize: 14, color: AppColors.success.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fade(delay: 450.ms).scale(begin: const Offset(0.98, 0.98), curve: Curves.easeOutBack)
                  else ...[
                    ...outOfStockProducts.take(3).map((p) => _stockAlertTile(
                          name: p.name,
                          badgeText: 'Out of stock',
                          badgeColor: AppColors.error,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const LowStockScreen()),
                            );
                          },
                        )).toList().animate(interval: 50.ms).fade(delay: 450.ms).slideX(begin: 0.05),
                    ...lowStockProducts.take(4).map((p) => _stockAlertTile(
                          name: p.name,
                          badgeText: '${CurrencyFormatter.formatQty(p.stockBase)} ${p.baseUnitName} left',
                          badgeColor: AppColors.warning,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const LowStockScreen()),
                            );
                          },
                        )).toList().animate(interval: 50.ms).fade(delay: 500.ms).slideX(begin: 0.05),
                  ],

                  const SizedBox(height: 32),

                  // Top Selling Products
                  if (data.topProducts.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionHeader('Top Sellers'),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SalesHistoryScreen(initialTabIndex: 0)),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          child: const Text('View All Items Sold'),
                        ),
                      ],
                    ).animate().fade(delay: 550.ms),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border, width: 0.5),
                        boxShadow: [
                          BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: data.topProducts.length,
                          separatorBuilder: (_, index) => Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (context, index) {
                            final item = data.topProducts[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 16),
                                ),
                              ),
                              title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              subtitle: Text('${CurrencyFormatter.formatQty(item.quantity)} sold', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              trailing: Text(
                                CurrencyFormatter.format(item.totalSales, currency: currency),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary, letterSpacing: -0.3),
                              ),
                            );
                          },
                        ),
                      ),
                    ).animate().fade(delay: 600.ms).slideY(begin: 0.05),
                    const SizedBox(height: 16),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _periodChip(BuildContext context, StoreProvider provider, String periodKey, String label) {
    final isSelected = provider.dashboardPeriod == periodKey;
    return GestureDetector(
      onTap: () => provider.setDashboardPeriod(periodKey),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.textPrimary : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? AppColors.textPrimary : AppColors.border, width: 1),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    bool isHero = false,
    VoidCallback? onTap,
  }) {
    final width = (MediaQuery.of(context).size.width - 56) / 2;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: width.clamp(140.0, 220.0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isHero ? 24 : 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockAlertTile({
    required String name,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            badgeText,
            style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.1),
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

