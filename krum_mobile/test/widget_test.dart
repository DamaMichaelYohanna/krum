import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krum/main.dart';
import 'package:krum/services/api_service.dart';
import 'package:krum/services/sync_service.dart';
import 'package:krum/providers/store_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows login screen when unauthenticated', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const KrumApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Register Store'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
  });

  testWidgets('shows the Krum dashboard when authenticated', (tester) async {
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'mock_access_token',
      'jwt_refresh_token': 'mock_refresh_token',
    });
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const KrumApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Krum Store'), findsOneWidget);
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Sell'), findsWidgets);
  });
}
