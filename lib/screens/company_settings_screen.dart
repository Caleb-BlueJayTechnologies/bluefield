import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../Models/company_settings_model.dart';
import '../Services/auth_service.dart';
import '../Services/company_settings_service.dart';
import '../Services/permission_service.dart';
import '../Theme/app_theme.dart';

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final AuthService _authService = AuthService();
  final CompanySettingsService _settingsService = CompanySettingsService();

  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _businessEmailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _logoUrlController = TextEditingController();
  final TextEditingController _industryTypeController = TextEditingController();
  final TextEditingController _ptoHoursController = TextEditingController();
  final TextEditingController _advanceNoticeController = TextEditingController();
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customValueController = TextEditingController();

  AuthUserProfile? _profile;
  String _crewTerminology = 'crew';

  // Local editable copy of each settings section, kept as plain maps so
  // toggling one switch can immediately cascade child toggles in the UI
  // without a full model round-trip. The real cascade/validation still
  // happens in CompanySettingsService.normalizeParentChildSettings at
  // save time — this is just for responsive editing.
  Map<String, dynamic> _settings = <String, dynamic>{};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _canEditModules {
    final role = _profile?.role;
    if (role == null) return false;
    return PermissionService.roleHasPermission(role, Permission.companyEditModules);
  }

  bool get _canEditProfile {
    final role = _profile?.role;
    if (role == null) return false;
    return PermissionService.roleHasPermission(role, Permission.companyEditProfile);
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _businessEmailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _logoUrlController.dispose();
    _industryTypeController.dispose();
    _ptoHoursController.dispose();
    _advanceNoticeController.dispose();
    _customNameController.dispose();
    _customValueController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await _authService.getCurrentUserProfile();

      // CompanySettingsService already does the correct parsing/defaults
      // (including the companyName-vs-legacy-name migration) — no need
      // to hand-roll it again here.
      final settings = await _settingsService.getCompanySettings(profile.activeCompanyId);

      _profile = profile;
      _crewTerminology = settings.crewTerminology;
      _settings = <String, dynamic>{
        'dashboardFeatures': Map<String, bool>.from(settings.dashboardFeatures),
        'timeOff': Map<String, dynamic>.from(settings.timeOff),
        'teamTime': Map<String, dynamic>.from(settings.teamTime),
        'messaging': Map<String, dynamic>.from(settings.messaging),
        'jobs': Map<String, dynamic>.from(settings.jobs),
        'payroll': Map<String, dynamic>.from(settings.payroll),
        'feedback': Map<String, dynamic>.from(settings.feedback),
        'vehicles': Map<String, dynamic>.from(settings.vehicles),
        'dataProtection': Map<String, dynamic>.from(settings.dataProtection),
        'customSettings': Map<String, dynamic>.from(settings.customSettings),
      };

      _companyNameController.text = settings.companyName;
      _businessEmailController.text = settings.businessEmail;
      _phoneController.text = settings.phone;
      _addressController.text = settings.address;
      _logoUrlController.text = settings.logoUrl;
      _industryTypeController.text = settings.industryType;
      _ptoHoursController.text =
          (_section('timeOff')['defaultPtoHours'] ?? 40).toString();
      _advanceNoticeController.text =
          (_section('timeOff')['minimumAdvanceNoticeDays'] ?? 7).toString();
    } catch (error) {
      _error = error.toString();
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    final profile = _profile;
    if (!_canEditModules && !_canEditProfile) return;
    if (profile == null) return;

    FocusScope.of(context).unfocus();

    final parsedPtoHours = int.tryParse(_ptoHoursController.text.trim());
    final parsedAdvanceNotice = int.tryParse(_advanceNoticeController.text.trim());

    if (parsedPtoHours == null || parsedPtoHours < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Default PTO hours must be 0 or greater.')),
      );
      return;
    }

    if (parsedAdvanceNotice == null || parsedAdvanceNotice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Advance notice days must be 0 or greater.')),
      );
      return;
    }

    final timeOff = _section('timeOff');
    timeOff['defaultPtoHours'] = parsedPtoHours;
    timeOff['minimumAdvanceNoticeDays'] = parsedAdvanceNotice;
    _settings['timeOff'] = timeOff;

    setState(() {
      _saving = true;
    });

    try {
      final model = CompanySettingsModel(
        companyId: profile.activeCompanyId,
        companyInfo: <String, dynamic>{
          'companyName': _companyNameController.text.trim(),
          'businessEmail': _businessEmailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'timezone': 'America/Chicago',
          'weekStartDay': 'monday',
          'crewTerminology': _crewTerminology,
          'logoUrl': _logoUrlController.text.trim(),
          'industryType': _industryTypeController.text.trim(),
        },
        dashboardFeatures: Map<String, bool>.from(_settings['dashboardFeatures'] as Map),
        timeOff: _section('timeOff'),
        teamTime: _section('teamTime'),
        messaging: _section('messaging'),
        jobs: _section('jobs'),
        payroll: _section('payroll'),
        feedback: _section('feedback'),
        vehicles: _section('vehicles'),
        dataProtection: _section('dataProtection'),
        customSettings: _section('customSettings'),
        updatedAt: DateTime.now(),
      );

      final normalized = _settingsService.normalizeParentChildSettings(model);
      await _settingsService.saveCompanySettings(normalized);

      if (!mounted) return;

      setState(() {
        _settings = <String, dynamic>{
          'dashboardFeatures': Map<String, bool>.from(normalized.dashboardFeatures),
          'timeOff': Map<String, dynamic>.from(normalized.timeOff),
          'teamTime': Map<String, dynamic>.from(normalized.teamTime),
          'messaging': Map<String, dynamic>.from(normalized.messaging),
          'jobs': Map<String, dynamic>.from(normalized.jobs),
          'payroll': Map<String, dynamic>.from(normalized.payroll),
          'feedback': Map<String, dynamic>.from(normalized.feedback),
          'vehicles': Map<String, dynamic>.from(normalized.vehicles),
          'customSettings': Map<String, dynamic>.from(normalized.customSettings),
        };
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Settings Saved'),
            content: const Text(
              'Some changes may require restarting the app before they fully apply.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save settings: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sign Out?'),
          content: const Text('Are you sure you want to sign out of BlueField?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true) return;

    await _authService.logout();

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _setDashboardFeature(String key, bool value) {
    if (!_canEditModules) return;

    setState(() {
      _syncDashboardFeature(key, value);

      if (!value) {
        if (key == 'timeOff') {
          final timeOff = _section('timeOff');
          _turnOffChildToggles(timeOff);
          _settings['timeOff'] = timeOff;
        } else if (key == 'teamTime') {
          final teamTime = _section('teamTime');
          _turnOffChildToggles(teamTime);
          _settings['teamTime'] = teamTime;
        } else if (key == 'messaging') {
          final messaging = _section('messaging');
          _turnOffChildToggles(messaging);
          _settings['messaging'] = messaging;
          _syncDashboardFeature('announcements', false);
        } else if (key == 'announcements') {
          final messaging = _section('messaging');
          messaging['announcements'] = false;
          _settings['messaging'] = messaging;
        } else if (key == 'jobs') {
          final jobs = _section('jobs');
          _turnOffChildToggles(jobs);
          _settings['jobs'] = jobs;
        } else if (key == 'payroll') {
          final payroll = _section('payroll');
          _turnOffChildToggles(payroll);
          _settings['payroll'] = payroll;
        } else if (key == 'feedback') {
          final feedback = _section('feedback');
          _turnOffChildToggles(feedback);
          _settings['feedback'] = feedback;
        } else if (key == 'vehicles') {
          final vehicles = _section('vehicles');
          _turnOffChildToggles(vehicles);
          _settings['vehicles'] = vehicles;
        }
      }
    });
  }

  void _setBool(String section, String key, bool value) {
    if (!_canEditModules) return;

    setState(() {
      final current = _section(section);
      current[key] = value;

      if (key == 'enabled') {
        _syncDashboardFeatureForSection(section, value);

        if (!value) {
          _turnOffChildToggles(current);
        }
      }

      if (section == 'messaging' && key == 'announcements') {
        _syncDashboardFeature('announcements', value);
      }

      _settings[section] = current;
    });
  }

  void _setString(String section, String key, String value) {
    if (!_canEditModules) return;

    setState(() {
      final current = _section(section);
      current[key] = value;
      _settings[section] = current;
    });
  }

  bool _isCapturingZone = false;

  /// Captures the device's current GPS position as the company's
  /// clock-in zone — deliberately NOT an address someone types in.
  /// Whoever is setting this should be standing at the actual spot
  /// (the shed, the house, wherever) when they tap the button.
  Future<void> _captureClockInZone() async {
    if (!_canEditModules || _isCapturingZone) return;

    setState(() => _isCapturingZone = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was denied. Enable it in device settings to set the clock-in zone.');
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are turned off on this device.');
      }

      final position = await Geolocator.getCurrentPosition();

      setState(() {
        final current = _section('teamTime');
        current['clockInZoneLatitude'] = position.latitude;
        current['clockInZoneLongitude'] = position.longitude;
        _settings['teamTime'] = current;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clock-in zone set to your current location. Save settings to apply it.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isCapturingZone = false);
    }
  }

  void _turnOffChildToggles(Map<String, dynamic> section) {
    for (final key in section.keys.toList()) {
      if (section[key] is bool) {
        section[key] = false;
      }
    }

    section['enabled'] = false;
  }

  void _syncDashboardFeature(String key, bool value) {
    final current = Map<String, bool>.from(_settings['dashboardFeatures'] as Map);
    current[key] = value;
    _settings['dashboardFeatures'] = current;
  }

  void _syncDashboardFeatureForSection(String section, bool value) {
    if (section == 'timeOff') {
      _syncDashboardFeature('timeOff', value);
    } else if (section == 'teamTime') {
      _syncDashboardFeature('teamTime', value);
    } else if (section == 'messaging') {
      _syncDashboardFeature('messaging', value);
      if (!value) {
        _syncDashboardFeature('announcements', false);
      }
    } else if (section == 'jobs') {
      _syncDashboardFeature('jobs', value);
    } else if (section == 'payroll') {
      _syncDashboardFeature('payroll', value);
    } else if (section == 'feedback') {
      _syncDashboardFeature('feedback', value);
    } else if (section == 'vehicles') {
      _syncDashboardFeature('vehicles', value);
    }
  }

  void _setRoundingRule(String value) {
    if (!_canEditModules) return;

    setState(() {
      final teamTime = _section('teamTime');
      teamTime['roundingRule'] = value;
      _settings['teamTime'] = teamTime;
    });
  }

  void _setCrewTerminology(String value) {
    if (!_canEditProfile) return;
    setState(() {
      _crewTerminology = value;
    });
  }

  void _addCustomSetting() {
    if (!_canEditModules) return;

    final name = _customNameController.text.trim();
    final value = _customValueController.text.trim();

    if (name.isEmpty) return;

    setState(() {
      final custom = _section('customSettings');
      custom[name] = value;
      _settings['customSettings'] = custom;
      _customNameController.clear();
      _customValueController.clear();
    });
  }

  void _removeCustomSetting(String key) {
    if (!_canEditModules) return;

    setState(() {
      final custom = _section('customSettings');
      custom.remove(key);
      _settings['customSettings'] = custom;
    });
  }

  Map<String, dynamic> _section(String name) {
    final section = _settings[name];

    if (section is Map<String, dynamic>) {
      return Map<String, dynamic>.from(section);
    }

    if (section is Map) {
      return Map<String, dynamic>.from(section);
    }

    return <String, dynamic>{};
  }

  Map<String, bool> _dashboardFeatures() {
    final features = _settings['dashboardFeatures'];

    if (features is Map<String, bool>) {
      return Map<String, bool>.from(features);
    }

    if (features is Map) {
      return features.map((key, value) => MapEntry(key.toString(), value == true));
    }

    return <String, bool>{};
  }

  bool _value(String section, String key) {
    return _section(section)[key] == true;
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
          'Company Settings',
          style: TextStyle(color: AppTheme.darkText, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmSignOut,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.mutedText),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadSettings,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 140),
                  children: [
                    if (!_canEditProfile && !_canEditModules)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: _NoticeBanner(
                          message:
                              'Your role does not have permission to edit company settings. Showing read-only view.',
                        ),
                      ),
                    _SettingsCard(
                      title: 'Company Information',
                      children: [
                        _TextField(
                          label: 'Company Name',
                          controller: _companyNameController,
                          enabled: _canEditProfile,
                        ),
                        _TextField(
                          label: 'Business Email',
                          controller: _businessEmailController,
                          enabled: _canEditProfile,
                        ),
                        _TextField(
                          label: 'Phone',
                          controller: _phoneController,
                          enabled: _canEditProfile,
                        ),
                        _TextField(
                          label: 'Address',
                          controller: _addressController,
                          enabled: _canEditProfile,
                        ),
                        _TextField(
                          label: 'Logo URL',
                          controller: _logoUrlController,
                          enabled: _canEditProfile,
                        ),
                        _TextField(
                          label: 'Industry Type',
                          controller: _industryTypeController,
                          enabled: _canEditProfile,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Crew Terminology',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.darkText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'crew', label: Text('Crew')),
                            ButtonSegment(value: 'team', label: Text('Team')),
                          ],
                          selected: {_crewTerminology},
                          onSelectionChanged: _canEditProfile
                              ? (selection) => _setCrewTerminology(selection.first)
                              : null,
                        ),
                      ],
                    ),
                    _SettingsCard(
                      title: 'Modules',
                      subtitle: 'Disabling a module hides it from every dashboard and blocks direct access.',
                      children: _dashboardFeatures().entries.map((entry) {
                        return _ToggleRow(
                          label: _moduleLabel(entry.key),
                          value: entry.value,
                          enabled: _canEditModules,
                          onChanged: (value) => _setDashboardFeature(entry.key, value),
                        );
                      }).toList(),
                    ),
                    if (_value('dashboardFeatures', 'timeOff') != false)
                      _SettingsCard(
                        title: 'Time Off',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('timeOff', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'PTO',
                            value: _value('timeOff', 'pto'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'pto', v),
                          ),
                          _ToggleRow(
                            label: 'Sick Time',
                            value: _value('timeOff', 'sick'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'sick', v),
                          ),
                          _ToggleRow(
                            label: 'Unpaid Time Off',
                            value: _value('timeOff', 'unpaid'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'unpaid', v),
                          ),
                          _ToggleRow(
                            label: 'Bereavement',
                            value: _value('timeOff', 'bereavement'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'bereavement', v),
                          ),
                          _ToggleRow(
                            label: 'Jury Duty',
                            value: _value('timeOff', 'juryDuty'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'juryDuty', v),
                          ),
                          _ToggleRow(
                            label: 'Manager Approval Required',
                            value: _value('timeOff', 'managerApprovalRequired'),
                            enabled: _canEditModules,
                            onChanged: (v) =>
                                _setBool('timeOff', 'managerApprovalRequired', v),
                          ),
                          _ToggleRow(
                            label: 'Allow Partial Days',
                            value: _value('timeOff', 'allowPartialDays'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('timeOff', 'allowPartialDays', v),
                          ),
                          _TextField(
                            label: 'Default PTO Hours',
                            controller: _ptoHoursController,
                            enabled: _canEditModules,
                            keyboardType: TextInputType.number,
                          ),
                          _TextField(
                            label: 'Minimum Advance Notice (days)',
                            controller: _advanceNoticeController,
                            enabled: _canEditModules,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    if (_value('dashboardFeatures', 'teamTime') != false)
                      _SettingsCard(
                        title: 'Team Time',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('teamTime', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('teamTime', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'Clock In / Out',
                            value: _value('teamTime', 'clockInOut'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('teamTime', 'clockInOut', v),
                          ),
                          _ToggleRow(
                            label: 'Breaks',
                            value: _value('teamTime', 'breaksEnabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('teamTime', 'breaksEnabled', v),
                          ),
                          _ToggleRow(
                            label: 'Correction Requests',
                            value: _value('teamTime', 'correctionRequests'),
                            enabled: _canEditModules,
                            onChanged: (v) =>
                                _setBool('teamTime', 'correctionRequests', v),
                          ),
                          _ToggleRow(
                            label: 'Manager Time Edits',
                            value: _value('teamTime', 'managerEdits'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('teamTime', 'managerEdits', v),
                          ),
                          _ToggleRow(
                            label: 'Employee Self-Edit',
                            value: _value('teamTime', 'employeeSelfEdit'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('teamTime', 'employeeSelfEdit', v),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Clock Rounding',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.darkText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButton<String>(
                            value: (_section('teamTime')['roundingRule'] ?? 'none')
                                .toString(),
                            isExpanded: true,
                            onChanged: _canEditModules
                                ? (value) {
                                    if (value != null) _setRoundingRule(value);
                                  }
                                : null,
                            items: const [
                              DropdownMenuItem(value: 'none', child: Text('No rounding')),
                              DropdownMenuItem(
                                  value: '5 minutes', child: Text('Nearest 5 minutes')),
                              DropdownMenuItem(
                                  value: '10 minutes', child: Text('Nearest 10 minutes')),
                              DropdownMenuItem(
                                  value: '15 minutes', child: Text('Nearest 15 minutes')),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text('Clock-In Zone',
                              style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkText)),
                          const SizedBox(height: 4),
                          Text(
                            (_section('teamTime')['clockInZoneLatitude'] != null &&
                                    _section('teamTime')['clockInZoneLongitude'] != null)
                                ? 'Set — ${(_section('teamTime')['clockInZoneLatitude'] as num).toStringAsFixed(5)}, '
                                    '${(_section('teamTime')['clockInZoneLongitude'] as num).toStringAsFixed(5)}'
                                : 'Not set yet',
                            style: const TextStyle(fontSize: 13, color: AppTheme.mutedText),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: (!_canEditModules || _isCapturingZone) ? null : _captureClockInZone,
                              icon: _isCapturingZone
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.my_location_outlined, size: 18),
                              label: Text(_isCapturingZone ? 'Getting location...' : 'Set Clock-In Zone to My Current Location'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Stand at the actual spot (your shed, office, wherever you\'re based out of) before tapping this.',
                            style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
                          ),
                          const SizedBox(height: 14),
                          Text('Radius: ${_section('teamTime')['geofenceRadiusMeters'] ?? 500} meters',
                              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkText)),
                          Slider(
                            value: ((_section('teamTime')['geofenceRadiusMeters'] as num?)?.toDouble() ?? 500).clamp(50, 10000),
                            min: 50,
                            max: 10000,
                            divisions: 199,
                            label: '${_section('teamTime')['geofenceRadiusMeters'] ?? 500}m',
                            onChanged: !_canEditModules
                                ? null
                                : (value) {
                                    setState(() {
                                      final current = _section('teamTime');
                                      current['geofenceRadiusMeters'] = value.round();
                                      _settings['teamTime'] = current;
                                    });
                                  },
                          ),
                          const SizedBox(height: 10),
                          const Text('Clock-In Mode', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.darkText)),
                          const SizedBox(height: 6),
                          DropdownButton<String>(
                            value: (_section('teamTime')['clockInGeofenceMode'] ?? 'off').toString(),
                            isExpanded: true,
                            onChanged: !_canEditModules
                                ? null
                                : (value) {
                                    if (value != null) _setString('teamTime', 'clockInGeofenceMode', value);
                                  },
                            items: const [
                              DropdownMenuItem(value: 'off', child: Text('Off — no check')),
                              DropdownMenuItem(value: 'strict', child: Text('Strict — blocked outside zone')),
                              DropdownMenuItem(value: 'lenient', child: Text('Lenient — allowed, but confirms + notifies')),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _ToggleRow(
                            label: 'Notify on Clock-Out Outside Zone',
                            value: _value('teamTime', 'clockOutGeofenceEnabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('teamTime', 'clockOutGeofenceEnabled', v),
                          ),
                          const Text(
                            'Clock-out is never blocked, even when this is on — it only notifies managers/owners, '
                            'so a forgotten clock-out stays easy to fix.',
                            style: TextStyle(fontSize: 11, color: AppTheme.mutedText),
                          ),
                        ],
                      ),
                    if (_value('dashboardFeatures', 'messaging') != false)
                      _SettingsCard(
                        title: 'Messaging',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('messaging', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('messaging', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'Direct Messages',
                            value: _value('messaging', 'directMessages'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('messaging', 'directMessages', v),
                          ),
                          _ToggleRow(
                            label: 'Crew Messages',
                            value: _value('messaging', 'crewMessages'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('messaging', 'crewMessages', v),
                          ),
                          _ToggleRow(
                            label: 'Announcements',
                            value: _value('messaging', 'announcements'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('messaging', 'announcements', v),
                          ),
                        ],
                      ),
                    if (_value('dashboardFeatures', 'jobs') != false)
                      _SettingsCard(
                        title: 'Jobs',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('jobs', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('jobs', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'Require Crew Assignment',
                            value: _value('jobs', 'requireCrewAssignment'),
                            enabled: _canEditModules,
                            onChanged: (v) =>
                                _setBool('jobs', 'requireCrewAssignment', v),
                          ),
                          _ToggleRow(
                            label: 'Allow Job Cancellation',
                            value: _value('jobs', 'allowJobCancel'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('jobs', 'allowJobCancel', v),
                          ),
                          _ToggleRow(
                            label: 'Show Job History',
                            value: _value('jobs', 'showJobHistory'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('jobs', 'showJobHistory', v),
                          ),
                          _ToggleRow(
                            label: 'Multiple Destination Directions',
                            value: _value('jobs', 'multipleDestinationDirections'),
                            enabled: _canEditModules,
                            onChanged: (v) =>
                                _setBool('jobs', 'multipleDestinationDirections', v),
                          ),
                          const SizedBox(height: 12),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Employee & Manager Job Visibility', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 4),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'How far ahead anyone without full job access can see upcoming jobs. Owners always see everything.',
                              style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: (_section('jobs')['visibilityWindow'] as String?) ?? 'week',
                            decoration: const InputDecoration(isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'nextJob', child: Text('Next job only')),
                              DropdownMenuItem(value: 'day', child: Text('Whole day')),
                              DropdownMenuItem(value: 'week', child: Text('This week')),
                              DropdownMenuItem(value: 'month', child: Text('This month')),
                            ],
                            onChanged: !_canEditModules
                                ? null
                                : (value) {
                                    if (value != null) _setString('jobs', 'visibilityWindow', value);
                                  },
                          ),
                        ],
                      ),
                    if (_value('dashboardFeatures', 'payroll') != false)
                      _SettingsCard(
                        title: 'Payroll',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('payroll', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('payroll', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'Pay Periods',
                            value: _value('payroll', 'payPeriods'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('payroll', 'payPeriods', v),
                          ),
                          _ToggleRow(
                            label: 'Payroll Summary',
                            value: _value('payroll', 'payrollSummary'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('payroll', 'payrollSummary', v),
                          ),
                          _ToggleRow(
                            label: 'Exports',
                            value: _value('payroll', 'exports'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('payroll', 'exports', v),
                          ),
                        ],
                      ),
                    if (_value('dashboardFeatures', 'feedback') != false)
                      _SettingsCard(
                        title: 'Feedback',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('feedback', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('feedback', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'Bug Reports',
                            value: _value('feedback', 'bugReports'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('feedback', 'bugReports', v),
                          ),
                          _ToggleRow(
                            label: 'Feature Requests',
                            value: _value('feedback', 'featureRequests'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('feedback', 'featureRequests', v),
                          ),
                          _ToggleRow(
                            label: 'Questions',
                            value: _value('feedback', 'questions'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('feedback', 'questions', v),
                          ),
                          _ToggleRow(
                            label: 'Screenshots',
                            value: _value('feedback', 'screenshots'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('feedback', 'screenshots', v),
                          ),
                        ],
                      ),
                    if (_value('dashboardFeatures', 'vehicles') != false)
                      _SettingsCard(
                        title: 'Vehicles',
                        children: [
                          _ToggleRow(
                            label: 'Enabled',
                            value: _value('vehicles', 'enabled'),
                            enabled: _canEditModules,
                            onChanged: (v) => _setBool('vehicles', 'enabled', v),
                          ),
                          _ToggleRow(
                            label: 'Require Vehicle For Jobs',
                            value: _value('vehicles', 'requireVehicleForJobs'),
                            enabled: _canEditModules,
                            onChanged: (v) =>
                                _setBool('vehicles', 'requireVehicleForJobs', v),
                          ),
                        ],
                      ),
                    _SettingsCard(
                      title: 'Deletion Protection',
                      subtitle: 'Require typing an item\'s name to confirm before permanently deleting it (vehicles, equipment).',
                      children: [
                        _ToggleRow(
                          label: 'Require Confirmation for Deletes',
                          value: _value('dataProtection', 'requireConfirmationForDeletes'),
                          enabled: _canEditModules,
                          onChanged: (v) => _setBool('dataProtection', 'requireConfirmationForDeletes', v),
                        ),
                      ],
                    ),
                    _SettingsCard(
                      title: 'Custom Settings',
                      subtitle: 'Company-specific key/value settings not covered above.',
                      children: [
                        ..._section('customSettings').entries.map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.key}: ${entry.value}',
                                        style: const TextStyle(color: AppTheme.darkText),
                                      ),
                                    ),
                                    if (_canEditModules)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () =>
                                            _removeCustomSetting(entry.key),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        if (_canEditModules) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customNameController,
                                  decoration: const InputDecoration(labelText: 'Name'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _customValueController,
                                  decoration: const InputDecoration(labelText: 'Value'),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _addCustomSetting,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_canEditProfile || _canEditModules)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _saving ? null : _saveSettings,
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save Settings'),
                        ),
                      ),
                  ],
                ),
    );
  }

  String _moduleLabel(String key) {
    switch (key) {
      case 'schedule':
        return 'Schedule';
      case 'jobs':
        return 'Jobs';
      case 'timeOff':
        return 'Time Off';
      case 'teamTime':
        return 'Team Time';
      case 'messaging':
        return 'Messaging';
      case 'announcements':
        return 'Announcements';
      case 'crews':
        return _crewTerminology == 'team' ? 'Teams' : 'Crews';
      case 'payroll':
        return 'Payroll';
      case 'feedback':
        return 'Feedback';
      case 'vehicles':
        return 'Vehicles';
      default:
        return key;
    }
  }
}

class _NoticeBanner extends StatelessWidget {
  final String message;

  const _NoticeBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 13, color: AppTheme.mutedText),
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

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: AppTheme.darkText)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;

  const _TextField({
    required this.label,
    required this.controller,
    required this.enabled,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
