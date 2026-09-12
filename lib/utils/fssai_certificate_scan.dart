/// Structured fields read from an FSSAI registration / licence card photo.
class FssaiCertificateScan {
  const FssaiCertificateScan({
    this.registrationNumber,
    this.legalName,
    this.address,
    this.validUntil,
    this.rawText = '',
  });

  final String? registrationNumber;
  final String? legalName;
  final String? address;
  final DateTime? validUntil;
  final String rawText;

  bool get hasAnyField =>
      (registrationNumber ?? '').isNotEmpty ||
      (legalName ?? '').isNotEmpty ||
      (address ?? '').isNotEmpty ||
      validUntil != null;

  bool get hasCoreFields =>
      (registrationNumber ?? '').isNotEmpty &&
      (legalName ?? '').isNotEmpty &&
      validUntil != null;
}

bool fssaiLicenceIsExpired(DateTime? validUntil, {DateTime? now}) {
  if (validUntil == null) return false;
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final until = DateTime(validUntil.year, validUntil.month, validUntil.day);
  return until.isBefore(today);
}

DateTime? parseStoredFssaiValidUntil(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
  return parseFssaiCardDate(raw.toString());
}

const _kMonthNames = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'sept': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Indian FSSAI cards print validity as DD-MM-YY, DD-MM-YYYY, or 10 Sep 2027.
DateTime? parseFssaiCardDate(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null && text.contains('-') && text.length >= 10 && text[4] == '-') {
    return DateTime(iso.year, iso.month, iso.day);
  }
  final named = RegExp(
    r'(\d{1,2})\s*[.\-/ ]\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\s*[.\-/ ]\s*(\d{2,4})',
    caseSensitive: false,
  ).firstMatch(text);
  if (named != null) {
    final day = int.tryParse(named.group(1) ?? '') ?? 0;
    final month = _kMonthNames[(named.group(2) ?? '').toLowerCase()] ?? 0;
    var year = int.tryParse(named.group(3) ?? '') ?? 0;
    if (year > 0 && year < 100) year += 2000;
    if (day >= 1 && day <= 31 && month >= 1 && year >= 2011 && year <= 2045) {
      return DateTime(year, month, day);
    }
  }
  final digits = text.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[Il]'), '1');
  final m = RegExp(r'(\d{1,2})\s*[.\-/]\s*(\d{1,2})\s*[.\-/]\s*(\d{2,4})').firstMatch(digits) ??
      RegExp(r'(\d{1,2})\s+(\d{1,2})\s+(\d{2,4})').firstMatch(digits);
  if (m == null) return null;
  final day = int.tryParse(m.group(1) ?? '') ?? 0;
  final month = int.tryParse(m.group(2) ?? '') ?? 0;
  var year = int.tryParse(m.group(3) ?? '') ?? 0;
  if (day < 1 || month < 1 || month > 12 || year == 0) return null;
  if (year < 100) year += 2000;
  if (day > 31 || year < 2011 || year > 2045) return null;
  return DateTime(year, month, day);
}

String fssaiValidUntilIsoDate(DateTime? value) {
  if (value == null) return '';
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

FssaiCertificateScan parseFssaiCertificateText(String raw) {
  final text = _normalizeOcr(raw);
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final fromLines = _parseLabeledLines(lines, text);
  final fromColumns = _parseTwoColumnCard(lines);
  final fromRegex = _parseWithRegex(text);

  final name = _bestPersonName([
    fromColumns.legalName,
    fromRegex.legalName,
    fromLines.legalName,
  ]);
  final swallowed = fromLines.legalName;
  final address = _bestAddress([
    fromLines.address,
    fromColumns.address,
    fromRegex.address,
    if (swallowed != null && !_looksLikePersonName(swallowed)) swallowed,
  ]);
  final validUntil = parseFssaiCardDate(fromLines.validRaw) ??
      parseFssaiCardDate(fromColumns.validRaw) ??
      parseFssaiCardDate(fromRegex.validRaw) ??
      _validityFromDocument(text);

  return FssaiCertificateScan(
    registrationNumber: fromLines.registration ?? fromColumns.registration ?? fromRegex.registration,
    legalName: name,
    address: address,
    validUntil: validUntil,
    rawText: text,
  );
}

class _ParsedFields {
  const _ParsedFields({
    this.registration,
    this.legalName,
    this.address,
    this.validRaw,
  });

  final String? registration;
  final String? legalName;
  final String? address;
  final String? validRaw;
}

String _normalizeOcr(String raw) {
  return raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'Valid\s*Up\s*[- ]?\s*to', caseSensitive: false), 'Valid Upto')
      .replaceAll(RegExp(r'Vald\s*Upto', caseSensitive: false), 'Valid Upto')
      .replaceAll('Registration lD', 'Registration ID')
      .replaceAll('Registration ID', 'Registration ID');
}

