import 'helpers.dart';

/// Completeness row for Admin desk KYC (chef vs driver).
class KycChecklist {
  const KycChecklist({required this.done, required this.total, required this.missing});

  final int done;
  final int total;
  final List<String> missing;

  bool get incomplete => done < total;
}

/// Identity/payout fields apply to both partners.
/// FSSAI and kitchen name are chef-only food-business requirements.
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
        normalizeFssaiVerificationStatus(row['fssai_verification_status']?.toString()) == 'verified'
            ? 'yes'
            : '';
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
