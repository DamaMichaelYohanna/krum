import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/store_provider.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'screens/scanner/barcode_scanner_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'screens/sell/pos_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/inventory/product_form_screen.dart';
import 'screens/purchases/add_purchase_screen.dart';
import 'screens/expenses/expenses_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/auth/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();
  final syncService = SyncService(api: apiService);
  final storeProvider = StoreProvider(api: apiService, syncService: syncService);
  await storeProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storeProvider),
      ],
      child: const KrumApp(),
    ),
  );
}

class KrumApp extends StatelessWidget {
  const KrumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krum Store Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Consumer<StoreProvider>(
        builder: (context, storeProvider, _) {
          return storeProvider.isAuthenticated
              ? const AppShell()
              : const LoginScreen();
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _openBarcodeScanner() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan Product Barcode',
          hint: 'Point camera at product barcode',
        ),
      ),
    );
    if (scanned != null && scanned.trim().isNotEmpty && mounted) {
      final code = scanned.trim();
      final provider = context.read<StoreProvider>();
      final product = await provider.findProductOrLookup(code);

      if (!mounted) return;

      if (product != null) {
        if (!product.active) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Product "${product.name}" is marked as inactive.'),
              backgroundColor: Colors.amber.shade800,
            ),
          );
          return;
        }
        provider.addToCart(product);
        _navigateToTab(1); // Switch to Sell tab
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${product.name} to cart!'),
            backgroundColor: AppColors.primary,
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductFormScreen(initialBarcode: code)),
        );
      }
    }
  }

  void _openAddStock() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddPurchaseScreen()),
    );
  }

  void _openAddExpense() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExpensesScreen()),
    );
  }

  void _openProductCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final cartUnits = provider.cartTotalUnits;

    final pages = [
      DashboardScreen(
        onNavigateTab: _navigateToTab,
        onScanBarcode: _openBarcodeScanner,
        onAddStock: _openAddStock,
        onAddExpense: _openAddExpense,
      ),
      PosScreen(
        onOpenProductCreate: _openProductCreate,
      ),
      const InventoryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: cartUnits > 0,
                label: Text('$cartUnits'),
                child: const Icon(Icons.point_of_sale_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: cartUnits > 0,
                label: Text('$cartUnits'),
                child: const Icon(Icons.point_of_sale_rounded),
              ),
              label: 'Sell',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Inventory',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
