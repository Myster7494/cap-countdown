import 'package:cap_countdown/src/config/config_helper.dart';
import 'package:pub_semver/pub_semver.dart';

class ConfigInstance {
  DateTime get capStartTime => DateTime.fromMillisecondsSinceEpoch(
      ConfigHelper.get<int>('cap_start_time'));

  Version get appVersion =>
      Version.parse(ConfigHelper.get<String>('app_version'));
}