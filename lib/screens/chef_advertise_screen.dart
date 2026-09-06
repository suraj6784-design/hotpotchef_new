import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../widgets/customer_ui_components.dart';

/// Chef / partner stub for the third-party advertising monetization framework.
class ChefAdvertiseScreen extends StatefulWidget {
  const ChefAdvertiseScreen({super.key});

  @override
  State<ChefAdvertiseScreen> createState() => _ChefAdvertiseScreenState();
}

class _ChefAdvertiseScreenState extends State<ChefAdvertiseScreen> {
  final _supabase = Supabase.instance.client;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _ctaUrl = TextEditingController();
  final _city = TextEditingController();
  final _brand = TextEditingController();

  String _reach = 'overall';
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _mine = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _ctaUrl.dispose();
    _city.dispose();
    _brand.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await _supabase
          .from('ad_campaigns')
          .select()
          .eq('advertiser_id', uid)
          .order('updated_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _mine = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Load ad campaigns failed');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load campaigns. Apply the ad_campaigns migration if missing. ($e)')),
        );
      }
    }
  }

  Future<void> _createDraft({required bool goLive}) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    final brand = _brand.text.trim();
    final title = _title.text.trim();
    if (brand.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add the brand / partner name')),
      );
      return;
    }
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a campaign headline')),
      );
      return;
    }
    if (_reach == 'targeted' && _city.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Targeted reach needs a city')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _supabase.from('ad_campaigns').insert({
        'advertiser_id': uid,
        'advertiser_name': brand,
        'title': title,
        'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
        'cta_url': _ctaUrl.text.trim().isEmpty ? null : _ctaUrl.text.trim(),
        'cta_label': 'Learn more',
        'reach_mode': _reach,
        'city': _reach == 'targeted' ? _city.text.trim() : null,
        'status': goLive ? 'live' : 'draft',
        'starts_at': DateTime.now().toUtc().toIso8601String(),
        'package_label': _reach == 'overall' ? 'Overall broadcast' : 'Targeted audience',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _brand.clear();
      _title.clear();
      _body.clear();
      _ctaUrl.clear();
      _city.clear();
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(goLive ? 'Brand placement is live on diner Home.' : 'Draft saved.')),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Create ad campaign failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save campaign: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await _supabase.from('ad_campaigns').update({
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      await _refresh();
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Update ad status failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final onSurface = AppTheme.onSurfaceOf(context);

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: const Text('Brand ads'),
        backgroundColor: canvas,
        foregroundColor: onSurface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Brand & partner advertising',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: onSurface),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Third-party placements for grocery brands, pantry labels, and other partners — not your own meal boosts. '
                  'Broadcast overall or to a targeted city. Diners see a clear Sponsored card on Home.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _brand,
                        decoration: const InputDecoration(
                          labelText: 'Brand / partner name *',
                          hintText: 'e.g. Local oil mill, spice brand',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Campaign headline *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _body,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Short body',
                          hintText: 'What should diners know?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ctaUrl,
                        decoration: const InputDecoration(
                          labelText: 'CTA link (https://…)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Reach', style: TextStyle(fontWeight: FontWeight.w800, color: onSurface)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'overall', label: Text('Overall'), icon: Icon(Icons.public, size: 16)),
                          ButtonSegment(value: 'targeted', label: Text('Targeted'), icon: Icon(Icons.my_location, size: 16)),
                        ],
                        selected: {_reach},
                        onSelectionChanged: (s) => setState(() => _reach = s.first),
                      ),
                      if (_reach == 'targeted') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _city,
                          decoration: const InputDecoration(
                            labelText: 'City *',
                            hintText: 'e.g. Pune',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : () => _createDraft(goLive: false),
                              child: const Text('Save draft'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saving ? null : () => _createDraft(goLive: true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Go live'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Partner campaigns', style: TextStyle(fontWeight: FontWeight.w900, color: onSurface)),
                const SizedBox(height: 8),
                if (_mine.isEmpty)
                  const Text(
                    'No brand campaigns yet. Add a grocery or partner placement above.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  )
                else
                  ..._mine.map((row) {
                    final status = (row['status'] ?? 'draft').toString();
                    final reach = (row['reach_mode'] ?? 'overall').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['title']?.toString() ?? 'Campaign',
                              style: TextStyle(fontWeight: FontWeight.w800, color: onSurface),
                            ),
                            if ((row['advertiser_name']?.toString() ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                row['advertiser_name'].toString(),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${status.toUpperCase()} · ${reach == 'targeted' ? 'Targeted' : 'Overall'}'
                              '${reach == 'targeted' && (row['city']?.toString().isNotEmpty ?? false) ? ' · ${row['city']}' : ''}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (status != 'live')
                                  TextButton(
                                    onPressed: () => _setStatus(row['id'].toString(), 'live'),
                                    child: const Text('Set live'),
                                  ),
                                if (status == 'live')
                                  TextButton(
                                    onPressed: () => _setStatus(row['id'].toString(), 'ended'),
                                    child: const Text('End'),
                                  ),
                                if (status != 'draft')
                                  TextButton(
                                    onPressed: () => _setStatus(row['id'].toString(), 'draft'),
                                    child: const Text('Back to draft'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
