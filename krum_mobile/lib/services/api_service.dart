import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String defaultBaseUrl = 'http://127.0.0.1:8000/api';
  String _baseUrl = defaultBaseUrl;

  String? _accessToken;
  String? _refreshToken;

  String get baseUrl => _baseUrl;
  bool get isAuthenticated => _accessToken != null;
  String? get refreshToken => _refreshToken;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('api_base_url') ?? defaultBaseUrl;
    _accessToken = prefs.getString('jwt_access_token');
    _refreshToken = prefs.getString('jwt_refresh_token');
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _baseUrl);
  }

  Future<void> saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_access_token', access);
    await prefs.setString('jwt_refresh_token', refresh);
  }

  Future<void> clearAuth() async {
    _accessToken = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_access_token');
    await prefs.remove('jwt_refresh_token');
  }

  Map<String, String> _headers({bool requireAuth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requireAuth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login/'),
      headers: _headers(requireAuth: false),
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await saveTokens(data['access'], data['refresh']);
      return data;
    } else {
      final err = _parseError(response);
      throw Exception(err);
    }
  }

  Future<Map<String, dynamic>> register({
    required String businessName,
    required String username,
    required String password,
    String currency = 'NGN',
    String phone = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register/'),
      headers: _headers(requireAuth: false),
      body: jsonEncode({
        'business_name': businessName,
        'username': username,
        'password': password,
        'currency': currency,
        'phone': phone,
      }),
    );

    if (response.statusCode == 201) {
      // Auto login
      return await login(username, password);
    } else {
      final err = _parseError(response);
      throw Exception(err);
    }
  }

  Future<Map<String, dynamic>> getBusinessProfile() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/business/me/'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> syncPull() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/sync/pull/'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> syncPush(Map<String, dynamic> payload) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/sync/push/'),
      headers: _headers(),
      body: jsonEncode(payload),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> getDashboard({String period = 'today'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/dashboard/?period=$period'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> getProfitLoss({String period = 'this_month'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/reports/profit-loss/?period=$period'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<List<dynamic>> getSalesReport({String period = 'this_month'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/reports/sales/?period=$period'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<List<dynamic>> getInventoryReport() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/reports/inventory/'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<String> exportReportCsv(String type, {String period = 'this_month'}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/reports/export/?type=$type&period=$period'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return response.body;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/products/'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createUnit(String name, {String symbol = ''}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/units/'),
      headers: _headers(),
      body: jsonEncode({'name': name, 'symbol': symbol}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createCategory(String name) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/categories/'),
      headers: _headers(),
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> addProductUnit(int productId, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/products/$productId/units/'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required double quantityDelta,
    required String reason,
    String reference = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/inventory/adjustments/'),
      headers: _headers(),
      body: jsonEncode({
        'product': productId,
        'quantity_delta': quantityDelta,
        'reason': reason,
        'reference': reference,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> recordCustomerPayment({
    required int customerId,
    required double amount,
    String method = 'cash',
    String reference = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/customer-payments/'),
      headers: _headers(),
      body: jsonEncode({
        'customer': customerId,
        'amount': amount,
        'method': method,
        'reference': reference,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createCustomer(String name, {String phone = ''}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/customers/'),
      headers: _headers(),
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createSupplier(String name, {String phone = ''}) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/suppliers/'),
      headers: _headers(),
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> completePurchase(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/purchases/complete/'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createExpense(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/expenses/'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<List<dynamic>> getExpenses({
    String? period,
    String? startDate,
    String? endDate,
    String? category,
  }) async {
    final queryParams = <String, String>{};
    if (period != null && period.isNotEmpty && period != 'all') queryParams['period'] = period;
    if (startDate != null && startDate.isNotEmpty) queryParams['start_date'] = startDate;
    if (endDate != null && endDate.isNotEmpty) queryParams['end_date'] = endDate;
    if (category != null && category.isNotEmpty && category.toLowerCase() != 'all') queryParams['category'] = category;

    final uri = Uri.parse('$_baseUrl/expenses/').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<void> deleteExpense(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/expenses/$id/'),
      headers: _headers(),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_parseError(response));
    }
  }

  Future<List<dynamic>> getSales({
    String? period,
    String? startDate,
    String? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (period != null && period.isNotEmpty && period != 'all') queryParams['period'] = period;
    if (startDate != null && startDate.isNotEmpty) queryParams['start_date'] = startDate;
    if (endDate != null && endDate.isNotEmpty) queryParams['end_date'] = endDate;

    final uri = Uri.parse('$_baseUrl/sales/').replace(
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(_parseError(response));
  }
  Future<Map<String, dynamic>> reverseSale(dynamic saleId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/sales/$saleId/reverse/'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> updateBusinessProfile(Map<String, dynamic> data) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/business/me/'),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<List<dynamic>> getStaff() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/staff/'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> createStaff({
    required String username,
    required String password,
    String role = 'sales',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/staff/'),
      headers: _headers(),
      body: jsonEncode({
        'username': username,
        'password': password,
        'role': role,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<Map<String, dynamic>> updateStaffRole(int membershipId, String role) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/staff/$membershipId/'),
      headers: _headers(),
      body: jsonEncode({'role': role}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseError(response));
  }

  Future<void> deleteStaff(int membershipId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/staff/$membershipId/'),
      headers: _headers(),
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }
    throw Exception(_parseError(response));
  }


  Future<Map<String, dynamic>?> lookupBarcode(String barcode) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/products/barcode/$barcode/'),
      headers: _headers(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  String _parseError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        if (decoded.containsKey('detail')) return decoded['detail'].toString();
        if (decoded.containsKey('error')) return decoded['error'].toString();
        final firstKey = decoded.keys.first;
        final val = decoded[firstKey];
        if (val is List && val.isNotEmpty) return '$firstKey: ${val.first}';
        return '$firstKey: $val';
      }
    } catch (_) {}
    return 'Server error (${response.statusCode}): ${response.reasonPhrase}';
  }
}
