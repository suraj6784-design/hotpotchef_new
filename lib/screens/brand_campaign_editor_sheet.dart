import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/kitchen_media.dart';
import '../utils/app_theme.dart';
import '../utils/network.dart';
import '../widgets/sponsored_placement_banner.dart';

Future<bool> showBrandCampaignEditorSheet(
  BuildContext context, {
  required Map<String, dynamic> row,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _BrandCampaignEditorSheet(row: row),
  );
  return saved == true;
}

class _BrandCampaignEditorSheet extends StatefulWidget {
  const _BrandCampaignEditorSheet({required this.row});

  final Map<String, dynamic> row;

  @override
  State<_BrandCampaignEditorSheet> createState() => _BrandCampaignEditorSheetState();
}

class _BrandCampaignEditorSheetState extends State<_BrandCampaignEditorSheet> {
  late final TextEditingController _url;
  late final TextEditingController _label;
  DateTime? _endsAt;
  TimeOfDay? _dailyStart;
  TimeOfDay? _dailyEnd;
  String? _imageUrl;
  String? _videoUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _url = TextEditingController(text: row['cta_url']?.toString() ?? '');
    _label = TextEditingController(text: row['cta_label']?.toString() ?? 'Learn more');
    _endsAt = DateTime.tryParse(row['ends_at']?.toString() ?? '')?.toLocal();
    _dailyStart = _timeFromMinute(row['daily_start_minute']);
    _dailyEnd = _timeFromMinute(row['daily_end_minute']);
    _imageUrl = row['image_url']?.toString();
    _videoUrl = row['video_url']?.toString();
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  TimeOfDay? _timeFromMinute(dynamic raw) {
    final mins = int.tryParse(raw?.toString() ?? '');
    if (mins == null) return null;
    return TimeOfDay(hour: (mins ~/ 60).clamp(0, 23), minute: (mins % 60).clamp(0, 59));
  }

  int? _minuteOf(TimeOfDay? t) => t == null ? null : t.hour * 60 + t.minute;

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 400)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endsAt ?? date.add(const Duration(hours: 21))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _endsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickDaypart({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start
          ? (_dailyStart ?? const TimeOfDay(hour: 9, minute: 0))
          : (_dailyEnd ?? const TimeOfDay(hour: 21, minute: 0)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _dailyStart = picked;
      } else {
        _dailyEnd = picked;
      }
    });
  }

  Future<void> _upload({required bool video}) async {
    final id = widget.row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final picker = ImagePicker();
    setState(() => _uploading = true);
    try {
      if (video) {
        final clip = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: 30),
        );
        if (clip == null) return;
        final url = await uploadAdCampaignAsset(
          campaignId: id,
          filePath: clip.path,
          contentType: 'video/mp4',
        );
        if (!mounted) return;
        setState(() => _videoUrl = url);
      } else {
        final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 78, maxWidth: 1600);
        if (image == null) return;
        final mime = image.mimeType ?? 'image/jpeg';
        final url = await uploadAdCampaignAsset(
          campaignId: id,
          filePath: image.path,
          contentType: mime,
        );
        if (!mounted) return;
        setState(() => _imageUrl = url);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final id = widget.row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final uri = sponsoredCtaUri(_url.text);
    if (_url.text.trim().isNotEmpty && uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a full https:// link, e.g. https://brand.com')),
      );
      return;
    }
    var startMin = _minuteOf(_dailyStart);
    var endMin = _minuteOf(_dailyEnd);
    if (startMin != null && endMin == null) endMin = 1440;
    if (endMin != null && startMin == null) startMin = 0;
    final clearDaypart = startMin == null && endMin == null;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc(
        'platform_update_ad_campaign',
        params: {
          'p_campaign_id': id,
          'p_cta_url': uri?.toString() ?? (_url.text.trim().isEmpty ? null : _url.text.trim()),
          'p_cta_label': _label.text.trim().isEmpty ? 'Learn more' : _label.text.trim(),
          'p_image_url': _imageUrl,
          'p_video_url': _videoUrl,
          'p_ends_at': _endsAt?.toUtc().toIso8601String(),
          'p_daily_start_minute': startMin,
          'p_daily_end_minute': endMin,
          'p_clear_ends_at': _endsAt == null,
          'p_clear_daypart': clearDaypart,
          'p_clear_video': (_videoUrl ?? '').trim().isEmpty,
        },
      ).withTimeout(NetworkTimeouts.standard);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save campaign: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.row['advertiser_name']?.toString() ?? 'Brand';
    final endLabel = _endsAt == null ? 'No end (runs until you End campaign)' : DateFormat('dd MMM yyyy, hh:mm a').format(_endsAt!);
    String clock(TimeOfDay? t) => t == null ? 'All day' : t.format(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.hairlineOf(context), borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Schedule & media', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.onSurfaceOf(context))),
            const SizedBox(height: 4),
            Text(brand, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Learn more link *',
                hintText: 'https://www.example.com',
                helperText: 'Must include https:// or the diner tap will do nothing',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Button label',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Campaign end'),
              subtitle: Text(endLabel),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_endsAt != null)
                    TextButton(onPressed: () => setState(() => _endsAt = null), child: const Text('Clear')),
                  TextButton(onPressed: _pickEnd, child: const Text('Set')),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show from (local)'),
              subtitle: Text(clock(_dailyStart)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dailyStart != null)
                    TextButton(onPressed: () => setState(() => _dailyStart = null), child: const Text('Clear')),
                  TextButton(onPressed: () => _pickDaypart(start: true), child: const Text('Set')),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show until (local)'),
              subtitle: Text(clock(_dailyEnd)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dailyEnd != null)
                    TextButton(onPressed: () => setState(() => _dailyEnd = null), child: const Text('Clear')),
                  TextButton(onPressed: () => _pickDaypart(start: false), child: const Text('Set')),
                ],
              ),
            ),
            const Text(
              'Leave from/until empty to show all day. Overnight windows are allowed (e.g. 8:00 PM–2:00 AM).',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.35),
            ),
            const SizedBox(height: 16),
            const Text('Creative', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _uploading ? null : () => _upload(video: false),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text((_imageUrl ?? '').isEmpty ? 'Upload still' : 'Replace still'),
                ),
                OutlinedButton.icon(
                  onPressed: _uploading ? null : () => _upload(video: true),
                  icon: const Icon(Icons.videocam_outlined, size: 18),
                  label: Text((_videoUrl ?? '').isEmpty ? 'Upload clip (≤30s)' : 'Replace clip'),
                ),
                if ((_videoUrl ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _videoUrl = null),
                    child: const Text('Remove clip'),
                  ),
              ],
            ),
            if (_uploading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if ((_imageUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Still saved', style: TextStyle(fontSize: 12, color: AppTheme.success)),
            ],
            if ((_videoUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Clip saved — loops muted on diner Home', style: TextStyle(fontSize: 12, color: AppTheme.success)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving || _uploading ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: Text(_saving ? 'Saving…' : 'Save campaign'),
            ),
          ],
        ),
      ),
    );
  }
}
