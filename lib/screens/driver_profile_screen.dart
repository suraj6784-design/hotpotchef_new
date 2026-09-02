// lib/screens/driver_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'map_picker_screen.dart';
import '../widgets/avatar_upload.dart';
import '../widgets/change_password_dialog.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _aadhaarMaskedController = TextEditingController();
  final _panController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  String _bloodGroup = 'O+';
  String? _avatarUrl;

  final _houseController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController(text: 'Maharashtra');
  final _pincodeController = TextEditingController();

  final _vehicleModelController = TextEditingController();
  final _vehicleRegNoController = TextEditingController();
  final _dlNumberController = TextEditingController();
  final _insurancePolicyController = TextEditingController();
  String _vehicleType = '2-Wheeler (Petrol)';

  double? _latitude;
  double? _longitude;

  static final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final _phoneRegex = RegExp(r'^[6-9]\d{9}$');

  final List<String> _bloodGroups = const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  final List<String> _vehicleTypes = const ['2-Wheeler (Petrol)', 'Electric 2-Wheeler (EV)', 'Bicycle', '3-Wheeler / Auto'];

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emergencyPhoneController.dispose();
    _aadhaarMaskedController.dispose();
    _panController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _houseController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _vehicleModelController.dispose();
    _vehicleRegNoController.dispose();
    _dlNumberController.dispose();
    _insurancePolicyController.dispose();
    super.dispose();
  }

  // --- Data Loading ---

  Future<void> _loadDriverProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final userData = await _supabase.from('users').select().eq('id', user.id).maybeSingle();

      if (userData != null && mounted) {
        _nameController.text = userData['name']?.toString() ?? userData['full_name']?.toString() ?? user.userMetadata?['name']?.toString() ?? '';
        _phoneController.text = userData['phone']?.toString() ?? user.userMetadata?['phone']?.toString() ?? '';
        _emergencyPhoneController.text = userData['emergency_phone']?.toString() ?? '';
        
        final rawAadhaar = userData['aadhaar_masked']?.toString() ?? userData['aadhaar_number']?.toString() ?? '';
        _aadhaarMaskedController.text = rawAadhaar.length > 4 
            ? 'XXXX-XXXX-${rawAadhaar.substring(rawAadhaar.length - 4)}' 
            : 'XXXX-XXXX-XXXX';

        _panController.text = userData['pan_number']?.toString() ?? userData['pan']?.toString() ?? '';
        _bloodGroup = userData['blood_group']?.toString() ?? 'O+';
        _avatarUrl = userData['avatar_url']?.toString();

        _vehicleModelController.text = userData['vehicle_model']?.toString() ?? '';
        _vehicleRegNoController.text = userData['vehicle_reg_no']?.toString() ?? userData['vehicle_number']?.toString() ?? '';
        _dlNumberController.text = userData['driving_license_no']?.toString() ?? userData['license_no']?.toString() ?? '';
        _insurancePolicyController.text = userData['insurance_policy_no']?.toString() ?? '';
        _vehicleType = userData['vehicle_type']?.toString() ?? '2-Wheeler (Petrol)';

        _latitude = (userData['lat'] as num?)?.toDouble();
        _longitude = (userData['lng'] as num?)?.toDouble();

        _houseController.text = userData['house_no']?.toString() ?? '';
        _streetController.text = userData['street']?.toString() ?? userData['address']?.toString() ?? '';
        _cityController.text = userData['city']?.toString() ?? '';
        _stateController.text = userData['state']?.toString() ?? 'Maharashtra';
        _pincodeController.text = userData['pincode']?.toString() ?? userData['postal_code']?.toString() ?? '';
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Driver profile load failure');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Map Picker ---

  Future<void> _openMapPicker() async {
    if (!_isEditing) return;

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(initialLat: _latitude, initialLng: _longitude),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _latitude = (result['latitude'] as num?)?.toDouble();
        _longitude = (result['longitude'] as num?)?.toDouble();
        final rawAddr = result['address']?.toString();
        if (rawAddr != null && rawAddr.isNotEmpty) {
          _streetController.text = rawAddr;
        }
      });
      _showSnackBar('Location coordinates updated.');
    }
  }

  // --- Password Reset ---

  void _showChangePasswordDialog() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => ChangePasswordDialog(
        requireCurrentPassword: true,
        onSubmit: ({currentPassword, required newPassword}) async {
          final user = _supabase.auth.currentUser;
          if (user == null || user.email == null) {
            throw Exception('Not logged in');
          }
          try {
            await _supabase.auth.signInWithPassword(
              email: user.email!,
              password: currentPassword ?? '',
            );
            await _supabase.auth.updateUser(UserAttributes(password: newPassword));
            _oldPasswordController.clear();
            _newPasswordController.clear();
          } catch (e, stack) {
            FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Driver password change failure');
            _showSnackBar('Failed to update password. Incorrect old password or network error.', isError: true);
            rethrow;
          }
        },
      ),
    ).then((ok) {
      if (ok == true) _showSnackBar('Password changed successfully!');
    });
  }

  // --- Profile Persistence ---

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      _showSnackBar('Please pin your residential address on the map.', isError: true);
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final emergency = _emergencyPhoneController.text.trim();
    final pan = _panController.text.trim().toUpperCase();

    final house = _houseController.text.trim();
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final state = _stateController.text.trim();
    final pin = _pincodeController.text.trim();

    final vehicleModel = _vehicleModelController.text.trim();
    final vehicleReg = _vehicleRegNoController.text.trim().toUpperCase();
    final dlNumber = _dlNumberController.text.trim().toUpperCase();
    final insurance = _insurancePolicyController.text.trim();
    
    final aadhaarInput = _aadhaarMaskedController.text.trim();
    final bool isNewAadhaar = aadhaarInput.length == 12 && !aadhaarInput.contains('X');

    final fullAddress = "$house, $street, $city, $state - $pin";

    setState(() => _isSaving = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Session expired');

      final updateData = {
        'id': user.id,
        'name': name,
        'full_name': name,
        'phone': phone,
        'emergency_phone': emergency,
        'pan_number': pan,
        'blood_group': _bloodGroup,
        'address': fullAddress,
        'house_no': house,
        'street': street,
        'city': city,
        'state': state,
        'pincode': pin,
        'lat': _latitude,
        'lng': _longitude,
        'vehicle_type': _vehicleType,
        'vehicle_model': vehicleModel,
        'vehicle_reg_no': vehicleReg,
        'driving_license_no': dlNumber,
        'insurance_policy_no': insurance,
        if (isNewAadhaar) 'aadhaar_number': aadhaarInput,
        'role': 'Driver',
        if (_avatarUrl != null) 'avatar_url': _avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase.from('users').upsert(updateData);
      await _supabase.auth.updateUser(UserAttributes(data: {'name': name, 'phone': phone}));

      if (!mounted) return;
      setState(() => _isEditing = false);
      _showSnackBar('Driver compliance profile updated successfully!');
      _loadDriverProfile();
      
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Driver profile save failure');
      _showSnackBar('Failed to save profile: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- Digital ID Card Modal ---

  void _showDigitalIDCard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.badge_outlined, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('Digital Partner ID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: Colors.deepOrange.withValues(alpha: 0.2),
                backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                child: _avatarUrl == null ? const Icon(Icons.person, size: 40, color: Colors.deepOrange) : null,
              ),
            ),
            const SizedBox(height: 16),
            _buildIDRow('Partner Name', _nameController.text.isEmpty ? 'Driver' : _nameController.text),
            _buildIDRow('Phone', _phoneController.text),
            _buildIDRow('Emergency Contact', _emergencyPhoneController.text.isEmpty ? 'Not provided' : _emergencyPhoneController.text),
            _buildIDRow('DL Number', _dlNumberController.text.isEmpty ? 'Pending' : _dlNumberController.text),
            _buildIDRow('Vehicle Reg', _vehicleRegNoController.text.isEmpty ? 'Pending' : _vehicleRegNoController.text),
            _buildIDRow('Blood Group', _bloodGroup),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 6),
                  Text('Active Commercial Delivery Partner',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildIDRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  // --- UI Tree ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Driver Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            icon: Icon(_isEditing ? Icons.close : Icons.edit, color: Colors.deepOrange, size: 18),
            label: Text(_isEditing ? 'Cancel' : 'Edit', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              AvatarUploadWidget(
                                initialAvatarUrl: _avatarUrl,
                                isEditing: _isEditing,
                                onUploadComplete: (newUrl) => setState(() => _avatarUrl = newUrl),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _nameController.text.isEmpty ? 'Delivery Partner' : _nameController.text,
                                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _phoneController.text.isEmpty ? 'Contact pending' : _phoneController.text,
                                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                      child: const Text('Verified Driver',
                                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: const Icon(Icons.badge_outlined, size: 18),
                                  label: const Text('Digital ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  onPressed: _showDigitalIDCard,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade800,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  icon: const Icon(Icons.lock_reset, size: 18),
                                  label: const Text('Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  onPressed: _showChangePasswordDialog,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Personal Info
                  const Text('Personal & Identity Info (Govt. Compliance)',
                      style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _nameController,
                    label: 'Full Name (as per Govt ID) *',
                    prefixIcon: Icons.person,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _phoneController,
                    label: 'Primary Phone Number *',
                    prefixIcon: Icons.phone,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || !_phoneRegex.hasMatch(v.trim())) return 'Enter valid 10-digit number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _emergencyPhoneController,
                    label: 'Emergency Contact Number',
                    prefixIcon: Icons.contact_emergency,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          controller: _aadhaarMaskedController,
                          label: 'Aadhaar Number',
                          prefixIcon: Icons.credit_card,
                          keyboardType: TextInputType.number,
                          maxLength: 12,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) {
                            if (v != null && v.isNotEmpty && !v.contains('X') && v.length != 12) {
                              return 'Enter valid 12-digit number';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: _bloodGroup,
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Blood Group', prefixIcon: Icon(Icons.bloodtype, color: Colors.redAccent)),
                          items: _bloodGroups.map((bg) => DropdownMenuItem(value: bg, child: Text(bg))).toList(),
                          onChanged: _isEditing ? (val) => setState(() => _bloodGroup = val ?? 'O+') : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _panController,
                    label: 'PAN Card Number (e.g. ABCDE1234F)',
                    prefixIcon: Icons.account_balance,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                    validator: (v) {
                      if (v != null && v.isNotEmpty && !_panRegex.hasMatch(v.trim().toUpperCase())) {
                        return 'Invalid PAN format';
                      }
                      return null;
                    },
                  ),
                  const Divider(height: 32, color: Colors.white24),

                  // Residential Address
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Permanent / Residential Address',
                          style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 15)),
                      Row(
                        children: [
                          Icon(_latitude != null ? Icons.check_circle : Icons.warning_amber_rounded,
                              size: 14, color: _latitude != null ? Colors.green : Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            _latitude != null ? 'Geo-Pinned' : 'Missing Pin',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _latitude != null ? Colors.green : Colors.orange),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Required for background verification and local RTO compliance.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 16),

                  if (_isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: _latitude == null ? Colors.deepOrange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                            side: BorderSide(color: _latitude == null ? Colors.deepOrange : Colors.green),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(Icons.pin_drop, color: _latitude == null ? Colors.deepOrange : Colors.green),
                          label: Text(
                            _latitude == null ? 'Pin Home Address on Map *' : 'Location Pinned (Tap to change)',
                            style: TextStyle(fontWeight: FontWeight.bold, color: _latitude == null ? Colors.deepOrange : Colors.green),
                          ),
                          onPressed: _openMapPicker,
                        ),
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _houseController,
                          label: 'House / Flat No. *',
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          controller: _cityController,
                          label: 'City *',
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _streetController,
                    label: 'Street Name / Area / Landmark *',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _stateController,
                          label: 'State *',
                          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _pincodeController,
                          label: 'Pincode *',
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          validator: (v) => v == null || v.trim().length != 6 ? '6-digit PIN' : null,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32, color: Colors.white24),

                  // Vehicle & License Details
                  const Text('Vehicle & License Details (MoRTH / RTO)',
                      style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _vehicleType,
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Vehicle Category', prefixIcon: Icon(Icons.two_wheeler, color: Colors.grey)),
                    items: _vehicleTypes.map((vt) => DropdownMenuItem(value: vt, child: Text(vt))).toList(),
                    onChanged: _isEditing ? (val) => setState(() => _vehicleType = val ?? _vehicleType) : null,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _vehicleModelController,
                    label: 'Vehicle Make & Model (e.g. Honda Activa 6G)',
                    prefixIcon: Icons.directions_bike,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _vehicleRegNoController,
                    label: 'Vehicle Registration No. *',
                    prefixIcon: Icons.pin,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _dlNumberController,
                    label: 'Driving License (DL) Number *',
                    prefixIcon: Icons.card_membership,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _insurancePolicyController,
                    label: 'Vehicle Insurance Policy Number',
                    prefixIcon: Icons.security,
                  ),
                  const SizedBox(height: 32),

                  if (_isEditing)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.save),
                      label: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Save Driver Compliance Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: _isSaving ? null : _saveProfile,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? prefixIcon,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      enabled: _isEditing && enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      validator: validator,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Colors.deepOrange, fontSize: 14, fontWeight: FontWeight.bold),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.grey, size: 20) : null,
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.deepOrange, width: 2)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}
