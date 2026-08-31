// lib/screens/map_picker_screen.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/app_theme.dart';

class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapPickerScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(18.6298, 73.7997); // Default fallback (Pimpri-Chinchwad)
  bool _isLoading = true;
  String _draggedAddress = 'Locating position...';

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    if (widget.initialLat != null && widget.initialLng != null) {
      _currentPosition = LatLng(widget.initialLat!, widget.initialLng!);
      await _updateAddress(_currentPosition);
      if (mounted) setState(() => _isLoading = false);
    } else {
      await _determineUserLocation();
    }
  }

  Future<void> _determineUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled. Using default area.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permissions denied. Using default area.');
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('Location permissions permanently denied. Enable in device settings.');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 5), onTimeout: () async {
        return await Geolocator.getLastKnownPosition() ??
            Position(
              latitude: 18.6298,
              longitude: 73.7997,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
      });

      _currentPosition = LatLng(position.latitude, position.longitude);
      await _updateAddress(_currentPosition);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Map picker location resolution failure');
      _showError('Could not fetch exact GPS fix. Using default region.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition, 16));
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orangeAccent, behavior: SnackBarBehavior.floating),
    );
  }

  // --- Debounced Reverse Geocoding ---

  void _onCameraIdleDebounced(LatLng pos) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _updateAddress(pos);
    });
  }

  Future<void> _updateAddress(LatLng pos) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final addressFormatted = [
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode
        ].where((e) => e != null && e.isNotEmpty && e != place.locality).toSet().join(', ');

        // Ensure city is included
        final finalAddress = addressFormatted.isNotEmpty
            ? '$addressFormatted, ${place.locality ?? ''}'.replaceAll(RegExp(r',\s*,'), ',').trim()
            : '${place.locality ?? ''}, ${place.administrativeArea ?? ''}';

        setState(() {
          _draggedAddress = finalAddress.isNotEmpty
              ? finalAddress
              : "Lat: ${pos.latitude.toStringAsFixed(4)}, Lng: ${pos.longitude.toStringAsFixed(4)}";
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Reverse geocode failure: $e');
      if (mounted) {
        setState(() {
          _draggedAddress = "Lat: ${pos.latitude.toStringAsFixed(4)}, Lng: ${pos.longitude.toStringAsFixed(4)}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin Delivery Location', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textMain),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _currentPosition, zoom: 16),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  onMapCreated: (controller) => _mapController = controller,
                  onCameraMove: (position) => _currentPosition = position.target,
                  onCameraIdle: () => _onCameraIdleDebounced(_currentPosition),
                ),
                // Center Fixed Pin Marker
                const Padding(
                  padding: EdgeInsets.only(bottom: 35),
                  child: Icon(Icons.location_on, size: 44, color: AppTheme.primary),
                ),

                // Bottom Confirmation Panel
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Selected Location',
                            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_draggedAddress,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.pop(context, {
                                'latitude': _currentPosition.latitude,
                                'longitude': _currentPosition.longitude,
                                'address': _draggedAddress,
                              });
                            },
                            child: const Text('Confirm Location',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
    );
  }
}