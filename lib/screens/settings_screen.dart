import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Firebase/firestore_schema.dart';
import '../Models/company_model.dart';
import '../Models/crew_model.dart';
import '../Models/employee_model.dart';
import '../Services/auth_service.dart';
import '../Services/biometric_auth_service.dart';
import '../Services/company_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/crew_service.dart';
import '../Services/employee_service.dart';
import '../Services/permission_service.dart';
import '../Services/platform_admin_service.dart';
import '../theme/app_theme.dart';
import 'admin/admin_gate_screen.dart';
import 'auth/change_password_screen.dart';
import 'company_settings_screen.dart';
import 'feedback_screen.dart';
import 'legal_acceptance_history_screen.dart';
import 'legal_document_screen.dart';
import 'my_tickets_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final EmployeeService _employeeService = EmployeeService();
  final CompanyService _companyService = CompanyService();
  final CrewService _crewService = CrewService();
  final CompanySettingsService _settingsService = CompanySettingsService();
  final PlatformAdminService _platformAdminService = PlatformAdminService();

  late Future<_SettingsData> _settingsFuture;

  bool _messagesEnabled = true;
  bool _scheduleEnabled = true;
  bool _announcementsEnabled = true;
  bool _timeOffEnabled = true;
  bool _payrollEnabled = true;
  bool _savingPreferences = false;

  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _savingBiometric = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
  }

  Future<_SettingsData> _loadSettings() async {
    final profile = await _authService.getCurrentUserProfile();

    // Self-heals a missing employees/{uid} doc automatically (see
    // EmployeeService.ensureEmployeeRecordExists) rather than silently
    // showing "Unknown" everywhere that resolves names — Settings is a
    // natural place for this check since it already loads the
    // employee record on every visit.
    final employee = await _employeeService.ensureEmployeeRecordExists(
      companyId: profile.activeCompanyId,
      userId: profile.uid,
    );

    final company = await _companyService.getCompany(profile.activeCompanyId);
    final companySettings =
        await _settingsService.getCompanySettings(profile.activeCompanyId);

    final crews = <CrewModel>[];
    for (final crewId in employee?.crewIds ?? const []) {
      final crew = await _crewService.getCrew(companyId: profile.activeCompanyId, crewId: crewId);
      if (crew != null) crews.add(crew);
    }

    // Notification preferences live as a loose map on the user doc
    // (not part of AppUser's typed fields) — read directly here.
    final userDoc = await FirebaseFirestore.instance
        .collection(FSCollections.users)
        .doc(profile.uid)
        .get();
    final preferences = _mapValue(userDoc.data()?['notificationPreferences']);

    _messagesEnabled = _boolValue(preferences, 'messages', fallback: true);
    _scheduleEnabled = _boolValue(preferences, 'scheduleChanges', fallback: true);
    _announcementsEnabled = _boolValue(preferences, 'announcements', fallback: true);
    _timeOffEnabled = _boolValue(preferences, 'timeOff', fallback: true);
    _payrollEnabled = _boolValue(preferences, 'payroll', fallback: true);

    // Invisible to literally everyone except the bootstrap admin
    // account (or anyone that account later grants access to) — see
    // PlatformAdminService.bootstrapSuperAdminEmail. No visible button
    // exists for this unless the check actually passes.
    final platformAdmin = await _platformAdminService.getCurrentAdmin();

    _biometricSupported = await _biometricService.isDeviceSupported();
    _biometricEnabled = _biometricSupported && await _biometricService.isEnabled();

    return _SettingsData(
      profile: profile,
      employee: employee,
      company: company,
      crews: crews,
      crewLabel: companySettings.crewTerminology == 'team' ? 'Team' : 'Crew',
      canEditCompanyProfile: PermissionService.roleHasPermission(
        profile.role,
        Permission.companyEditProfile,
      ),
      isPlatformAdmin: platformAdmin != null,
    );
  }

  Future<void> _saveNotificationPreference({
    required String key,
    required bool value,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _savingPreferences = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection(FSCollections.users)
          .doc(user.uid)
          .set(
        {
          'notificationPreferences': {key: value},
          FSFields.updatedAt: FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingPreferences = false;
        });
      }
    }
  }

  /// Enabling from Settings needs the account password once — not
  /// stored anywhere after the original sign-in, so it has to be
  /// re-entered here rather than reused. [_promptForPassword] collects
  /// it, then it's verified against Firebase via reauthentication
  /// BEFORE ever being handed to BiometricAuthService.enable — storing
  /// an unverified password behind biometrics would mean a typo here
  /// silently breaks quick sign-in every time it's actually used later,
  /// with no obvious reason why. Disabling needs no such check.
  Future<void> _toggleBiometric(bool value) async {
    if (!value) {
      setState(() => _savingBiometric = true);
      try {
        await _biometricService.disable();
        if (!mounted) return;
        setState(() => _biometricEnabled = false);
      } finally {
        if (mounted) setState(() => _savingBiometric = false);
      }
      return;
    }

    final password = await _promptForPassword();
    if (password == null || password.isEmpty) return;

    setState(() => _savingBiometric = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        throw Exception('Unable to verify your account. Try signing out and back in.');
      }

      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );

      final enabled = await _biometricService.enable(email: email, password: password);
      if (!mounted) return;
      if (enabled) {
        setState(() => _biometricEnabled = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quick sign-in wasn\'t enabled — the biometric check didn\'t succeed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authService.friendlyAuthErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _savingBiometric = false);
    }
  }

  Future<String?> _promptForPassword() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              icon: const Icon(Icons.fingerprint, color: AppTheme.blue, size: 36),
              title: const Text('Enable Quick Sign-In'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Confirm your password once — after this, fingerprint or Face ID signs you in.',
                      style: TextStyle(fontSize: 13, color: AppTheme.mutedText),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: controller,
                      obscureText: obscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(() => obscure = !obscure),
                          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                      onFieldSubmitted: (_) {
                        if (formKey.currentState!.validate()) {
                          Navigator.of(dialogContext).pop(controller.text);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(dialogContext).pop(controller.text);
                    }
                  },
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return password;
  }

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    await _authService.logout();

    if (!context.mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openChangePassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ChangePasswordScreen(),
      ),
    );
  }

  Future<void> _openCompanySettings() async {
    final shouldRefresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const CompanySettingsScreen(),
      ),
    );

    if (shouldRefresh == true && mounted) {
      setState(() {
        _settingsFuture = _loadSettings();
      });
    }
  }

  void _showLockedMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      default:
        return 'Employee';
    }
  }

  String _roleDescription(String role) {
    switch (role) {
      case 'owner':
        return 'Full company access';
      case 'manager':
        return 'Manager access controlled by company permissions';
      default:
        return 'Employee access controlled by company settings';
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  static bool _boolValue(
    Map<String, dynamic> data,
    String key, {
    required bool fallback,
  }) {
    final value = data[key];
    if (value is bool) return value;
    return fallback;
  }

  static Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.darkText,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: FutureBuilder<_SettingsData>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
              children: [
                _ErrorCard(message: _cleanError(snapshot.error!)),
                const SizedBox(height: 10),
                _LogoutButton(onPressed: () => _logout(context)),
              ],
            );
          }

          final data = snapshot.data;

          if (data == null) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
              children: [
                const _ErrorCard(message: 'Settings could not be loaded.'),
                const SizedBox(height: 10),
                _LogoutButton(onPressed: () => _logout(context)),
              ],
            );
          }

          final profile = data.profile;
          final employee = data.employee;
          final role = profile.role;
          final isOwner = profile.isOwnerRole;
          final isManager = profile.isManagerRole;
          final companyName = data.company?.companyName ?? 'Company not provided';
          final roleLabel = _roleLabel(role);

          final fullName = employee?.fullName.trim().isNotEmpty == true
              ? employee!.fullName
              : '${profile.firstName} ${profile.lastName}'.trim();

          final crewName = data.crews.isNotEmpty
              ? data.crews.map((c) => c.crewName).join(', ')
              : (isOwner ? 'Company Admin' : 'No ${data.crewLabel.toLowerCase()} assigned');

          final phone = employee?.phone?.trim().isNotEmpty == true
              ? employee!.phone!
              : 'Not provided';

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _settingsFuture = _loadSettings();
              });
              await _settingsFuture;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
              children: [
                _SettingsHeader(
                  name: fullName.isEmpty ? 'BlueField User' : fullName,
                  subtitle: '$roleLabel • $crewName',
                  companyName: companyName,
                ),
                const SizedBox(height: 14),
                _SettingsSection(
                  title: 'Profile',
                  note: 'These values reflect your BlueField account and employee record.',
                  children: [
                    _SettingsTile(
                      icon: Icons.person_outline,
                      title: 'Name',
                      subtitle: fullName.isEmpty ? 'Not provided' : fullName,
                      trailingText: 'View',
                    ),
                    _SettingsTile(
                      icon: Icons.phone_outlined,
                      title: 'Phone Number',
                      subtitle: phone,
                      trailingText: 'Locked',
                      onTap: () => _showLockedMessage(
                        'Profile editing will be added later. For now, changes are managed from the employee record.',
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.email_outlined,
                      title: 'Email',
                      subtitle: profile.email.isEmpty ? 'Not provided' : profile.email,
                      trailingText: 'Locked',
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Notifications',
                  note: _savingPreferences
                      ? 'Saving notification preferences...'
                      : 'These switches are saved to your user account.',
                  children: [
                    _SettingsSwitchTile(
                      icon: Icons.message_outlined,
                      title: 'Messages',
                      subtitle: 'Crew, direct, and company messages',
                      value: _messagesEnabled,
                      onChanged: (value) {
                        setState(() => _messagesEnabled = value);
                        _saveNotificationPreference(key: 'messages', value: value);
                      },
                    ),
                    _SettingsSwitchTile(
                      icon: Icons.calendar_month_outlined,
                      title: 'Schedule Changes',
                      subtitle: 'New jobs, updates, and cancellations',
                      value: _scheduleEnabled,
                      onChanged: (value) {
                        setState(() => _scheduleEnabled = value);
                        _saveNotificationPreference(key: 'scheduleChanges', value: value);
                      },
                    ),
                    _SettingsSwitchTile(
                      icon: Icons.campaign_outlined,
                      title: 'Announcements',
                      subtitle: 'Company-wide updates',
                      value: _announcementsEnabled,
                      onChanged: (value) {
                        setState(() => _announcementsEnabled = value);
                        _saveNotificationPreference(key: 'announcements', value: value);
                      },
                    ),
                    _SettingsSwitchTile(
                      icon: Icons.event_busy_outlined,
                      title: 'Time Off Updates',
                      subtitle: 'Request status changes and approvals',
                      value: _timeOffEnabled,
                      onChanged: (value) {
                        setState(() => _timeOffEnabled = value);
                        _saveNotificationPreference(key: 'timeOff', value: value);
                      },
                    ),
                    _SettingsSwitchTile(
                      icon: Icons.payments_outlined,
                      title: 'Payroll Updates',
                      subtitle: 'Payroll summaries and pay-period alerts',
                      value: _payrollEnabled,
                      onChanged: (value) {
                        setState(() => _payrollEnabled = value);
                        _saveNotificationPreference(key: 'payroll', value: value);
                      },
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Company-Controlled',
                  note: _roleDescription(role),
                  children: [
                    _SettingsTile(
                      icon: Icons.business_outlined,
                      title: 'Company',
                      subtitle: companyName,
                      trailingText: 'Locked',
                    ),
                    _SettingsTile(
                      icon: Icons.badge_outlined,
                      title: 'Role',
                      subtitle: roleLabel,
                      trailingText: 'Locked',
                    ),
                    _SettingsTile(
                      icon: Icons.groups_outlined,
                      title: data.crewLabel,
                      subtitle: crewName,
                      trailingText: 'Locked',
                    ),
                  ],
                ),
                if (isOwner)
                  _SettingsSection(
                    title: 'Owner Tools',
                    note: 'Company-wide setup and feature toggles belong here.',
                    children: [
                      _SettingsTile(
                        icon: Icons.tune_outlined,
                        title: 'Company Settings',
                        subtitle: 'Company info, dashboard features, and setup toggles',
                        trailingText: 'Open',
                        onTap: _openCompanySettings,
                      ),
                    ],
                  ),
                if (isManager)
                  _SettingsSection(
                    title: 'Manager Access',
                    note: 'Your manager tools are controlled by company permissions.',
                    children: [
                      const _SettingsTile(
                        icon: Icons.manage_accounts_outlined,
                        title: 'Manager Role',
                        subtitle: 'Can view assigned manager dashboard tools',
                        trailingText: 'Locked',
                      ),
                      // Real permission check, not a hardcoded lock —
                      // managers get companyEditProfile by default in
                      // the permission matrix (see permission_service.dart),
                      // so this should actually be reachable for most
                      // managers rather than always saying "Locked".
                      _SettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Company Settings',
                        subtitle: data.canEditCompanyProfile
                            ? 'Edit company info and dashboard features'
                            : 'Not permitted by your current role',
                        trailingText: data.canEditCompanyProfile ? 'Open' : 'Locked',
                        onTap: data.canEditCompanyProfile ? _openCompanySettings : null,
                      ),
                    ],
                  ),
                _SettingsSection(
                  title: 'Security',
                  children: [
                    _SettingsTile(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      subtitle: 'Update your account password',
                      trailingText: 'Open',
                      onTap: _openChangePassword,
                    ),
                    if (_biometricSupported)
                      _SettingsSwitchTile(
                        icon: Icons.fingerprint,
                        title: 'Quick Sign-In',
                        subtitle: _biometricEnabled
                            ? 'Fingerprint/Face ID sign-in is on for this device'
                            : 'Sign in faster with fingerprint or Face ID',
                        value: _biometricEnabled,
                        onChanged: _savingBiometric ? null : _toggleBiometric,
                      ),
                  ],
                ),
                _SettingsSection(
                  title: 'Legal & Privacy',
                  children: [
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: 'Company Terms of Service',
                      subtitle: 'The current version, and what you accepted',
                      trailingText: 'Open',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const LegalDocumentScreen(documentType: FSLegalDocumentType.companyTerms),
                          ),
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      subtitle: 'How BlueJay handles information in BlueField',
                      trailingText: 'Open',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const LegalDocumentScreen(documentType: FSLegalDocumentType.privacyPolicy),
                          ),
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.history_outlined,
                      title: 'My Acceptance History',
                      subtitle: 'Every version you\'ve accepted, and when',
                      trailingText: 'Open',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const LegalAcceptanceHistoryScreen()),
                        );
                      },
                    ),
                  ],
                ),
                _SettingsSection(
                  title: 'Support',
                  note: 'Report a bug, request a feature, or ask a question.',
                  children: [
                    _SettingsTile(
                      icon: Icons.feedback_outlined,
                      title: 'Submit Feedback',
                      subtitle: 'Bug reports, feature requests, questions',
                      trailingText: 'Open',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const FeedbackScreen()));
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.confirmation_number_outlined,
                      title: 'My Tickets',
                      subtitle: 'Track the status of what you\'ve submitted',
                      trailingText: 'Open',
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const MyTicketsScreen()));
                      },
                    ),
                  ],
                ),
                // Structurally invisible, not just hidden — this
                // section is never even built unless data.isPlatformAdmin
                // resolved true, which only ever happens for the
                // bootstrap admin account (or someone that account has
                // explicitly granted access to via the Admin Panel
                // itself). Everyone else never sees this exists.
                if (data.isPlatformAdmin)
                  _SettingsSection(
                    title: 'BlueJay Admin',
                    note: 'Only visible on this account.',
                    children: [
                      _SettingsTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Admin Panel',
                        subtitle: 'Support tickets across every company',
                        trailingText: 'Open',
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminGateScreen()));
                        },
                      ),
                    ],
                  ),
                const _SettingsSection(
                  title: 'App',
                  children: [
                    _SettingsTile(
                      icon: Icons.palette_outlined,
                      title: 'Theme',
                      subtitle: 'Dark mode coming soon',
                      trailingText: 'Coming Soon',
                    ),
                    _SettingsTile(
                      icon: Icons.info_outline,
                      title: 'Version',
                      subtitle: 'BlueField 1.0',
                      trailingText: '',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _LogoutButton(onPressed: () => _logout(context)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsData {
  final AuthUserProfile profile;
  final EmployeeModel? employee;
  final CompanyModel? company;
  final List<CrewModel> crews;
  final String crewLabel;
  final bool canEditCompanyProfile;
  final bool isPlatformAdmin;

  const _SettingsData({
    required this.profile,
    required this.employee,
    required this.company,
    this.crews = const [],
    required this.crewLabel,
    required this.canEditCompanyProfile,
    required this.isPlatformAdmin,
  });
}

class _SettingsHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final String companyName;

  const _SettingsHeader({
    required this.name,
    required this.subtitle,
    required this.companyName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppTheme.blue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 34,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                color: AppTheme.blue,
                size: 42,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    companyName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String? note;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    this.note,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkText,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(
                note!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedText,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailingText;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLocked = trailingText == 'Locked';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTheme.darkText,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppTheme.mutedText,
        ),
      ),
      trailing: trailingText.isEmpty
          ? null
          : Text(
              trailingText,
              style: TextStyle(
                color: isLocked ? AppTheme.mutedText : AppTheme.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: AppTheme.blue),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTheme.darkText,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppTheme.mutedText,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.logout),
        label: const Text('Log Out'),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.error_outline,
          color: Colors.red,
        ),
        title: const Text(
          'Unable to load settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.darkText,
          ),
        ),
        subtitle: Text(
          message,
          style: const TextStyle(color: AppTheme.mutedText),
        ),
      ),
    );
  }
}
