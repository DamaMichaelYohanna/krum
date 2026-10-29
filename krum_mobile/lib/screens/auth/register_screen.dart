import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _businessNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _currency = 'NGN';
  bool _obscurePassword = true;

  @override
  void dispose() {
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Your Store'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Setup Provision Store',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Start managing your products, stock, debts and profit.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),

                  if (provider.errorMessage.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        provider.errorMessage,
                        style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextField(
                    controller: _businessNameController,
                    decoration: const InputDecoration(
                      labelText: 'Store Name',
                      hintText: 'e.g. Mama Ngozi Provisions',
                      prefixIcon: Icon(Icons.store_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Store Phone',
                      hintText: 'e.g. 08012345678',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      prefixIcon: Icon(Icons.monetization_on_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'NGN', child: Text('Nigerian Naira (₦)')),
                      DropdownMenuItem(value: 'GHS', child: Text('Ghanaian Cedi (GH₵)')),
                      DropdownMenuItem(value: 'KES', child: Text('Kenyan Shilling (KSh)')),
                      DropdownMenuItem(value: 'USD', child: Text('US Dollar (\$)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _currency = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Owner Email (Login ID)',
                      hintText: 'e.g. owner@store.com',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password (min 8 chars)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: provider.isLoading
                        ? null
                        : () async {
                            final bizName = _businessNameController.text.trim();
                            final email = _emailController.text.trim();
                            final password = _passwordController.text;
                            if (bizName.isEmpty || email.isEmpty || password.length < 8) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill all fields (password at least 8 characters)')),
                              );
                              return;
                            }
                            final success = await provider.register(
                              businessName: bizName,
                              email: email,
                              password: password,
                              currency: _currency,
                              phone: _phoneController.text.trim(),
                            );
                            if (success && context.mounted) {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: provider.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Create Store', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
