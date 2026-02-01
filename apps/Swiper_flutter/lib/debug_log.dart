import 'package:dio/dio.dart';

/// Fire-and-forget log for debug session. POSTs to Cursor ingest; server writes NDJSON to .cursor/debug.log.
void debugLog(String location, String message, Map<String, dynamic> data, {String? hypothesisId}) {
  final payload = {
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'sessionId': 'debug-session',
    if (hypothesisId != null) 'hypothesisId': hypothesisId,
  };
  Dio()
      .post(
        'http://127.0.0.1:7245/ingest/ddc9e3c2-ad47-4244-9d77-ce2efa8256ba',
        data: payload,
        options: Options(sendTimeout: const Duration(milliseconds: 200), receiveTimeout: const Duration(milliseconds: 200)),
      )
      .catchError((_) {});
}
