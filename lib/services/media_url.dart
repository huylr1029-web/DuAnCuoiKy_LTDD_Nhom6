import '../config.dart';

/// Uploads are served from the API host, outside the /api route prefix.
String resolveMediaUrl(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text);
  if (uri == null) return '';
  if (uri.hasScheme) {
    return uri.scheme == 'http' || uri.scheme == 'https' ? text : '';
  }
  final base = Uri.parse(apiBaseUrl);
  final path = base.path.replaceFirst(RegExp(r'/api$'), '');
  return base
      .replace(path: '$path/', query: null, fragment: null)
      .resolve(text)
      .toString();
}
