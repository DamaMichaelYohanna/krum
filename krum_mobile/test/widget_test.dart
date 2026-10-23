import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krum/main.dart';
import 'package:krum/services/api_service.dart';
import 'package:krum/services/sync_service.dart';
import 'package:krum/providers/store_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the Krum dashboard', (tester) async {
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
