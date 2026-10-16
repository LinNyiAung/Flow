// Creates the HTTP client used for the streaming AI chat. The browser's default
// `http` client buffers whole responses, so the web build uses fetch (which
// streams); Android keeps the plain `http.Client()`.
export 'streaming_client_io.dart'
    if (dart.library.js_interop) 'streaming_client_web.dart';
