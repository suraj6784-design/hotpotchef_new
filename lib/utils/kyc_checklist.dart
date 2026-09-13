/// Completeness row for Admin desk KYC (chef vs driver).
///
/// Identity/payout fields apply to both partners.
/// FSSAI and kitchen name are chef-only food-business requirements.
class KycChecklist {
  const KycChecklist({required this.done, required this.total, required this.missing});

  final int done;
  final int total;
  final List<String> missing;

  bool get incomplete => done < total;
}

/// Normalize ops / profile FSSAI verification values.
String normalizeFssaiVerificationStatus(String? raw) {
  final status = (raw ?? '').trim().toLowerCase();
  if (status == 'pending' || status == 'verified' || status == 'rejected' || status == 'unsubmitted') {
    return status;
  }
  return 'unsubmitted';
}

String fssaiVerificationLabel(String? status) {
  switch (normalizeFssaiVerificationStatus(status)) {
    case 'verified':
      return 'FSSAI verified';
    case 'pending':
      return 'FSSAI proof under review';
    case 'rejected':
      return 'FSSAI rejected — re-upload proof';
    default:
      return 'Upload FSSAI proof to publish';
  }
}

String maskPan(String? raw) {
  final cleaned = (raw ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  if (cleaned.length < 4) return cleaned.isEmpty ? '' : '****';
  return '******${cleaned.substring(cleaned.length - 4)}';
}

String maskBankAccount(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return digits.isEmpty ? '' : '****';
  return 'XXXXXX${digits.substring(digits.length - 4)}';
}

KycChecklist kycChecklistFor(Map<String, dynamic> row) {
  final role = (row['role']?.toString() ?? '').toLowerCase();
  final isChef = role == 'chef';
  final checks = <String, String>{
    'Name': row['name']?.toString() ?? row['full_name']?.toString() ?? '',
    'Email': row['email']?.toString() ?? '',
    'GSTIN': row['gstin']?.toString() ?? '',
    'Bank account': row['bank_account_number']?.toString() ?? '',
    'IFSC': row['ifsc_code']?.toString() ?? row['bank_ifsc']?.toString() ?? '',
    'PAN': row['pan_number']?.toString() ?? '',
    'Aadhaar': row['aadhaar_masked']?.toString() ?? '',
  };
  if (isChef) {
    checks['FSSAI number'] = row['fssai_number']?.toString() ?? '';
    checks['FSSAI proof'] = row['fssai_proof_url']?.toString() ?? '';
    checks['FSSAI verified'] =
        normalizeFssaiVerificationStatus(row['fssai_verification_status']?.toString()) == 'verified' ? 'yes' : '';
    checks['Kitchen name'] = row['local_kitchen_name']?.toString() ?? '';
  }
  final missing = <String>[];
  var done = 0;
  for (final entry in checks.entries) {
    if (entry.value.trim().isEmpty) {
      missing.add(entry.key);
    } else {
      done++;
    }
  }
  return KycChecklist(done: done, total: checks.length, missing: missing);
}
