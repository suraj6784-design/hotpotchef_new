// lib/screens/address_form_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/helpers.dart';
import '../utils/app_theme.dart';
import '../widgets/app_dialog.dart';
import 'map_picker_screen.dart';

class PlacePrediction {
  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String fullDescription;

  PlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.fullDescription,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'] as Map<String, dynamic>?;
    return PlacePrediction(
      placeId: json['place_id']?.toString() ?? '',
      primaryText: structured?['main_text']?.toString() ?? json['description']?.toString() ?? '',
      secondaryText: structured?['secondary_text']?.toString() ?? '',
      fullDescription: json['description']?.toString() ?? '',
    );
  }
}

class AddressFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existingAddress;

  const AddressFormScreen({super.key, this.existingAddress});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _uuid = Uuid();

  // Form Controllers
  final _houseController = TextEditingController();
  final _streetController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _countryController = TextEditingController(text: 'India');
  final _searchController = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _isLoading = false;
  String _sessionToken = _uuid.v4();

  Timer? _debounceTimer;
  Completer<List<PlacePrediction>>? _autocompleteCompleter;

  @override
  void initState() {
    super.initState();

    if (widget.existingAddress != null) {
      final a = widget.existingAddress!;
      _houseController.text = a['house_no']?.toString() ?? '';
      _streetController.text = a['street']?.toString() ?? '';
      _landmarkController.text = a['landmark']?.toString() ?? '';
      _cityController.text = a['city']?.toString() ?? '';
      _stateController.text = a['state']?.toString() ?? '';
      _pincodeController.text = a['postal_code']?.toString() ?? a['pincode']?.toString() ?? '';
      _countryController.text = a['country']?.toString() ?? 'India';

      _latitude = (a['latitude'] as num?)?.toDouble() ??
          double.tryParse(a['latitude']?.toString() ?? '');
      _longitude = (a['longitude'] as num?)?.toDouble() ??
          double.tryParse(a['longitude']?.toString() ?? '');

      if (_streetController.text.isNotEmpty) {
        _searchController.text = "${_houseController.text}, ${_streetController.text}".trim();
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _houseController.dispose();
    _streetController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _countryController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- Optimized Google Places Autocomplete with Debounce & Session Tokens ---

  Future<List<PlacePrediction>> _getPlacePredictionsDebounced(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _autocompleteCompleter = Completer<List<PlacePrediction>>();

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      final results = await _executePlaceAutocomplete(query);
      if (!_autocompleteCompleter!.isCompleted) {
        _autocompleteCompleter!.complete(results);
      }
    });

    return _autocompleteCompleter!.future;
  }

  Future<List<PlacePrediction>> _executePlaceAutocomplete(String query) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    final trimmed = query.trim();
    if (trimmed.length < 3 || apiKey.isEmpty) return [];

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(trimmed)}'
      '&components=country:in'
      '&sessiontoken=$_sessionToken'
      '&key=$apiKey',
    );

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List<dynamic>? ?? [];
          return predictions
              .whereType<Map<String, dynamic>>()
              .map(PlacePrediction.fromJson)
              .toList(growable: false);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Autocomplete HTTP failure: $e');
    }
    return [];
  }

  // --- Place Details Resolution & Auto-fill ---

  Future<void> _fetchAndFillPlaceDetails(String placeId) async {
    setState(() => _isLoading = true);
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=address_components,geometry,formatted_address'
      '&sessiontoken=$_sessionToken'
      '&key=$apiKey',
    );

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['status'] == 'OK' && data['result'] != null) {
          final result = data['result'] as Map<String, dynamic>;
          final geometry = result['geometry']?['location'] as Map<String, dynamic>?;

          if (geometry != null) {
            _latitude = (geometry['lat'] as num?)?.toDouble();
            _longitude = (geometry['lng'] as num?)?.toDouble();
          }

          final components = result['address_components'] as List<dynamic>? ?? [];
          String streetName = '';
          String sublocality = '';
          String locality = '';
          String adminArea2 = ''; // Often contains district/city in Indian addresses
          String state = '';
          String pincode = '';
          String country = 'India';

          for (final c in components) {
            final comp = c as Map<String, dynamic>;
            final types = (comp['types'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? {};
            final longName = comp['long_name']?.toString() ?? '';

            if (types.contains('premise') || types.contains('subpremise')) {
              _houseController.text = longName;
            } else if (types.contains('route')) {
              streetName = longName;
            } else if (types.contains('sublocality_level_1') || types.contains('sublocality')) {
              sublocality = longName;
            } else if (types.contains('locality')) {
              locality = longName;
            } else if (types.contains('administrative_area_level_2')) {
              adminArea2 = longName;
            } else if (types.contains('administrative_area_level_1')) {
              state = longName;
            } else if (types.contains('postal_code')) {
              pincode = longName;
            } else if (types.contains('country')) {
              country = longName;
            }
          }

          final fullStreet = [streetName, sublocality].where((s) => s.isNotEmpty).join(', ');
          final finalCity = locality.isNotEmpty ? locality : adminArea2;

          setState(() {
            if (fullStreet.isNotEmpty) _streetController.text = fullStreet;
            if (finalCity.isNotEmpty) _cityController.text = finalCity;
            if (state.isNotEmpty) _stateController.text = state;
            if (pincode.isNotEmpty) _pincodeController.text = pincode;
            if (country.isNotEmpty) _countryController.text = country;
          });

          // Reset session token after finishing details fetch to close billing bracket
          _sessionToken = _uuid.v4();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Address details filled successfully!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Place details exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load place details: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Interactive Map Pin Drop ---

  Future<void> _openMapPicker() async {
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLat: _latitude,
          initialLng: _longitude,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _latitude = (result['latitude'] as num?)?.toDouble();
        _longitude = (result['longitude'] as num?)?.toDouble();
        final rawAddress = result['address']?.toString();
        if (rawAddress != null && rawAddress.isNotEmpty) {
          _streetController.text = rawAddress;
          _searchController.text = rawAddress;
        }
      });

      if (_latitude != null && _longitude != null) {
        try {
          final placemarks = await placemarkFromCoordinates(_latitude!, _longitude!);
          if (placemarks.isNotEmpty && mounted) {
            final place = placemarks.first;
            setState(() {
              _cityController.text = place.locality?.isNotEmpty == true
                  ? place.locality!
                  : (place.subAdministrativeArea ?? _cityController.text);
              _pincodeController.text = place.postalCode ?? _pincodeController.text;
              _stateController.text = place.administrativeArea ?? _stateController.text;
              _countryController.text = place.country ?? _countryController.text;
            });
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Reverse geocoding error: $e');
        }
      }
    }
  }

  // --- Database Persistence ---

  Future<Map<String, dynamic>> _upsertAddress({
    required Map<String, dynamic> addressData,
    Object? existingId,
  }) async {
    final client = Supabase.instance.client;
    final payload = {
      'user_id': addressData['user_id'],
      'house_no': addressData['house_no'],
      'street': addressData['street'],
      'city': addressData['city'],
      'state': addressData['state'],
      'postal_code': addressData['postal_code'],
      'country': addressData['country'],
      'landmark': addressData['landmark'],
      'latitude': addressData['latitude'],
      'longitude': addressData['longitude'],
      if (addressData['is_default'] == true) 'is_default': true,
    };

    Future<Map<String, dynamic>> write(Map<String, dynamic> data) async {
      if (existingId != null) {
        await client.from('user_addresses').update(Map<String, dynamic>.from(data)..remove('user_id')).eq('id', existingId);
        return {...data, 'id': existingId};
      }
      await client.from('user_addresses').insert(data);
      return data;
    }

    Future<Map<String, dynamic>> writeWithPinFallback(Map<String, dynamic> data) async {
      try {
        return await write(data);
      } catch (_) {
        final alt = {
          ...data,
          'pincode': data['postal_code'],
        }..remove('postal_code');
        return await write(alt);
      }
    }

    try {
      return await writeWithPinFallback(payload);
    } catch (_) {
      return await writeWithPinFallback(Map<String, dynamic>.from(payload)..remove('is_default'));
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an address or drop a pin on the map to determine coordinates.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final houseNo = _houseController.text.trim();
    final street = _streetController.text.trim();
    final city = _cityController.text.trim();
    final state = _stateController.text.trim();
    final pincode = _pincodeController.text.trim();
    final country = _countryController.text.trim();

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User authentication session expired');

      final addressData = {
        'user_id': user.id,
        'house_no': houseNo,
        'street': street,
        'address_line1': '$houseNo, $street',
        'city': city,
        'state': state,
        'postal_code': pincode,
        'country': country,
        'landmark': _landmarkController.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'updated_at': DateTime.now().toIso8601String(),
      };

      List<Map<String, dynamic>> existingRows = const [];
      try {
        final rows = await Supabase.instance.client
            .from('user_addresses')
            .select()
            .eq('user_id', user.id);
        existingRows = List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {}

      final existingId = widget.existingAddress?['id'] ??
          matchingSavedAddressId(existingRows, addressData);
      if (shouldMarkSavedAddressDefault(existingRows, editingId: existingId)) {
        addressData['is_default'] = true;
      }
      final saved = await _upsertAddress(addressData: addressData, existingId: existingId);

      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save address: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAddress() async {
    final addressId = widget.existingAddress?['id'];
    if (addressId == null) return;

    final confirm = await AppDialog.showConfirmation(
      context: context,
      title: 'Delete Address',
      message: 'Are you sure you want to delete this address? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.from('user_addresses').delete().eq('id', addressId);
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete address: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.background;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;
    final fill = isDark ? AppTheme.surfaceMutedDark : Colors.white;
    final divider = isDark ? Colors.white24 : Colors.black12;
    final optionBorder = isDark ? Colors.white12 : Colors.grey.shade300;
    final optionDivider = isDark ? Colors.white10 : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: titleColor),
        title: Text(
          widget.existingAddress == null ? 'Add Delivery Address' : 'Edit Address',
          style: TextStyle(fontWeight: FontWeight.bold, color: titleColor),
        ),
        actions: [
          if (widget.existingAddress != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _isLoading ? null : _deleteAddress,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            children: [
              // Smart Autocomplete with Debounced Search
              Autocomplete<PlacePrediction>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  return _getPlacePredictionsDebounced(textEditingValue.text);
                },
                displayStringForOption: (option) => option.fullDescription,
                onSelected: (PlacePrediction selection) {
                  _searchController.text = selection.fullDescription;
                  _fetchAndFillPlaceDetails(selection.placeId);
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  if (controller.text.isEmpty && _searchController.text.isNotEmpty) {
                    controller.text = _searchController.text;
                  }
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    style: TextStyle(color: titleColor, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Search Building, Street, or Area 🔍',
                      labelStyle: TextStyle(color: muted, fontSize: 13),
                      hintText: 'Start typing area or landmark...',
                      hintStyle: TextStyle(color: muted, fontSize: 13),
                      filled: true,
                      fillColor: fill,
                      prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: muted, size: 18),
                              onPressed: () {
                                controller.clear();
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8.0,
                      color: Colors.transparent,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        width: MediaQuery.of(context).size.width - 32,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: optionBorder),
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: optionDivider),
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on_outlined, color: AppTheme.primary, size: 20),
                              title: Text(
                                option.primaryText,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: titleColor),
                              ),
                              subtitle: option.secondaryText.isNotEmpty
                                  ? Text(
                                      option.secondaryText,
                                      style: TextStyle(fontSize: 12, color: muted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: Divider(color: divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('OR', style: TextStyle(color: muted, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Divider(color: divider)),
                ],
              ),
              const SizedBox(height: 16),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: fill,
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: AppTheme.primary, width: 1.2),
                ),
                icon: Icon(_latitude == null ? Icons.map_outlined : Icons.check_circle, size: 20),
                label: Text(
                  _latitude == null ? 'Drop Pin on Map' : 'Location Pinned (Tap to Adjust)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: _isLoading ? null : _openMapPicker,
              ),
              const SizedBox(height: 24),

              Text(
                'Address Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: titleColor),
              ),
              const SizedBox(height: 12),

              _buildHighContrastTextField(
                controller: _houseController,
                label: 'House / Flat / Block No. *',
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter house or flat number' : null,
              ),
              const SizedBox(height: 14),
              _buildHighContrastTextField(
                controller: _streetController,
                label: 'Street / Area / Colony *',
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter street or locality' : null,
              ),
              const SizedBox(height: 14),
              _buildHighContrastTextField(
                controller: _landmarkController,
                label: 'Landmark (Optional)',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildHighContrastTextField(
                      controller: _cityController,
                      label: 'City *',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHighContrastTextField(
                      controller: _stateController,
                      label: 'State *',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildHighContrastTextField(
                      controller: _pincodeController,
                      label: 'Pin Code *',
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      validator: (v) => v == null || v.trim().length != 6 ? '6-digit PIN required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHighContrastTextField(
                      controller: _countryController,
                      label: 'Country *',
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isLoading ? null : _saveAddress,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Save Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighContrastTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;
    final fill = isDark ? AppTheme.surfaceMutedDark : Colors.white;
    final border = isDark ? Colors.white12 : Colors.grey.shade300;

    return TextFormField(
      controller: controller,
      style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.w500),
      keyboardType: keyboardType,
      maxLength: maxLength,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: muted, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold),
        filled: true,
        fillColor: fill,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}