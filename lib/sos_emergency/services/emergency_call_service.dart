import 'package:url_launcher/url_launcher.dart';

class EmergencyCallService {
  Future<bool> call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
