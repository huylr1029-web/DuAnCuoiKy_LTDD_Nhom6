import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationService {
  static Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('GPS đang tắt. Hãy bật vị trí trong cài đặt thiết bị.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Hãy mở cài đặt ứng dụng và cấp quyền vị trí.');
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw StateError('Cần cấp quyền vị trí để chia sẻ.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  }

  static Uri mapUri(String coordinates) {
    final parts = coordinates.split(',');
    final lat = parts.length == 2 ? double.tryParse(parts[0].trim()) : null;
    final lng = parts.length == 2 ? double.tryParse(parts[1].trim()) : null;
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      throw const FormatException('Vị trí không hợp lệ.');
    }
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$lat,$lng',
    });
  }

  static Future<void> openMap(String coordinates) async {
    final uri = mapUri(coordinates);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Không mở được Google Maps trên thiết bị.');
    }
  }
}
