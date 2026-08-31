// lib/screens/live_tracking_screen.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../utils/helpers.dart';

class LiveTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isDriver;
  final bool isDineInNavigation;

  const LiveTrackingScreen({
    super.key,
    required this.order,
    required this.isDriver,
    this.isDineInNavigation = false,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final _supabase = Supabase.instance.client;
  GoogleMapController? _mapController;

  LatLng? _currentPosition;
  LatLng? _destinationPosition;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final List<LatLng> _polylineCoordinates = [];

  StreamSubscription<Position>? _positionStream;
  RealtimeChannel? _locationChannel;

  String _etaText = 'Calculating ETA...';
  bool _isLoading = true;

  static const double _distanceRatio = 1.3;
  static const double _speedKmPerMin = 0.5; // Average city driving speed

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _locationChannel?.unsubscribe();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    try {
      // 1. Verify and request GPS location permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled on this device.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 6), onTimeout: () async {
        return await Geolocator.getLastKnownPosition() ??
            Position(
              latitude: 18.6147,
              longitude: 73.7669,
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

      _currentPosition = LatLng(initialPos.latitude, initialPos.longitude);
      _destinationPosition = await _resolveDestinationCoordinates();

      if (_destinationPosition != null) {
        _updateMarkers(_currentPosition!, _destinationPosition);
        _updateEta(_currentPosition!, _destinationPosition!);
        await _fetchPolylineRoute(_currentPosition!, _destinationPosition!);

        Future.delayed(const Duration(milliseconds: 600), () {
          if (_currentPosition != null && _destinationPosition != null && mounted) {
            _zoomToFitRoute(_currentPosition!, _destinationPosition!);
          }
        });
      } else {
        setState(() => _etaText = 'Destination unavailable');
      }

      if (widget.isDriver) {
        _startDriverLocationBroadcasting();
      } else {
        _listenToDriverTelemetry();
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Live tracking initialization error');
      if (mounted) {
        setState(() {
          _etaText = 'Unable to establish GPS fix';
          _currentPosition = const LatLng(18.6147, 73.7669);
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<LatLng?> _resolveDestinationCoordinates() async {
    try {
      if (widget.isDineInNavigation) {
        final latStr = widget.order['chef_lat']?.toString() ?? widget.order['hosting_lat']?.toString();
        final lngStr = widget.order['chef_lng']?.toString() ?? widget.order['hosting_lng']?.toString();

        if (latStr != null && lngStr != null && latStr.isNotEmpty && lngStr.isNotEmpty) {
          return LatLng(double.parse(latStr), double.parse(lngStr));
        }

        final chefAddress = widget.order['chef_address']?.toString() ?? widget.order['hosting_address']?.toString();
        if (chefAddress != null && chefAddress.isNotEmpty) {
          List<Location> locs = await locationFromAddress(chefAddress);
          if (locs.isNotEmpty) return LatLng(locs.first.latitude, locs.first.longitude);
        }
      } else {
        final latStr = widget.order['delivery_lat']?.toString() ?? widget.order['customer_lat']?.toString();
        final lngStr = widget.order['delivery_lng']?.toString() ?? widget.order['customer_lng']?.toString();

        if (latStr != null && lngStr != null && latStr.isNotEmpty && lngStr.isNotEmpty) {
          return LatLng(double.parse(latStr), double.parse(lngStr));
        }

        final addressStr = widget.order['delivery_address']?.toString();
        if (addressStr != null && addressStr.isNotEmpty) {
          List<Location> locs = await locationFromAddress(addressStr);
          if (locs.isNotEmpty) return LatLng(locs.first.latitude, locs.first.longitude);
        }
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Destination coordinate resolution failed');
    }
    return null;
  }

  void _updateEta(LatLng origin, LatLng destination) {
    double straightDistMeters = Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );

    if (straightDistMeters < 40) {
      if (mounted) setState(() => _etaText = 'Arriving shortly');
      return;
    }

    double drivingKm = (straightDistMeters / 1000.0) * _distanceRatio;
    int estimatedMinutes = math.max(1, (drivingKm / _speedKmPerMin).round());

    if (mounted) {
      setState(() => _etaText = 'Arriving in $estimatedMinutes mins');
    }
  }

  void _updateMarkers(LatLng current, LatLng? destination) {
    if (!mounted) return;
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('current_movable_pin'),
          position: current,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'Live Location'),
        ),
        if (destination != null)
          Marker(
            markerId: const MarkerId('destination_pin'),
            position: destination,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ),
      };
    });
  }

  Future<void> _fetchPolylineRoute(LatLng origin, LatLng destination) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) return;

      PolylinePoints polylinePoints = PolylinePoints(apiKey: apiKey);
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty && mounted) {
        _polylineCoordinates.clear();
        for (var point in result.points) {
          _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }

        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route_polyline'),
              color: AppTheme.primary,
              width: 5,
              points: _polylineCoordinates,
            ),
          };
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Polyline route fetch failure');
    }
  }

  void _zoomToFitRoute(LatLng origin, LatLng destination) {
    if (_mapController == null) return;
    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(origin.latitude, destination.latitude),
        math.min(origin.longitude, destination.longitude),
      ),
      northeast: LatLng(
        math.max(origin.latitude, destination.latitude),
        math.max(origin.longitude, destination.longitude),
      ),
    );
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  // --- Realtime Location Broadcasting & Listening ---

  void _startDriverLocationBroadcasting() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15, // Throttle pings to 15-meter movements to save quota
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (!mounted) return;
      LatLng newPos = LatLng(position.latitude, position.longitude);
      setState(() => _currentPosition = newPos);

      _updateMarkers(newPos, _destinationPosition);
      if (_destinationPosition != null) {
        _updateEta(newPos, _destinationPosition!);
      }

      // Broadcast telemetry over Supabase Realtime channel
      _locationChannel ??= _supabase.channel('order_${widget.order['id']}');
      _locationChannel!.sendBroadcastMessage(
        event: 'location_update',
        payload: {'lat': position.latitude, 'lng': position.longitude},
      );
    });
  }

  void _listenToDriverTelemetry() {
    final orderId = widget.order['id']?.toString() ?? '';
    if (orderId.isEmpty) return;

    _locationChannel = _supabase.channel('order_$orderId');
    _locationChannel!
        .onBroadcast(
          event: 'location_update',
          callback: (payload) {
            if (!mounted) return;
            final lat = payload['lat'] as num?;
            final lng = payload['lng'] as num?;

            if (lat != null && lng != null) {
              LatLng updatedPos = LatLng(lat.toDouble(), lng.toDouble());
              setState(() => _currentPosition = updatedPos);

              _updateMarkers(updatedPos, _destinationPosition);
              if (_destinationPosition != null) {
                _updateEta(updatedPos, _destinationPosition!);
              }

              _mapController?.animateCamera(CameraUpdate.newLatLng(updatedPos));
            }
          },
        )
        .subscribe();
  }

  // --- Order Summary Modal ---

  void _showOrderSummaryModal() {
    final double itemPrice = (widget.order['price'] as num?)?.toDouble() ?? 250.0;
    final int qty = (widget.order['quantity'] as num?)?.toInt() ?? 1;
    final double basketValue = itemPrice * qty;
    final double billTotal = basketValue + 20.0; // Packaging fee fallback

    final String customerName = widget.order['customer_name']?.toString() ?? 'Customer';
    final String customerPhone = widget.order['customer_phone']?.toString() ?? '';
    final String deliveryAddress = widget.order['delivery_address']?.toString() ?? 'Delivery Address';
    final String orderIdStr = formatOrderId(widget.order['order_id']?.toString(), widget.order['id'].toString());
    final String orderDate = formatOrderDate(widget.order['created_at']?.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.fastfood, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${widget.order['title'] ?? 'Meal Order'} (x$qty)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
                      const SizedBox(height: 2),
                      Text('Order confirmed & dispatched',
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Text('₹${basketValue.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textMain)),
              ],
            ),
            const Divider(height: 32, color: Colors.black12),
            const Text('Delivery details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain)),
            const SizedBox(height: 12),
            _buildDetailTile(icon: Icons.person_outline, title: customerName, subtitle: customerPhone),
            const SizedBox(height: 10),
            _buildDetailTile(icon: Icons.location_on_outlined, title: deliveryAddress, subtitle: 'Destination address'),
            const SizedBox(height: 10),
            _buildDetailTile(icon: Icons.confirmation_number_outlined, title: orderIdStr, subtitle: 'Order reference'),
            const SizedBox(height: 10),
            _buildDetailTile(icon: Icons.calendar_today_outlined, title: orderDate, subtitle: 'Timestamp'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailTile({required IconData icon, required String title, required String subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: AppTheme.textMain),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textMain)),
              const SizedBox(height: 1),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_etaText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.support_agent, color: AppTheme.primary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connecting to support...')));
            },
          ),
        ],
      ),
      body: _isLoading || _currentPosition == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _currentPosition!, zoom: 15),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  onMapCreated: (controller) => _mapController = controller,
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.delivery_dining, color: AppTheme.primary, size: 24),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_etaText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textMain)),
                                const Text('Live route tracking active', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                          onPressed: _showOrderSummaryModal,
                          child: const Text('Details', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}