_ParsedFields _parseLabeledLines(List<String> lines, String full) {
  final registration = _registrationFromLines(lines, full);
  final legalName = _labeledBlock(
    lines,
    const [
      'name of food business operator',
      'name of fbo',
      'name on licence',
      'name',
    ],
    stopLabels: _kFieldStops,
    singleLine: true,
  );
  final address = _labeledBlock(
    lines,
    const ['address of premises', 'premises address', 'address'],
    stopLabels: _kFieldStops,
  );
  final validRaw = _labeledBlock(
    lines,
    const ['valid upto', 'valid until', 'valid till', 'validity', 'valid to'],
    stopLabels: _kFieldStops,
    singleLine: true,
  );
  return _ParsedFields(
    registration: registration,
    legalName: legalName,
    address: address,
    validRaw: validRaw,
  );
}

/// ML Kit often reads the left label column, then the right value column.
_ParsedFields _parseTwoColumnCard(List<String> lines) {
  var firstValue = 0;
  while (firstValue < lines.length && _bareFieldKey(lines[firstValue]) == null) {
    firstValue++;
  }
  // Skip a duplicate Registration Certificate header if it was classified as a field.
  if (firstValue < lines.length &&
      lines[firstValue].toLowerCase().contains('certificate')) {
    firstValue++;
    while (firstValue < lines.length && _bareFieldKey(lines[firstValue]) == null) {
      firstValue++;
    }
  }
  final keys = <String>[];
  while (firstValue < lines.length && _bareFieldKey(lines[firstValue]) != null) {
    keys.add(_bareFieldKey(lines[firstValue])!);
    firstValue++;
  }
  if (keys.length < 3 || firstValue >= lines.length) return const _ParsedFields();

  final values = lines.sublist(firstValue);
  final addressIndex = keys.indexOf('address');
  String? pick(String key) {
    final index = keys.indexOf(key);
    if (index < 0) return null;
    if (key == 'address' && addressIndex >= 0) {
      final keysAfter = keys.length - (addressIndex + 1);
      final end = (values.length - keysAfter).clamp(addressIndex + 1, values.length);
      return values.sublist(addressIndex, end).join(', ');
    }
    var valueIndex = index;
    if (addressIndex >= 0 && index > addressIndex) {
      valueIndex = values.length - (keys.length - index);
    }
    if (valueIndex < 0 || valueIndex >= values.length) return null;
    return values[valueIndex];
  }

  final namePick = pick('name');
  final validPick = pick('valid');
  String? personFromValues() {
    if (_looksLikePersonName(namePick)) return namePick;
    for (final value in values) {
      if (_looksLikePersonName(value)) return value;
    }
    return namePick;
  }

  String? dateFromValues() {
    if (parseFssaiCardDate(validPick) != null) return validPick;
    for (final value in values) {
      if (parseFssaiCardDate(value) != null) return value;
    }
    return validPick;
  }

  return _ParsedFields(
    registration: _fourteenDigitLicence(pick('registration')),
    legalName: personFromValues(),
    address: pick('address'),
    validRaw: dateFromValues(),
  );
}

