import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  const AppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  factory AppInfo.fromPackageInfo(PackageInfo packageInfo) {
    return AppInfo(
      appName: packageInfo.appName.isEmpty ? 'OpenHand' : packageInfo.appName,
      packageName: packageInfo.packageName.isEmpty
          ? 'com.flwork.openhand'
          : packageInfo.packageName,
      version: packageInfo.version.isEmpty ? '0.1.0' : packageInfo.version,
      buildNumber: packageInfo.buildNumber.isEmpty
          ? '1'
          : packageInfo.buildNumber,
    );
  }

  factory AppInfo.fallback() {
    return const AppInfo(
      appName: 'OpenHand',
      packageName: 'com.flwork.openhand',
      version: '0.1.0',
      buildNumber: '1',
    );
  }

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  String get displayVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';
}
