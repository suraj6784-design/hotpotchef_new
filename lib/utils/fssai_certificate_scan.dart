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

/// Indian FSSAI cards print validity as DD-MM-YY or DD-MM-YYYY.
DateTime? parseFssaiCardDate(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null && text.contains('-') && text.length >= 10 && text[4] == '-') {
    return DateTime(iso.year, iso.month, iso.day);
  }
  final m = RegExp(r'(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2,4})').firstMatch(text);
  if (m == null) return null;
  final day = int.tryParse(m.group(1) ?? '') ?? 0;
  final month = int.tryParse(m.group(2) ?? '') ?? 0;
  var year = int.tryParse(m.group(3) ?? '') ?? 0;
  if (day < 1 || month < 1 || month > 12 || year == 0) return null;
  if (year < 100) year += 2000;
  if (day > 31) return null;
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
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  final registration = _registrationFromLines(lines, text);
  final legalName = _labeledBlock(lines, const ['name'], stopLabels: _kFieldStops);
  final address = _labeledBlock(lines, const ['address'], stopLabels: _kFieldStops);
  final validRaw = _labeledBlock(
    lines,
    const ['valid upto', 'valid until', 'valid till', 'validity', 'valid to'],
    stopLabels: _kFieldStops,
    singleLine: true,
  );
  return FssaiCertificateScan(
    registrationNumber: registration,
    legalName: _cleanPersonName(legalName),
    address: _cleanAddress(address),
    validUntil: parseFssaiCardDate(validRaw),
    rawText: text,
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
      if (!lower.startsWith(label)) continue;
      final afterColon = line.substring(label.length).replaceFirst(RegExp(r'^[\s:\-]+'), '').trim();
      if (singleLine) {
        if (afterColon.isNotEmpty) return afterColon;
        if (i + 1 < lines.length) return lines[i + 1];
        return null;
      }
      final buf = <String>[];
      if (afterColon.isNotEmpty) buf.add(afterColon);
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j];
        if (_startsWithAnyLabel(next, stopLabels)) break;
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
  final value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return null;
  if (value.toLowerCase() == 'n/a') return null;
  return value;
}

String? _cleanAddress(String? raw) {
  final value = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.isEmpty) return null;
  return value;
}
