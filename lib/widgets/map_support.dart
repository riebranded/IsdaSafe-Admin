import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether the Google map can be shown: on the web (the Maps JavaScript API
/// loaded in web/index.html) and on Android (a Maps key from `.env`, see
/// android/app/build.gradle.kts). Elsewhere the pages show a list instead.
///
/// `kIsWeb` short-circuits before `Platform` is touched, which isn't
/// available on the web.
bool get isMapViewSupported => kIsWeb || Platform.isAndroid;
