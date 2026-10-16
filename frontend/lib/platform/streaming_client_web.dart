import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// fetch-based client: unlike the XHR-based default it delivers the response
/// body incrementally, and closing it aborts the in-flight request.
http.Client createStreamingClient() => FetchClient(mode: RequestMode.cors);
