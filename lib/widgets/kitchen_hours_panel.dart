import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/kitchen_promise.dart';

class KitchenHoursPanel extends StatelessWidget {
  const KitchenHoursPanel({
    super.key,
    required this.weeklyHours,
    this.prepMinutes,
    this.compact = false,
  });

  final dynamic weeklyHours;
  final int? prepMinutes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hours = parseKitchenWeeklyHours(weeklyHours);
    final accepting = kitchenHoursAccepting(hours);
    if (hours.isEmpty) {
      return Text(
        'Hours not posted · ${accepting ? 'online when the chef is taking orders' : 'currently closed'}',
        style: AppTheme.caption,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          accepting ? kitchenWeeklyHoursLabel(hours) : 'Closed now · ${kitchenWeeklyHoursLabel(hours)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 12 : 14,
            color: accepting ? AppTheme.onSurfaceOf(context) : AppTheme.error,
          ),
        ),
        if (prepMinutes != null && prepMinutes! > 0) ...[
          const SizedBox(height: 2),
          Text('Prep window ${prepMinutes} min', style: AppTheme.caption),
        ],
        if (!compact) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < kKitchenHourKeys.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(kKitchenHourLabels[i], style: AppTheme.micro.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Expanded(child: Text(_dayLabel(hours[kKitchenHourKeys[i]]), style: AppTheme.caption)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _dayLabel(dynamic day) {
    if (day is! Map || day['closed'] == true) return 'Closed';
    final open = parseKitchenClockMinutes(day['open']?.toString());
    final close = parseKitchenClockMinutes(day['close']?.toString());
    if (open == null || close == null) return 'Closed';
    return '${formatKitchenClockLabel(open)}–${formatKitchenClockLabel(close)}';
  }
}
