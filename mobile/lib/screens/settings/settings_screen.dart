/// DesignMirror AI — Settings Screen
///
/// Profile info, name editing, password change, theme toggle,
/// and dimension unit preference — all in one place.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_event.dart';
import '../../blocs/auth/auth_state.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../config/units.dart';
import '../../repositories/auth_repository.dart';
import '../../services/preferences_service.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _prefs = GetIt.instance<PreferencesService>();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state is AuthAuthenticated ? state.user : null;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ── Profile Section ────────────────────
              _sectionHeader('Profile'),
              _profileTile(user?.fullName ?? '-', user?.email ?? '-'),
              _actionTile(
                icon: Icons.edit_outlined,
                title: 'Change Name',
                onTap: user != null ? () => _showEditName(user.fullName) : null,
              ),
              _actionTile(
                icon: Icons.lock_outline,
                title: 'Change Password',
                onTap: _showChangePassword,
              ),
              const Divider(height: 32),

              // ── Appearance ─────────────────────────
              _sectionHeader('Appearance'),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: _prefs.themeMode,
                builder: (_, mode, __) => _themeTile(mode, colorScheme),
              ),
              const Divider(height: 32),

              // ── Units ──────────────────────────────
              _sectionHeader('Measurement Units'),
              ValueListenableBuilder<DimensionUnit>(
                valueListenable: DimensionFormatter.currentUnit,
                builder: (_, unit, __) => _unitTile(unit, colorScheme),
              ),
              const SizedBox(height: 32),

              // ── About ──────────────────────────────
              _sectionHeader('About'),
              _infoTile('App Version', '0.1.0'),
              const Divider(height: 32),

              // ── Logout ─────────────────────────────
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Icon(Icons.logout_rounded,
                    size: 22, color: AppTheme.error),
                title: Text('Logout',
                    style: TextStyle(
                        fontSize: 15, color: AppTheme.error)),
                onTap: _showLogoutDialog,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // ── Helpers ────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.accent,
              letterSpacing: 0.5)),
    );
  }

  Widget _profileTile(String name, String email) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.accent.withAlpha(30),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(email),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing:
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: const Icon(Icons.info_outline, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: Text(value,
          style: const TextStyle(fontSize: 14, color: Colors.grey)),
    );
  }

  Widget _themeTile(ThemeMode mode, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_outlined, size: 22),
              SizedBox(width: 12),
              Text('Theme', style: TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => _prefs.setThemeMode(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitTile(DimensionUnit unit, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.straighten_outlined, size: 22),
              SizedBox(width: 12),
              Text('Unit', style: TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<DimensionUnit>(
              segments: const [
                ButtonSegment(value: DimensionUnit.meters, label: Text('m')),
                ButtonSegment(value: DimensionUnit.feet, label: Text('ft')),
                ButtonSegment(value: DimensionUnit.inches, label: Text('in')),
              ],
              selected: {unit},
              onSelectionChanged: (s) => _prefs.setDimensionUnit(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Edit Name ──────────────────────────────

  void _showEditName(String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _updateName(name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateName(String name) async {
    try {
      final repo = GetIt.instance<AuthRepository>();
      await repo.updateProfile(fullName: name);
      if (mounted) {
        context.read<AuthBloc>().add(AuthRefreshProfile());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  // ── Change Password ────────────────────────

  void _showChangePassword() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current Password'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password'),
                validator: (v) {
                  if (v == null || v.length < 8) return 'Min 8 characters';
                  if (!v.contains(RegExp(r'[A-Z]'))) {
                    return 'Need one uppercase letter';
                  }
                  if (!v.contains(RegExp(r'[0-9]'))) {
                    return 'Need one digit';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm New Password'),
                validator: (v) =>
                    v != newCtrl.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _changePassword(currentCtrl.text, newCtrl.text);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthBloc>().add(AuthLogoutRequested());
              context.go(AppRoutes.login);
            },
            child: Text('Logout', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(String current, String newPass) async {
    try {
      final repo = GetIt.instance<AuthRepository>();
      await repo.changePassword(
          currentPassword: current, newPassword: newPass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }
}
