import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../widgets/customer_ui_components.dart';
import '../widgets/sponsored_placement_banner.dart';

/// Chef brand-referral intake. Pricing and go-live stay with the platform.
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
  final _contact = TextEditingController();

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
    _contact.dispose();
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
          SnackBar(content: Text('Could not load brand referrals. ($e)')),
        );
      }
    }
  }

  Future<void> _submit({required bool forReview}) async {
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
        const SnackBar(content: Text('Add a suggested headline')),
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
        'cta_url': sponsoredCtaUri(_ctaUrl.text.trim())?.toString(),
        'cta_label': 'Learn more',
        'reach_mode': _reach,
        'city': _reach == 'targeted' ? _city.text.trim() : null,
        'status': forReview ? 'pending_review' : 'draft',
        'source_role': 'chef_referral',
        'contact_note': _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        'package_label': _reach == 'overall' ? 'Suggested: overall' : 'Suggested: targeted',
        'starts_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      _brand.clear();
      _title.clear();
      _body.clear();
      _ctaUrl.clear();
      _city.clear();
      _contact.clear();
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            forReview
                ? 'Sent to HotPotChef for pricing and approval. It will not show to diners until we go live.'
                : 'Draft saved. Submit for review when the brand details look right.',
          ),
        ),
      );
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Create ad referral failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save referral: $e'), backgroundColor: Colors.red),
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
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Update ad referral status failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update. Live campaigns are managed by HotPotChef. ($e)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AppTheme.canvasOf(context);
    final onSurface = AppTheme.onSurfaceOf(context);

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: const Text('Refer a brand'),
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
                  'Suggest a grocery or partner brand',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: onSurface),
                ),
                const SizedBox(height: 6),
                const Text(
                  'HotPotChef owns pricing, packages, and when a Sponsored card goes live on diner Home. '
                  'You refer the brand — we review, bill the partner, and publish.',
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
                          labelText: 'Suggested headline *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _body,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Short pitch',
                          hintText: 'What should diners know?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ctaUrl,
                        decoration: const InputDecoration(
                          labelText: 'Brand link (https://…)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _contact,
                        decoration: const InputDecoration(
                          labelText: 'Brand contact (optional)',
                          hintText: 'Phone / email / WhatsApp',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Suggested reach', style: TextStyle(fontWeight: FontWeight.w800, color: onSurface)),
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
                              onPressed: _saving ? null : () => _submit(forReview: false),
                              child: const Text('Save draft'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saving ? null : () => _submit(forReview: true),
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
                                  : const Text('Submit for review'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Your referrals', style: TextStyle(fontWeight: FontWeight.w900, color: onSurface)),
                const SizedBox(height: 8),
                if (_mine.isEmpty)
                  const Text(
                    'No brand referrals yet. Suggest a grocery or partner brand above.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  )
                else
                  ..._mine.map((row) {
                    final status = (row['status'] ?? 'draft').toString();
                    final reach = (row['reach_mode'] ?? 'overall').toString();
                    final editable = status == 'draft' || status == 'pending_review';
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
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.link),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${adCampaignStatusLabel(status)} · ${reach == 'targeted' ? 'Targeted' : 'Overall'}'
                              '${reach == 'targeted' && (row['city']?.toString().isNotEmpty ?? false) ? ' · ${row['city']}' : ''}',
                              style: AppTheme.caption,
                            ),
                            if (editable) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (status == 'draft')
                                    TextButton(
                                      onPressed: () => _setStatus(row['id'].toString(), 'pending_review'),
                                      child: const Text('Submit for review'),
                                    ),
                                  if (status == 'pending_review')
                                    TextButton(
                                      onPressed: () => _setStatus(row['id'].toString(), 'draft'),
                                      child: const Text('Back to draft'),
                                    ),
                                  TextButton(
                                    onPressed: () => _setStatus(row['id'].toString(), 'ended'),
                                    child: const Text('Withdraw'),
                                  ),
                                ],
                              ),
                            ] else if (status == 'live')
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Live on diner Home. Contact HotPotChef to pause or change terms.',
                                  style: AppTheme.caption,
                                ),
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

String adCampaignStatusLabel(String? status) {
  switch ((status ?? '').toLowerCase().trim()) {
    case 'pending_review':
      return 'With HotPotChef for review';
    case 'live':
      return 'Live (platform published)';
    case 'ended':
      return 'Ended';
    case 'draft':
    case '':
      return 'Draft';
    default:
      return status!;
  }
}