_ParsedFields _parseWithRegex(String text) {
  final flat = text.replaceAll('\n', ' ');
  final registration = _fourteenDigitLicence(
    RegExp(
      r'registration\s*i[dD]\s*:?\s*([0-9][0-9\s-]{12,22})',
      caseSensitive: false,
    ).firstMatch(flat)?.group(1),
  ) ??
      _fourteenDigitLicence(flat);

  final validRaw = RegExp(
    r'valid\s*up\s*to\s*:?\s*(\d{1,2}[.\-/ ]\d{1,2}[.\-/ ]\d{2,4}|\d{1,2}\s*[A-Za-z]{3,9}\s*\d{2,4})',
    caseSensitive: false,
  ).firstMatch(flat)?.group(1);

  final name = RegExp(
    r'\bname(?:\s+of\s+food\s+business\s+operator|\s+of\s+fbo|\s+on\s+licence)?\s*:?\s*([A-Za-z][A-Za-z .]{1,80}?)(?=\s*(?:address|kob|govt|issuing|issued)\b)',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);

  final address = RegExp(
    r'address\s*:?\s*(.+?)(?=\s*(?:\nkob\b|\ngovt\b|\nissuing\b|\nissued\b|\ndisclaimer\b|$))',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(text)?.group(1);

  return _ParsedFields(
    registration: registration,
    legalName: name,
    address: address,
    validRaw: validRaw,
  );
}

const _kFieldStops = [
  'registration id',
  'registration no',
  'licence no',
  'license no',
  'valid upto',
  'valid until',
  'valid till',
  'validity',
  'name',
  'address',
  'kob',
  'govt id',
  'issuing authority',
  'issued on',
  'disclaimer',
];

String? _bareFieldKey(String line) {
  final lower = line.toLowerCase().replaceAll(RegExp(r'[:\-|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (lower.contains('certificate') || lower.contains('form c') || lower == 'fssai') return null;
  if (lower.startsWith('registration')) return 'registration';
  if (lower.startsWith('valid')) return 'valid';
  if (lower.startsWith('name')) return 'name';
  if (lower.startsWith('address') || lower.startsWith('premises')) return 'address';
  if (lower.startsWith('kob') || lower.startsWith('kind of business')) return 'kob';
  if (lower.startsWith('govt')) return 'govt';
  if (lower.startsWith('issuing')) return 'issuing';
  if (lower.startsWith('issued')) return 'issued';
  if (lower.startsWith('disclaimer')) return 'disclaimer';
  return null;
}

String? _registrationFromLines(List<String> lines, String full) {
  final labeled = _labeledBlock(
    lines,
    const ['registration id', 'registration no', 'licence no', 'license no', 'fssai no', 'fssai number'],
    stopLabels: _kFieldStops,
    singleLine: true,
  );
  final fromLabel = _fourteenDigitLicence(labeled);
  if (fromLabel != null) return fromLabel;
  return _fourteenDigitLicence(full);
}

String? _fourteenDigitLicence(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  for (var i = 0; i + 14 <= digits.length; i++) {
    final slice = digits.substring(i, i + 14);
    if (slice.startsWith('1') || slice.startsWith('2')) return slice;
  }
  return null;
}

String? _labeledBlock(
  List<String> lines,
  List<String> labels, {
  required List<String> stopLabels,
  bool singleLine = false,
}) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    for (final label in labels) {
      final idx = lower.indexOf(label);
      if (idx < 0) continue;
      // Prefer a real field label, not the word inside another sentence.
      if (idx > 0 && RegExp(r'[a-z]').hasMatch(lower[idx - 1])) continue;
      var afterColon = line.substring(idx + label.length).replaceFirst(RegExp(r'^[\s:\-]+'), '').trim();
      if (_isLabelResidue(afterColon)) afterColon = '';
      if (singleLine) {
        if (afterColon.isNotEmpty && _bareFieldKey(afterColon) == null) return afterColon;
        if (i + 1 < lines.length && _bareFieldKey(lines[i + 1]) == null) return lines[i + 1];
        return null;
      }
      final buf = <String>[];
      if (afterColon.isNotEmpty && _bareFieldKey(afterColon) == null) buf.add(afterColon);
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j];
        if (_startsWithAnyLabel(next, stopLabels) || _bareFieldKey(next) != null) break;
        buf.add(next);
      }
      final joined = buf.join(', ').trim();
      return joined.isEmpty ? null : joined;
    }
  }
  return null;
}

