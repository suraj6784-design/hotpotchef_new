import '../models/app_role.dart';
import 'fssai_certificate_scan.dart';
import 'helpers.dart';

class KycChecklist {
  const KycChecklist({
    required this.done,
    required this.total,
    required this.missing,
    this.payoutMissing = const [],
  });

  final int done;
  final int total;
  final List<String> missing;
  final List<String> payoutMissing;

  bool get incomplete => done < total;
  bool get needsReminder => incomplete || payoutMissing.isNotEmpty;
}

/// Fields chefs can complete in-app that block publish, plus payout extras.
KycChecklist kycChecklistFor(Map<String, dynamic> row) {
  final parsed = AppRole.parse(row['role']?.toString());
  if (!parsed.requiresKitchenFssai && !parsed.requiresDriverKyc) {
    return const KycChecklist(done: 1, total: 1, missing: []);
  }

  if (parsed.requiresDriverKyc) {
    final checks = <String, String>{
      'Name': row['name']?.toString() ?? row['full_name']?.toString() ?? '',
      'Phone': row['phone']?.toString() ?? '',
      'Bank account': row['bank_account_number']?.toString() ?? '',
      'IFSC': row['ifsc_code']?.toString() ?? row['bank_ifsc']?.toString() ?? '',
      'PAN': row['pan_number']?.toString() ?? '',
      'Aadhaar': row['aadhaar_masked']?.toString() ?? '',
      'Vehicle type': row['vehicle_type']?.toString() ?? '',
      'Vehicle number': row['vehicle_reg_no']?.toString() ?? row['vehicle_number']?.toString() ?? '',
    };
    return _fromChecks(checks);
  }

  final live = <String, String>{
    'Name': row['name']?.toString() ?? row['full_name']?.toString() ?? '',
    'Phone': row['phone']?.toString() ?? '',
    'FSSAI number': row['fssai_number']?.toString() ?? '',
    'FSSAI proof': row['fssai_proof_url']?.toString() ?? '',
    'FSSAI verified':
        (!fssaiLicenceIsExpired(parseStoredFssaiValidUntil(row['fssai_valid_until'])) &&
                normalizeFssaiVerificationStatus(row['fssai_verification_status']?.toString()) == 'verified')
            ? 'yes'
            : '',
    'Kitchen pin': hasKitchenPin(row) ? 'yes' : '',
  };
  final payoutMissing = <String>[];
  if ((row['bank_account_number']?.toString() ?? '').trim().isEmpty) {
    payoutMissing.add('Bank account');
  }
  if ((row['ifsc_code']?.toString() ?? row['bank_ifsc']?.toString() ?? '').trim().isEmpty) {
    payoutMissing.add('IFSC');
  }
  final result = _fromChecks(live);
  return KycChecklist(
    done: result.done,
    total: result.total,
    missing: result.missing,
    payoutMissing: payoutMissing,
  );
}

KycChecklist _fromChecks(Map<String, String> checks) {
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
