import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../utils/helpers.dart';

class KitchenLiveSession extends ChangeNotifier {
  KitchenLiveSession({
    required this.chefId,
    required this.isHost,
    this.chefName = 'Kitchen',
  });

  final String chefId;
  final bool isHost;
  final String chefName;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  String status = 'Starting…';
  String? error;
  bool connected = false;
  bool ended = false;
  bool timedOut = false;
  bool micOn = true;
  int viewerCount = 0;
  Duration remaining = const Duration(seconds: kKitchenLiveMaxSeconds);

  final _peers = <String, RTCPeerConnection>{};
  final _pendingIce = <String, List<RTCIceCandidate>>{};
  final _remoteReady = <String>{};
  final _seenSignals = <int>{};

  MediaStream? _localStream;
  RealtimeChannel? _channel;
  Timer? _clock;
  DateTime? _startedAt;
  String _myId = '';
  bool _started = false;
  bool _disposed = false;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _myId = isHost ? chefId.trim() : kitchenLiveViewerId(userId: _client.auth.currentUser?.id);

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    if (isHost) {
      await _startHost();
    } else {
      await _startViewer();
    }
  }

  Future<void> _startHost() async {
    try {
      _setStatus('Opening the kitchen camera…');
      _localStream = await _openCamera();
      localRenderer.srcObject = _localStream;
      notifyListeners();

      await _client.from('kitchen_live_signals').delete().eq('room_id', chefId);
      _startedAt = DateTime.now().toUtc();
      await _setLiveFlag(true);
      _startClock(_startedAt!);
      await _listenSignals();

      final recent = await _client
          .from('kitchen_live_signals')
          .select()
          .eq('room_id', chefId)
          .eq('kind', 'join')
          .order('id');
      for (final row in recent) {
        await _onSignal(Map<String, dynamic>.from(row as Map));
      }

      _setStatus('You are live for 2 minutes. Then go live again for the next diners.');
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen live host start failed');
      _fail('Could not start the kitchen camera. Allow camera and microphone, then try again.');
    }
  }

  Future<void> _startViewer() async {
    try {
      Map<String, dynamic>? profile;
      try {
        profile = await _client
            .from('chef_profiles')
            .select('is_live, live_started_at')
            .eq('user_id', chefId)
            .maybeSingle();
      } catch (e, stack) {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen live status lookup failed');
      }

      if (profile != null && !isKitchenLiveStreaming(profile)) {
        _fail(
          kitchenLiveTimeUp(
            startedAt: DateTime.tryParse(profile['live_started_at']?.toString() ?? ''),
          )
              ? 'This 2-minute kitchen clip just ended. Try the next one.'
              : 'This kitchen is not live right now.',
        );
        return;
      }

      _startedAt = DateTime.tryParse(profile?['live_started_at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc();
      if (!kitchenLiveCanAdmitViewer(startedAt: _startedAt)) {
        _fail('This clip is ending. Catch the next 2-minute kitchen live.');
        return;
      }
      _startClock(_startedAt!);
      _setStatus('Connecting to the kitchen…');
      await _listenSignals();
      await _sendSignal(kind: 'join', targetId: chefId);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen live viewer start failed');
      _fail('Could not join this kitchen live. Try again in a moment.');
    }
  }

  Future<MediaStream> _openCamera() async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'environment',
          'width': 640,
          'height': 480,
          'frameRate': 15,
        },
      });
    } catch (_) {
      return navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': true,
      });
    }
  }

  Future<void> _listenSignals() async {
    _channel = _client
        .channel('kitchen-live-$chefId-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'kitchen_live_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: chefId,
          ),
          callback: (payload) {
            unawaited(_onSignal(Map<String, dynamic>.from(payload.newRecord)));
          },
        );
    _channel!.subscribe();
  }

  void _startClock(DateTime startedAt) {
    _startedAt = startedAt.toUtc();
    remaining = kitchenLiveRemaining(startedAt: _startedAt);
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      remaining = kitchenLiveRemaining(startedAt: _startedAt);
      notifyListeners();
      if (remaining <= Duration.zero) {
        unawaited(_endForTime());
      }
    });
  }

  Future<void> _endForTime() async {
    if (timedOut || _disposed) return;
    timedOut = true;
    ended = true;
    connected = false;
    remaining = Duration.zero;
    _clock?.cancel();
    if (isHost) {
      _setStatus('The 2-minute clip ended. Go live again so the next diners can watch.');
      await stop();
    } else {
      _setStatus('This 2-minute kitchen clip has ended.');
    }
  }

  void markConnectTimeout() {
    if (connected || error != null || ended) return;
    _fail('Still connecting. Some mobile networks block live video.');
  }

  Future<void> _onSignal(Map<String, dynamic> row) async {
    if (_disposed) return;
    final id = int.tryParse(row['id']?.toString() ?? '');
    if (id != null && !_seenSignals.add(id)) return;

    final sender = row['sender_id']?.toString() ?? '';
    final target = row['target_id']?.toString();
    if (!kitchenLiveSignalForMe(myId: _myId, senderId: sender, targetId: target)) {
      return;
    }

    final kind = row['kind']?.toString() ?? '';
    final body = row['body'] is Map ? Map<String, dynamic>.from(row['body'] as Map) : <String, dynamic>{};

    try {
      switch (kind) {
        case 'join':
          if (isHost) await _hostOfferTo(sender);
        case 'leave':
          if (isHost) {
            await _closePeer(sender);
          } else if (sender == chefId) {
            ended = true;
            connected = false;
            _setStatus('The kitchen ended the live stream.');
          }
        case 'offer':
          if (!isHost) await _viewerAnswer(sender, body);
        case 'answer':
          if (isHost) await _hostAcceptAnswer(sender, body);
        case 'ice':
          await _addRemoteIce(sender, body);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen live signal $kind failed');
    }
  }

  Future<void> _hostOfferTo(String viewerId) async {
    if (_peers.containsKey(viewerId)) return;
    if (_peers.length >= kKitchenLiveMaxViewers) return;
    if (!kitchenLiveCanAdmitViewer(startedAt: _startedAt)) return;

    final pc = await _createPeer(viewerId);
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    final offer = await pc.createOffer({
      'offerToReceiveAudio': false,
      'offerToReceiveVideo': false,
    });
    await pc.setLocalDescription(offer);
    await _sendSignal(
      kind: 'offer',
      targetId: viewerId,
      body: {'sdp': offer.sdp, 'type': offer.type},
    );
    _refreshViewerCount();
  }

  Future<void> _viewerAnswer(String hostId, Map<String, dynamic> body) async {
    var pc = _peers[hostId];
    pc ??= await _createPeer(hostId);

    await pc.setRemoteDescription(
      RTCSessionDescription(body['sdp']?.toString() ?? '', body['type']?.toString() ?? 'offer'),
    );
    _remoteReady.add(hostId);
    await _flushIce(hostId, pc);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await _sendSignal(
      kind: 'answer',
      targetId: hostId,
      body: {'sdp': answer.sdp, 'type': answer.type},
    );
    _setStatus('Watching $chefName live from the kitchen.');
  }

  Future<void> _hostAcceptAnswer(String viewerId, Map<String, dynamic> body) async {
    final pc = _peers[viewerId];
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(body['sdp']?.toString() ?? '', body['type']?.toString() ?? 'answer'),
    );
    _remoteReady.add(viewerId);
    await _flushIce(viewerId, pc);
  }

  Future<RTCPeerConnection> _createPeer(String peerId) async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      unawaited(_sendSignal(
        kind: 'ice',
        targetId: peerId,
        body: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      ));
    };

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      connected = true;
      notifyListeners();
    };

    pc.onIceConnectionState = (state) {
      if (_disposed) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        connected = true;
        if (!isHost) _setStatus('Watching $chefName live from the kitchen.');
        notifyListeners();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (!isHost) {
          _fail('Could not reach this kitchen. Some mobile networks block live video.');
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (isHost) {
          unawaited(_closePeer(peerId));
        }
      }
    };

    _peers[peerId] = pc;
    return pc;
  }

  Future<void> _addRemoteIce(String peerId, Map<String, dynamic> body) async {
    final candidate = RTCIceCandidate(
      body['candidate']?.toString() ?? '',
      body['sdpMid']?.toString(),
      int.tryParse(body['sdpMLineIndex']?.toString() ?? ''),
    );
    final pc = _peers[peerId];
    if (pc == null || !_remoteReady.contains(peerId)) {
      _pendingIce.putIfAbsent(peerId, () => []).add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  Future<void> _flushIce(String peerId, RTCPeerConnection pc) async {
    final pending = _pendingIce.remove(peerId) ?? const [];
    for (final candidate in pending) {
      await pc.addCandidate(candidate);
    }
  }

  Future<void> _sendSignal({
    required String kind,
    String? targetId,
    Map<String, dynamic> body = const {},
  }) async {
    await _client.from('kitchen_live_signals').insert({
      'room_id': chefId,
      'sender_id': _myId,
      'target_id': (targetId ?? '').trim().isEmpty ? null : targetId,
      'kind': kind,
      'body': body,
    });
  }

  Future<void> _setLiveFlag(bool live) async {
    await _client.from('chef_profiles').upsert({
      'user_id': chefId,
      'is_live': live,
      if (live) 'is_open': true,
      'live_started_at': live ? DateTime.now().toUtc().toIso8601String() : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> toggleMic() async {
    micOn = !micOn;
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final track in tracks) {
      track.enabled = micOn;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    final track = tracks.first;
    try {
      await Helper.switchCamera(track);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen live camera switch failed');
    }
  }

  Future<void> _closePeer(String peerId) async {
    final pc = _peers.remove(peerId);
    _pendingIce.remove(peerId);
    _remoteReady.remove(peerId);
    await pc?.close();
    _refreshViewerCount();
  }

  void _refreshViewerCount() {
    viewerCount = _peers.length;
    notifyListeners();
  }

  void _setStatus(String next) {
    status = next;
    notifyListeners();
  }

  void _fail(String message) {
    error = message;
    status = message;
    notifyListeners();
  }

  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    _clock?.cancel();
    _clock = null;
    try {
      if (isHost) {
        await _sendSignal(kind: 'leave');
        await _setLiveFlag(false);
        await _client.from('kitchen_live_signals').delete().eq('room_id', chefId);
      } else {
        await _sendSignal(kind: 'leave', targetId: chefId);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Kitchen live stop signal failed');
    }

    await _channel?.unsubscribe();
    _channel = null;

    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();

    final tracks = _localStream?.getTracks() ?? const [];
    for (final track in tracks) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }

}
