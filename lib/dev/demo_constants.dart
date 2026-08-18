/// Shared constants for the GenericMoversDemo@gmail.com demo tooling —
/// kept in one place so demo_data_seeder.dart (which creates the fake
/// employees' Firebase Auth accounts) and view_as_screen.dart (which
/// signs into them) always agree on the email/password scheme without
/// storing plaintext passwords anywhere in Firestore.
library;

/// One shared password for every seeded demo employee account. Fine for
/// fake, non-sensitive demo data — never used for anything tied to a
/// real customer.
const String kDemoEmployeePassword = 'BlueFieldDemo1!';

/// .test is an IETF-reserved TLD (RFC 2606) that will never resolve to a
/// real mailbox, so these can never collide with — or accidentally
/// email — an actual person.
String demoEmployeeEmail(String firstName, String lastName) {
  final first = firstName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final last = lastName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return '$first.$last@genericmoversdemo.test';
}
