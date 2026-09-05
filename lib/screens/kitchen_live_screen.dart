import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/kitchen_live_service.dart';
import '../utils/helpers.dart';

class KitchenLiveScreen extends StatefulWidget {
  const KitchenLiveScreen({
    super.key,
    required this.chefId,
    this.hostRequested = false,
    this.chefName = 'Kitchen',
  });

  final String chefId;
  final bool hostRequested;
  final String chefName;

  @override
  State<KitchenLiveScreen> createState() => _KitchenLiveScreenState();
}

class _KitchenLiveScreenState extends State<KitchenLiveScreen> {
  late final bool _isHost;
  late final KitchenLiveSession _session;
  Timer? _connectWatch;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _isHost = widget.hostRequested &&
        canHostKitchenLive(
          chefId: widget.chefId,
          userId: Supabase.instance.client.auth.currentUser?.id,
        );
    _session = KitchenLiveSession(
      chefId: widget.chefId.trim(),
      isHost: _isHost,
      chefName: widget.chefName,
    );
    _session.addListener(_onSession);
    unawaited(_session.start());
    if (!_isHost) {
      _connectWatch = Timer(const Duration(seconds: 14), () {
        if (!mounted || _session.connected || _session.error != null || _session.ended) {
          return;
        }
        _session.markConnectTimeout();
      });
    }
  }

  void _onSession() {
    if (!mounted || _leaving || !_session.timedOut) return;
    _leaving = true;
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _connectWatch?.cancel();
    _session.removeListener(_onSession);
    unawaited(_session.stop());
    _session.dispose();
    super.dispose();
  }

  Future<void> _end() async {
    await _session.stop();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.chefName.trim().isEmpty ? 'Kitchen' : widget.chefName.trim();

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final renderer = _isHost ? _session.localRenderer : _session.remoteRenderer;
          final showVideo = _isHost || _session.connected;

          return Stack(
            fit: StackFit.expand,
            children: [
              if (showVideo)
                RTCVideoView(
                  renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: false,
                )
              else
                const ColoredBox(color: Colors.black),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Colors.transparent, Color(0x99000000)],
                    stops: [0, 0.35, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _end,
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _session.status,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _session.remaining.inSeconds <= 20
                                  ? Colors.orange.shade800
                                  : Colors.red.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _isHost
                                  ? '${_session.viewerCount}/$kKitchenLiveMaxViewers · ${kitchenLiveCountdownLabel(_session.remaining)}'
                                  : kitchenLiveCountdownLabel(_session.remaining),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (_session.error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Text(
                          _session.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (_isHost)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Row(
                          children: [
                            _liveAction(
                              icon: _session.micOn ? Icons.mic : Icons.mic_off,
                              label: _session.micOn ? 'Mute' : 'Unmute',
                              onTap: _session.toggleMic,
                            ),
                            const SizedBox(width: 12),
                            _liveAction(
                              icon: Icons.cameraswitch_outlined,
                              label: 'Flip',
                              onTap: _session.switchCamera,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: _end,
                                child: const Text('End live'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Text(
                          '2-minute kitchen clip so more neighbours can watch. Order from the chef card when you are hungry.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _liveAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class KitchenLiveBadge extends StatelessWidget {
  const KitchenLiveBadge({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 3 : 6),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 9 : 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class KitchenWatchLiveButton extends StatelessWidget {
  const KitchenWatchLiveButton({
    super.key,
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 8 : 12),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.videocam, size: 18),
      label: Text(
        'Watch live · 2 min',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 12 : 14, color: AppTheme.snow),
      ),
    );
  }
}