bool _startsWithAnyLabel(String line, List<String> labels) {
  final lower = line.toLowerCase();
  return labels.any((l) => lower == l || lower.startsWith('$l:') || lower.startsWith('$l '));
}

String? _cleanPersonName(String? raw) {
  var value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return null;
  if (_bareFieldKey(value) != null) return null;
  if (value.toLowerCase() == 'n/a') return null;
  value = value
      .split(RegExp(r'\s+(address|kob|govt|issuing|issued|disclaimer)\b', caseSensitive: false))
      .first
      .trim();
  value = value.split(RegExp(r'\s+made with', caseSensitive: false)).first.trim();
  if (_isLabelResidue(value) || _looksLikeAddress(value) || !_looksLikePersonName(value)) return null;
  if (value.length < 2) return null;
  return value;
}

String? _cleanAddress(String? raw) {
  var value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return null;
  if (_bareFieldKey(value) != null) return null;
  if (_isLabelResidue(value)) return null;
  value = value.split(RegExp(r'\s+KOB\b', caseSensitive: false)).first.trim();
  return value.isEmpty ? null : value;
}

bool _isLabelResidue(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return true;
  return value.startsWith('of ') ||
      value == 'id' ||
      value == 'no' ||
      value == 'upto' ||
      value.startsWith('of food') ||
      value.startsWith('of premises') ||
      value.startsWith('food business') ||
      value == 'operator';
}

bool _looksLikeAddress(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value.isEmpty) return false;
  if (RegExp(r'\d{6}').hasMatch(value)) return true;
  const hints = [
    'complex',
    'apartment',
    'appart',
    'chowk',
    'nagar',
    'road',
    'street',
    'society',
    'sector',
    'plot',
    'wing',
    'floor',
    'pune',
    'mumbai',
    'thane',
    'building',
    'lane',
    'marg',
    'colony',
    'phase',
  ];
  return hints.any(value.contains);
}

bool _looksLikePersonName(String? raw) {
  final value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return false;
  if (_isLabelResidue(value) || _looksLikeAddress(value)) return false;
  if (RegExp(r'\d').hasMatch(value)) return false;
  if (!RegExp(r"^[A-Za-z][A-Za-z .']{1,70}$").hasMatch(value)) return false;
  final lower = value.toLowerCase();
  const blocked = [
    'manufacturing',
    'stall',
    'holder',
    'petty',
    'retail',
    'restaurant',
    'catering',
    'operator',
    'authority',
    'government',
    'certificate',
    'registration',
    'permanent',
    'temporary',
    'business',
    'standards',
    'licence',
    'license',
    'fssai',
    'general',
    'premises',
  ];
  if (blocked.any(lower.contains)) return false;
  final words = value.split(' ').where((w) => w.isNotEmpty).toList();
  return words.length >= 2 && words.length <= 5;
}

String? _bestPersonName(List<String?> candidates) {
  for (final candidate in candidates) {
    final cleaned = _cleanPersonName(candidate);
    if (cleaned != null) return cleaned;
  }
  return null;
}

String? _bestAddress(List<String?> candidates) {
  String? best;
  for (final candidate in candidates) {
    final cleaned = _cleanAddress(candidate);
    if (cleaned == null) continue;
    if (best == null || cleaned.length > best.length) best = cleaned;
  }
  return best;
}

DateTime? _validityFromDocument(String text) {
  final dates = <DateTime>[];
  final matches = [
    ...RegExp(r'\d{1,2}\s*[.\-/]\s*\d{1,2}\s*[.\-/]\s*\d{2,4}').allMatches(text),
    ...RegExp(
      r'\d{1,2}\s*[.\-/ ]\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\s*[.\-/ ]\s*\d{2,4}',
      caseSensitive: false,
    ).allMatches(text),
    ...RegExp(r'\d{1,2}\s+\d{1,2}\s+\d{2,4}').allMatches(text),
  ];
  for (final match in matches) {
    final parsed = parseFssaiCardDate(match.group(0));
    if (parsed != null) dates.add(parsed);
  }
  if (dates.isEmpty) return null;
  dates.sort();
  return dates.last;
}
