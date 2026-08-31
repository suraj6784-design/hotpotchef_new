// lib/utils/helpers.dart

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

// Export the theme so all screens automatically inherit it
export 'app_theme.dart'; 

class Validators {
  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    // RFC 5822 compliant standard email regex
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  static String? requiredField(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  static String? pinCode(String? v) {
    if (v == null || v.trim().length != 6) return 'Enter a valid 6-digit PIN code';
    return null;
  }
}

class Formatters {
  static String currency(double value, {String symbol = '₹'}) {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: symbol, decimalDigits: 0);
    return f.format(value);
  }

  static String shortDateTime(DateTime dt) {
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }
}

class Ui {
  static Widget loadingIndicator({double size = 20}) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

// ----------------------------------------------------------------------
// GLOBAL HELPERS FOR ORDERS & SCHEDULING
// ----------------------------------------------------------------------

String formatOrderId(String? rawOrderId, String fallbackId) {
  if (rawOrderId != null && rawOrderId.isNotEmpty) {
    return rawOrderId.length > 8 ? rawOrderId.substring(0, 8).toUpperCase() : rawOrderId.toUpperCase();
  }
  return fallbackId.length > 8 ? fallbackId.substring(0, 8).toUpperCase() : fallbackId.toUpperCase();
}

DateTime getTrueOrderDateTime(String rawOrderId, String? createdAt) {
  try {
    final parts = rawOrderId.split('-');
    if (parts.length >= 2) {
      final epoch = int.tryParse(parts[1]);
      if (epoch != null && epoch > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(epoch);
      }
    }
  } catch (_) {}

  if (createdAt != null) {
    final parsed = DateTime.tryParse(createdAt);
    if (parsed != null) return parsed.toLocal();
  }
  return DateTime.now();
}

String formatOrderDate(String? isoString) {
  if (isoString == null || isoString.isEmpty) return 'Unknown Time';
  final dt = DateTime.tryParse(isoString);
  if (dt == null) return 'Unknown Time';
  return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
}

String formatFriendlyDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  
  final diffDays = target.difference(today).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Tomorrow';
  if (diffDays == -1) return 'Yesterday';
  
  return DateFormat('dd MMM').format(date);
}

DateTime? parseSlotStartTime(String timeSlot, {DateTime? baseDate}) {
  try {
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false).firstMatch(timeSlot);
    if (match != null) {
      int h = int.parse(match.group(1)!);
      int m = int.parse(match.group(2)!);
      String ampm = match.group(3)!.toUpperCase();
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;
      
      final date = baseDate ?? DateTime.now();
      return DateTime(date.year, date.month, date.day, h, m);
    }
  } catch (_) {}
  return null;
}

bool isMealExpired(String? timeSlot, {DateTime? orderDate}) {
  if (timeSlot == null || timeSlot.isEmpty) return false;
  final startTime = parseSlotStartTime(timeSlot, baseDate: orderDate);
  if (startTime != null) {
    // Meal expires 3 hours after its scheduled start time
    return DateTime.now().isAfter(startTime.add(const Duration(hours: 3)));
  }
  return false;
}

bool isTimeWithinChefBounds(String selectedTime, String chefScheduleStr) {
  if (chefScheduleStr.isEmpty) return true;
  
  final timeRegex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
  final matches = timeRegex.allMatches(chefScheduleStr).toList();
  final selectedMatch = timeRegex.firstMatch(selectedTime);

  if (selectedMatch == null) return true;

  int toMins(RegExpMatch m) {
    int h = int.parse(m.group(1)!);
    if (m.group(3)!.toUpperCase() == 'PM' && h != 12) h += 12;
    if (m.group(3)!.toUpperCase() == 'AM' && h == 12) h = 0;
    return h * 60 + int.parse(m.group(2)!);
  }

  int sel = toMins(selectedMatch);

  // Range provided (e.g., "9:00 AM - 5:00 PM")
  if (matches.length >= 2) {
    int start = toMins(matches[0]);
    int end = toMins(matches[1]);
    return sel >= start && sel <= end;
  }
  
  // Open-ended schedule starting from a time (e.g., "9:00 AM onwards")
  if (matches.length == 1) {
    int start = toMins(matches[0]);
    return sel >= start;
  }

  return true;
}

bool isDateWithinChefBounds(String dateStr, String chefScheduleStr) {
  return true;
}

List<DateTime> getValidDatesForChefSchedule(String scheduleStr) {
  List<DateTime> dates = [];
  final now = DateTime.now();
  for (int i = 0; i < 7; i++) {
    dates.add(now.add(Duration(days: i)));
  }
  return dates;
}