import 'dart:developer' as dev;

import 'app_exception.dart';

/// Centralised error-to-user-message translation.
class ErrorHandler {
  ErrorHandler._();

  /// Convert any thrown object into a user-friendly Chinese message.
  static String toUserMessage(Object error, [StackTrace? stack]) {
    if (stack != null) {
      dev.log('Error handled', error: error, stackTrace: stack);
    }

    if (error is AppException) {
      return error.message;
    }

    // Fallback for unexpected errors.
    return '出了点问题，请稍后再试';
  }

  /// Log the error for debugging (not shown to user directly).
  static void log(Object error, [StackTrace? stack]) {
    dev.log('App error', error: error, stackTrace: stack);
  }
}
