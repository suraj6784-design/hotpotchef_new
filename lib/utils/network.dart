import 'dart:async';

class NetworkTimeouts {
  static const Duration short = Duration(seconds: 8);
  static const Duration standard = Duration(seconds: 15);
  static const Duration payment = Duration(seconds: 25);
}

class NetworkException implements Exception {
  const NetworkException(this.message, {this.timedOut = false});

  final String message;
  final bool timedOut;

  static const timedOutMessage =
      'This is taking too long. Check your connection and try again.';
  static const offlineMessage =
      "You're offline. Check your connection and try again.";

  @override
  String toString() => message;
}

String networkErrorMessage(Object? error) {
  if (error is NetworkException) return error.message;
  if (error is TimeoutException) return NetworkException.timedOutMessage;
  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('clientexception') ||
      text.contains('connection reset') ||
      text.contains('offline')) {
    return NetworkException.offlineMessage;
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return NetworkException.timedOutMessage;
  }
  return error?.toString() ?? 'Something went wrong. Please try again.';
}

extension WithNetworkTimeout<T> on Future<T> {
  Future<T> withTimeout([Duration duration = NetworkTimeouts.standard]) {
    return timeout(
      duration,
      onTimeout: () => throw const NetworkException(
        NetworkException.timedOutMessage,
        timedOut: true,
      ),
    );
  }
}
