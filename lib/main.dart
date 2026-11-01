import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

/// App entrypoint.
///
/// [WidgetsFlutterBinding.ensureInitialized] and [runApp] are executed immediately
/// without awaiting blocking I/O, allowing the Flutter engine to draw the splash
/// screen on the very first frame right after the user taps the app icon.
///
/// Firebase, FCM, and local notifications initialize concurrently in the background
/// via [firebaseInitProvider] during the splash presentation window.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('CoSpend Flutter Framework Error: ${details.exceptionAsString()}');
    // Forward to Crashlytics after Firebase is initialized.
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('CoSpend Unhandled Async Error: $error\n$stack');
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    return true;
  };

  runApp(const ProviderScope(child: CoSpendApp()));
}
