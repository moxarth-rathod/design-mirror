/// DesignMirror AI — Budget Planner Screen

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../repositories/room_repository.dart';
import '../../services/api_service.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _api = GetIt.instance<ApiService>();
  final _roomRepo = GetIt.instance<RoomRepository>();
  final _budgetCtrl = TextEditingController();

  List<Map<String, dynamic>> _rooms = [];
  String? _selectedRoomId;
  List<Map<String, dynamic>> _picks = [];
  bool _loadingRooms = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await _roomRepo.getRooms();
      _rooms = rooms
          .map((r) => {
                'id': r['id'],
                'room_name': r['room_name'],
                'dimensions': r['dimensions'],
              })
          .where((r) => r['dimensions'] != null)
          .toList();
      if (_rooms.isNotEmpty) _selectedRoomId = _rooms.first['id'] as String;
    } catch (_) {}
    if (mounted) setState(() => _loadingRooms = false);
  }

  Future<void> _search() async {
    final budget = double.tryParse(_budgetCtrl.text.replaceAll(',', ''));
    if (budget == null || budget <= 0 || _selectedRoomId == null) return;

    setState(() {
      _searching = true;
      _error = null;
      _picks = [];
    });
    try {
      final res = await _api.get(
        '/catalog/budget-picks?room_id=$_selectedRoomId&budget_inr=$budget',
      );
      final data = res.data as Map<String, dynamic>;
      _picks = (data['items'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget Planner')),
      body: _loadingRooms
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInputSection(),
                const SizedBox(height: 20),
                if (_searching)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ))
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $_error',
                        style: TextStyle(color: AppTheme.error)),
                  )
                else if (_picks.isNotEmpty)
                  ..._buildResults()
                else if (!_searching && _budgetCtrl.text.isNotEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No furniture found within this budget and room size.',
                        style: TextStyle(color: AppTheme.secondaryTextOf(context)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Find furniture that fits your room and budget',
              style: TextStyle(
                  fontSize: 14, color: AppTheme.secondaryTextOf(context))),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedRoomId,
            decoration: const InputDecoration(
              labelText: 'Select Room',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
            items: _rooms.map((r) {
              return DropdownMenuItem<String>(
                value: r['id'] as String,
                child: Text(r['room_name'] as String? ?? 'Room'),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedRoomId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _budgetCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Budget (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
              hintText: 'e.g. 50000',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed:
                _selectedRoomId != null && !_searching ? _search : null,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Find Furniture'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResults() {
    final budgetInr =
        (double.tryParse(_budgetCtrl.text.replaceAll(',', '')) ?? 0).round();
    int runningTotal = 0;

    return [
      // Header
      Row(
        children: [
          Expanded(
            child: Text('${_picks.length} items within budget',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Budget: ₹${_indianComma(budgetInr)}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent)),
          ),
        ],
      ),
      const SizedBox(height: 12),

      // Product cards with individual price + cumulative tracker
      ...List.generate(_picks.length, (i) {
        final p = _picks[i];
        final priceInr = (p['price_inr'] as num?)?.toInt() ?? 0;
        runningTotal += priceInr;
        final imageUrl = p['image_url'] as String?;
        final withinBudget = runningTotal <= budgetInr;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl, fit: BoxFit.cover)
                          : Container(
                              color: AppTheme.surfaceDimOf(context),
                              child: Icon(Icons.chair_outlined,
                                  color: AppTheme.mutedOf(context)),
                            ),
                    ),
                  ),
                  title: Text(p['name'] as String? ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    '${_capitalize(p['category'] as String? ?? '')}  •  ${p['dimensions'] ?? ''}',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryTextOf(context)),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${_indianComma(priceInr)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.accent)),
                      const SizedBox(height: 2),
                      Text('Total: ₹${_indianComma(runningTotal)}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: withinBudget
                                  ? AppTheme.success
                                  : AppTheme.error)),
                    ],
                  ),
                ),
                // Budget usage bar
                Padding(
                  padding:
                      const EdgeInsets.only(left: 14, right: 14, bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: budgetInr > 0
                          ? (runningTotal / budgetInr).clamp(0.0, 1.0)
                          : 0,
                      minHeight: 4,
                      backgroundColor: Colors.grey.withAlpha(40),
                      color: withinBudget ? AppTheme.success : AppTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),

      // Summary footer
      const Divider(height: 24),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: runningTotal <= budgetInr
              ? AppTheme.success.withAlpha(15)
              : AppTheme.error.withAlpha(15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_picks.length} Products',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.secondaryTextOf(context))),
                Text('Combined Total',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryTextOf(context))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Remaining: ₹${_indianComma((budgetInr - runningTotal).abs())}',
                  style: TextStyle(
                    fontSize: 13,
                    color: runningTotal <= budgetInr
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                ),
                Text(
                  '₹${_indianComma(runningTotal)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: runningTotal <= budgetInr
                        ? AppTheme.success
                        : AppTheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _indianComma(int n) {
    if (n < 0) return '-${_indianComma(-n)}';
    final s = n.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},${last3}';
  }
}
