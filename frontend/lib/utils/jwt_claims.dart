import 'dart:convert';

/// When [token] (a JWT) was issued: its payload's `iat`, read WITHOUT
/// checking the signature (only the server can, and it does on every call).
/// Null for anything that is not a JWT with a numeric `iat`.
DateTime? jwtIssuedAt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final iat = payload['iat'];
    if (iat is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (iat * 1000).round(),
      isUtc: true,
    );
  } on FormatException {
    return null;
  } on ArgumentError {
    // An `iat` outside DateTime's range.
    return null;
  }
}
