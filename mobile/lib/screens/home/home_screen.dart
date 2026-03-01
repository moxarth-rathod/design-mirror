/// DesignMirror AI — Home Dashboard
///
/// Premium interior design dashboard with hero greeting,
/// visual feature tiles, and quick-action grid.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/auth/auth_state.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../repositories/catalog_repository.dart';
import '../../repositories/room_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _roomCount = 0;
  int _productCount = 0;
  bool _statsLoaded = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadStats();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final roomRepo = GetIt.instance<RoomRepository>();
      final catalogRepo = GetIt.instance<CatalogRepository>();
      final results = await Future.wait([
        roomRepo.getUserRooms(),
        catalogRepo.getCatalog(page: 1, pageSize: 1),
      ]);
      if (mounted) {
        setState(() {
          _roomCount = (results[0] as List).length;
          _productCount = (results[1] as CatalogPage).total;
          _statsLoaded = true;
        });
        _animCtrl.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _statsLoaded = true);
        _animCtrl.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) context.go(AppRoutes.login);
      },
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _loadStats,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── Hero App Bar ──
              SliverAppBar(
                expandedHeight: 200,
                floating: false,
                pinned: true,
                stretch: true,
                backgroundColor: isDark
                    ? AppTheme.darkSurface
                    : AppTheme.primary,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHero(isDark),
                  collapseMode: CollapseMode.parallax,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    color: Colors.white,
                    onPressed: () => context.push(AppRoutes.settings),
                  ),
                ],
              ),

              // ── Body ──
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuickStats(isDark),
                        const SizedBox(height: 24),
                        _buildSectionLabel('Quick Actions'),
                        const SizedBox(height: 12),
                        _buildQuickActions(isDark),
                        const SizedBox(height: 24),
                        _buildSectionLabel('Explore'),
                        const SizedBox(height: 12),
                        _buildFeatureGrid(isDark),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ── Hero Section
  // ═══════════════════════════════════════════════════

  Widget _buildHero(bool isDark) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final name =
            state is AuthAuthenticated ? state.user.fullName : 'there';
        final hour = DateTime.now().hour;
        final greeting = hour < 12
            ? 'Good Morning'
            : hour < 17
                ? 'Good Afternoon'
                : 'Good Evening';

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                  : [AppTheme.primary, const Color(0xFF0984E3)],
            ),
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(15),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(10),
                  ),
                ),
              ),
              // Content
              Positioned(
                left: 20,
                right: 20,
                bottom: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting,',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withAlpha(180),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Design your perfect space',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withAlpha(160),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════
  // ── Stats Chips
  // ═══════════════════════════════════════════════════

  Widget _buildQuickStats(bool isDark) {
    return Row(
      children: [
        _miniStat(
          Icons.meeting_room_rounded,
          _statsLoaded ? '$_roomCount' : '–',
          _roomCount == 1 ? 'Room' : 'Rooms',
          const Color(0xFF6C5CE7),
          isDark,
        ),
        const SizedBox(width: 12),
        _miniStat(
          Icons.weekend_rounded,
          _statsLoaded ? '$_productCount' : '–',
          'Products',
          AppTheme.accent,
          isDark,
        ),
        const SizedBox(width: 12),
        _miniStat(
          Icons.auto_awesome_rounded,
          'AI',
          'Powered',
          AppTheme.success,
          isDark,
        ),
      ],
    );
  }

  Widget _miniStat(
      IconData icon, String value, String label, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: isDark ? color.withAlpha(20) : color.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(35)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.secondaryTextOf(context))),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ── Section Label
  // ═══════════════════════════════════════════════════

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ── Quick Actions (Add Room + Browse)
  // ═══════════════════════════════════════════════════

  Widget _buildQuickActions(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _actionTile(
            icon: Icons.add_home_rounded,
            label: 'Add Room',
            gradient: isDark
                ? [const Color(0xFF2D1B69), const Color(0xFF11998E)]
                : [const Color(0xFF6C5CE7), const Color(0xFF00CEC9)],
            onTap: _showAddRoomChoice,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionTile(
            icon: Icons.weekend_rounded,
            label: 'Catalog',
            gradient: isDark
                ? [const Color(0xFF4A2C00), const Color(0xFFE17055)]
                : [AppTheme.accent, const Color(0xFFFDCB6E)],
            onTap: () => context.push(AppRoutes.catalog),
          ),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withAlpha(50),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -8,
              child: Transform.rotate(
                angle: math.pi / 12,
                child: Icon(icon, size: 64, color: Colors.white.withAlpha(30)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(height: 8),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ── Feature Grid (2x2)
  // ═══════════════════════════════════════════════════

  Widget _buildFeatureGrid(bool isDark) {
    final features = [
      _FeatureTile(
        icon: Icons.meeting_room_rounded,
        title: 'My Rooms',
        subtitle: '$_roomCount saved',
        color: const Color(0xFF6C5CE7),
        route: AppRoutes.rooms,
        onTap: () async {
          await context.push(AppRoutes.rooms);
          _loadStats();
        },
      ),
      _FeatureTile(
        icon: Icons.favorite_rounded,
        title: 'Wishlist',
        subtitle: 'Saved picks',
        color: const Color(0xFFE84393),
        route: AppRoutes.wishlist,
        onTap: () => context.push(AppRoutes.wishlist),
      ),
      _FeatureTile(
        icon: Icons.history_rounded,
        title: 'History',
        subtitle: 'Past designs',
        color: const Color(0xFF0984E3),
        route: AppRoutes.history,
        onTap: () => context.push(AppRoutes.history),
      ),
      _FeatureTile(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Budget',
        subtitle: 'Plan smart',
        color: const Color(0xFF00B894),
        route: AppRoutes.budget,
        onTap: () => context.push(AppRoutes.budget),
      ),
      _FeatureTile(
        icon: Icons.dashboard_customize_rounded,
        title: 'Layout',
        subtitle: 'Multi-furniture',
        color: const Color(0xFF6C5CE7),
        route: AppRoutes.layoutPlanner,
        onTap: () => context.push(AppRoutes.layoutPlanner),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: features.map((f) => _featureCard(f, isDark)).toList(),
    );
  }

  Widget _featureCard(_FeatureTile tile, bool isDark) {
    return GestureDetector(
      onTap: tile.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? tile.color.withAlpha(18)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? tile.color.withAlpha(40)
                : Colors.grey.withAlpha(25),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tile.color.withAlpha(isDark ? 30 : 18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tile.icon, color: tile.color, size: 22),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tile.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(tile.subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryTextOf(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ── Add Room Choice Bottom Sheet
  // ═══════════════════════════════════════════════════

  void _showAddRoomChoice() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text('How do you want to add a room?',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              _addRoomOption(
                icon: Icons.edit_outlined,
                color: AppTheme.primary,
                title: 'Manual Entry',
                subtitle: 'Type in width, length, and height',
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.push(AppRoutes.manualRoom);
                  _loadStats();
                },
              ),
              const SizedBox(height: 12),
              _addRoomOption(
                icon: Icons.view_in_ar_rounded,
                color: AppTheme.accent,
                title: 'AR Scan',
                subtitle: 'Measure your room using the camera',
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.push(AppRoutes.arScanner);
                  _loadStats();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addRoomOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryTextOf(context))),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 14, color: AppTheme.secondaryTextOf(context)),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String route;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.route,
    required this.onTap,
  });
}
