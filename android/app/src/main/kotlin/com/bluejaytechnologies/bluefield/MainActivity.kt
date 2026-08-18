package com.bluejaytechnologies.bluefield

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity — local_auth's Android
// implementation requires a FragmentActivity host to show the
// biometric prompt (it's built on AndroidX's BiometricPrompt, which is
// fragment-based). Plain FlutterActivity would make every
// authenticate() call throw at runtime. Everything else about how the
// app boots is unaffected; FlutterFragmentActivity is a drop-in
// superset of FlutterActivity.
class MainActivity : FlutterFragmentActivity()