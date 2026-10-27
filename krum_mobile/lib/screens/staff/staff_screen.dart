import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../../theme/app_colors.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    await context.read<StoreProvider>().loadStaff();
    if (mounted) setState(() => _isLoading = false);
  }

  void _showAddStaffDialog(BuildContext context) {
    final provider = context.read<StoreProvider>();
    final isOwner = provider.isOwner;
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'sales';
    bool obscurePassword = true;
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add New Staff Member',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create an account for your cashier or store manager to process sales.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              localError!,
                              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Staff Username',
                      hintText: 'e.g. cashier_john or mary',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'At least 6 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setModalState(() => obscurePassword = !obscurePassword);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Staff Role',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.point_of_sale, size: 18),
                          label: const Text('Cashier (Sales)'),
                          selected: selectedRole == 'sales',
                          selectedColor: const Color(0xFFE6F4EA),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedRole = 'sales');
                          },
                        ),
                      ),
                      if (isOwner) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            avatar: const Icon(Icons.manage_accounts, size: 18),
                            label: const Text('Manager'),
                            selected: selectedRole == 'manager',
                            selectedColor: const Color(0xFFE8EEF9),
                            onSelected: (val) {
                              if (val) setModalState(() => selectedRole = 'manager');
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      selectedRole == 'sales'
                          ? '• Cashiers can log in, process sales, issue receipts, and view inventory.'
                          : '• Managers can restock products, adjust stock, manage expenses, and view sales reports.',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Create Staff Account', style: TextStyle(fontSize: 15)),
                      onPressed: () async {
                        final u = usernameController.text.trim();
                        final p = passwordController.text.trim();
                        if (u.isEmpty) {
                          setModalState(() => localError = 'Please enter a username.');
                          return;
                        }
                        if (p.length < 6) {
                          setModalState(() => localError = 'Password must be at least 6 characters long.');
                          return;
                        }

                        final prov = sheetCtx.read<StoreProvider>();
                        final success = await prov.createStaff(
                          username: u,
                          password: p,
                          role: selectedRole,
                        );

                        if (!mounted) return;
                        if (success) {
                          Navigator.pop(sheetCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Staff member "$u" created successfully!')),
                          );
                        } else {
                          setModalState(() => localError = prov.errorMessage);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRoleDialog(BuildContext context, Map<String, dynamic> staff) {
    final currentRole = staff['role'] ?? 'sales';
    final membershipId = staff['id'] as int;
    final username = staff['username'] ?? 'Staff';

    showDialog(
      context: context,
      builder: (dCtx) {
        String roleToSet = currentRole;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Change Role: $username'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: const Text('Cashier (Sales)'),
                  subtitle: const Text('Sell, checkout, view inventory'),
                  value: 'sales',
                  groupValue: roleToSet,
                  onChanged: (val) {
                    if (val != null) setDialogState(() => roleToSet = val);
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Store Manager'),
                  subtitle: const Text('Restock, stock adjustment, reports'),
                  value: 'manager',
                  groupValue: roleToSet,
                  onChanged: (val) {
                    if (val != null) setDialogState(() => roleToSet = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dCtx);
                  final prov = context.read<StoreProvider>();
                  final success = await prov.updateStaffRole(membershipId, roleToSet);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? '$username role updated to ${roleToSet.toUpperCase()}'
                              : 'Failed: ${prov.errorMessage}',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Update Role'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteStaff(BuildContext context, Map<String, dynamic> staff) {
    final membershipId = staff['id'] as int;
    final username = staff['username'] ?? 'Staff';

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Remove Staff Member'),
        content: Text(
          'Are you sure you want to remove "$username"? They will no longer have access to this store.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dCtx);
              final prov = context.read<StoreProvider>();
              final success = await prov.deleteStaff(membershipId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Staff member "$username" removed' : 'Failed: ${prov.errorMessage}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (role.toLowerCase()) {
      case 'owner':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7E22CE);
        icon = Icons.verified_user;
        label = 'OWNER';
        break;
      case 'manager':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF3730A3);
        icon = Icons.manage_accounts;
        label = 'MANAGER';
        break;
      default:
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        icon = Icons.point_of_sale;
        label = 'CASHIER';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final isOwner = provider.isOwner;
    final staffList = provider.staff;

    final totalCount = staffList.length;
    final cashiersCount = staffList.where((s) => s['role'] == 'sales').length;
    final managersCount = staffList.where((s) => s['role'] == 'manager').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Cashiers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Staff',
            onPressed: _loadStaff,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddStaffDialog(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStaff,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Top Summary Stats Cards
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          label: 'Total Staff',
                          value: '$totalCount',
                          icon: Icons.people_outline,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          label: 'Cashiers',
                          value: '$cashiersCount',
                          icon: Icons.point_of_sale,
                          color: const Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statCard(
                          label: 'Managers',
                          value: '$managersCount',
                          icon: Icons.manage_accounts,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Store Team Members',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  if (staffList.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(Icons.badge_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No team members registered yet',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Add cashiers and managers to handle checkouts and inventory under individual logins.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  else
                    ...staffList.map((member) {
                      final username = member['username'] as String? ?? 'User';
                      final role = (member['role'] as String? ?? 'sales').toLowerCase();
                      final isCurrentSelf = username == provider.username;
                      final isMemberOwner = role == 'owner';

                      return Card(
                        elevation: 0.5,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: role == 'owner'
                                ? const Color(0xFFF3E8FF)
                                : role == 'manager'
                                    ? const Color(0xFFE0E7FF)
                                    : const Color(0xFFD1FAE5),
                            child: Text(
                              username.isNotEmpty ? username[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: role == 'owner'
                                    ? const Color(0xFF7E22CE)
                                    : role == 'manager'
                                        ? const Color(0xFF3730A3)
                                        : const Color(0xFF065F46),
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  username,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrentSelf) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('You', style: TextStyle(fontSize: 10, color: Colors.black87)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                _buildRoleBadge(role),
                                const SizedBox(width: 8),
                                if (member['is_active'] == false)
                                  const Text('• Inactive', style: TextStyle(color: Colors.red, fontSize: 12))
                                else
                                  const Text('• Active', style: TextStyle(color: Colors.green, fontSize: 12)),
                              ],
                            ),
                          ),
                          trailing: isOwner && !isMemberOwner && !isCurrentSelf
                              ? PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (action) {
                                    if (action == 'role') {
                                      _showRoleDialog(context, member);
                                    } else if (action == 'delete') {
                                      _confirmDeleteStaff(context, member);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(
                                      value: 'role',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Change Role'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Remove Staff', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
