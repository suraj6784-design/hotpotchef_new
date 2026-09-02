import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool connectivityHasLink(List<ConnectivityResult> results) {
  return results.any((result) => result != ConnectivityResult.none);
}

final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  try {
    yield connectivityHasLink(await connectivity.checkConnectivity());
  } catch (_) {
    yield true;
  }
  await for (final results in connectivity.onConnectivityChanged) {
    yield connectivityHasLink(results);
  }
});
