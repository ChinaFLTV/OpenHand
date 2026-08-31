import 'package:package_info_plus/package_info_plus.dart';

const String kOpenHandDefaultAppName = 'OpenHand';
const String _kDefaultPackageName = 'com.flwork.openhand';
const String _kDefaultVersion = '0.1.0';
const String _kDefaultBuildNumber = '1';

class AppInfo {
  const AppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  factory AppInfo.fromPackageInfo(PackageInfo packageInfo) {
    return AppInfo(
      appName: packageInfo.appName.isEmpty
          ? kOpenHandDefaultAppName
          : packageInfo.appName,
      packageName: packageInfo.packageName.isEmpty
          ? _kDefaultPackageName
          : packageInfo.packageName,
      version: packageInfo.version.isEmpty
          ? _kDefaultVersion
          : packageInfo.version,
      buildNumber: packageInfo.buildNumber.isEmpty
          ? _kDefaultBuildNumber
          : packageInfo.buildNumber,
    );
  }

  factory AppInfo.fallback() {
    return const AppInfo(
      appName: kOpenHandDefaultAppName,
      packageName: _kDefaultPackageName,
      version: _kDefaultVersion,
      buildNumber: _kDefaultBuildNumber,
    );
  }

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  String get displayVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';
}
