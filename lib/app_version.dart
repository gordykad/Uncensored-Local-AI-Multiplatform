/// The app's version, centralized (design audit #10).
///
/// pubspec.yaml stays the build's source of truth for Codemagic;
/// every RENDERED or SERVED version string in Dart reads this one
/// constant, so the settings footer and the local API can never
/// drift from each other again (the 1.14.1 stale-string audit
/// failure was three hand-edited spots). Bump both together -
/// the IPA audit verifies the served value against the build.
const String kAppVersion = '1.20.8';
