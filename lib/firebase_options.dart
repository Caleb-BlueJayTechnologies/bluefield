import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase is only configured for Web and Android right now.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBFzZCdHT2pu9R-GMmxb6CKgx95rJtFKTM',
    authDomain: 'bluefield-f9eb9.firebaseapp.com',
    databaseURL: 'https://bluefield-f9eb9-default-rtdb.firebaseio.com',
    projectId: 'bluefield-f9eb9',
    storageBucket: 'bluefield-f9eb9.firebasestorage.app',
    messagingSenderId: '903012762212',
    appId: '1:903012762212:web:1834d21f5e116038c49571',
    measurementId: 'G-6W0LM4WB9T',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDQnO_j9K0A2B9pZcTmkq74h_3nQkhw180',
    appId: '1:903012762212:android:9b9242f2148e4b70c49571',
    messagingSenderId: '903012762212',
    projectId: 'bluefield-f9eb9',
    databaseURL: 'https://bluefield-f9eb9-default-rtdb.firebaseio.com',
    storageBucket: 'bluefield-f9eb9.firebasestorage.app',
  );
}