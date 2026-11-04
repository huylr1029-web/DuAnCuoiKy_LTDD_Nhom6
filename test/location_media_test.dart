import 'package:flutter_test/flutter_test.dart';
import 'package:nhom6/config.dart';
import 'package:nhom6/models/api_models.dart';
import 'package:nhom6/services/auth_service.dart';
import 'package:nhom6/services/location_service.dart';
import 'package:nhom6/services/media_url.dart';

void main() {
  test('Vietnamese phone numbers normalize for friend lookup', () {
    for (final phone in ['0912 345 678', '+84912345678', '84912345678']) {
      expect(AuthService.normalizePhone(phone), '+84912345678');
    }
    expect(AuthService.normalizePhone('123456'), isNull);
  });

  test('Shared location opens the same coordinates in Google Maps', () {
    final uri = LocationService.mapUri('10.762622, 106.660172');
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters['query'], '10.762622,106.660172');
    for (final invalid in ['abc', '91,0', '0,181', 'NaN,0', '0,Infinity']) {
      expect(() => LocationService.mapUri(invalid), throwsFormatException);
    }
  });

  test('Uploaded media resolves on the API host and text stays unchanged', () {
    final url = resolveMediaUrl('/uploads/chat/photo.jpg');
    expect(Uri.parse(url).host, Uri.parse(apiBaseUrl).host);
    expect(Uri.parse(url).path, '/uploads/chat/photo.jpg');
    expect(
      resolveMediaUrl('https://cdn.example.com/a.jpg'),
      'https://cdn.example.com/a.jpg',
    );
    expect(resolveMediaUrl('file:///private/image.jpg'), isEmpty);
    final image = MessageItem.fromJson({
      'type': 'image',
      'text': '/uploads/a.jpg',
    });
    expect(Uri.parse(image.text).path, '/uploads/a.jpg');
    expect(
      MessageItem.fromJson({'type': 'text', 'text': '/hello'}).text,
      '/hello',
    );
  });
}
