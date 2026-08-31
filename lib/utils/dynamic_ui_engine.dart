// lib/utils/dynamic_ui_engine.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class DynamicUIEngine extends StatefulWidget {
  final String screenName;

  const DynamicUIEngine({super.key, required this.screenName});

  @override
  State<DynamicUIEngine> createState() => _DynamicUIEngineState();
}

class _DynamicUIEngineState extends State<DynamicUIEngine> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _configFuture;

  @override
  void initState() {
    super.initState();
    // Cache the future in initState to prevent network refetch storms on parent rebuilds
    _configFuture = _fetchScreenConfig();
  }

  Future<List<Map<String, dynamic>>> _fetchScreenConfig() async {
    try {
      final response = await _supabase
          .from('remote_ui_config')
          .select()
          .eq('screen_name', widget.screenName)
          .eq('is_active', true)
          .order('priority_order', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to fetch remote UI configuration');
      return [];
    }
  }

  // --- Safe Hex Color Parser ---
  Color _parseColor(String? hexString, Color fallbackColor) {
    if (hexString == null || hexString.trim().isEmpty) return fallbackColor;
    try {
      var hex = hexString.replaceAll('#', '').trim();
      if (hex.length == 6) {
        hex = 'FF$hex'; // Add full opacity prefix if missing
      }
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return fallbackColor;
    }
  }

  Widget _buildComponent(String type, Map<String, dynamic> props) {
    switch (type) {
      case 'promo_banner':
        final bgColor = _parseColor(props['bg_color'], const Color(0xFFFFF3E0));
        final textColor = _parseColor(props['text_color'], const Color(0xFFFF9800));
        final title = props['title']?.toString() ?? '';
        final subtitle = props['subtitle']?.toString() ?? '';

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (title.isNotEmpty && subtitle.isNotEmpty) const SizedBox(height: 6),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black87, fontSize: 13),
                ),
            ],
          ),
        );
      default:
        // Graceful fallback for unhandled remote components
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _configFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Optional shimmer or minimal placeholder while fetching remote layout
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final configs = snapshot.data!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: configs
              .map((config) => _buildComponent(
                    config['component_type']?.toString() ?? '',
                    Map<String, dynamic>.from(config['properties'] ?? {}),
                  ))
              .toList(),
        );
      },
    );
  }
}