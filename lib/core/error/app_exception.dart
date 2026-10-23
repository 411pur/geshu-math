/// Typed error hierarchy for the entire app.
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

class NetworkException extends AppException {
  final int? statusCode;
  const NetworkException(super.message, {this.statusCode});
}

class DifyApiException extends AppException {
  final String? workflow;
  const DifyApiException(super.message, {this.workflow});
}

class AiApiException extends AppException {
  const AiApiException(super.message);
}

class DatabaseException extends AppException {
  final String? cause;
  const DatabaseException(super.message, {this.cause});
}

class OcrException extends AppException {
  const OcrException(super.message);
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}