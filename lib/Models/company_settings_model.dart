import 'package:cloud_firestore/cloud_firestore.dart';

class CompanySettingsModel {
  static const Map<String, bool> defaultDashboardFeatures = {
    'schedule': true,
    'jobs': true,
    'timeOff': true,
    'teamTime': true,
    'messaging': true,
    'announcements': true,
    'crews': true,
    'payroll': true,
    'feedback': true,
    'vehicles': true,
  };

  static const Map<String, dynamic> defaultTimeOffSettings = {
    'enabled': true,
    'pto': true,
    'unpaid': true,
    'sick': true,
    'bereavement': false,
    'juryDuty': false,
    'managerApprovalRequired': true,
    'allowPartialDays': true,
    'defaultPtoHours': 40,
    'minimumAdvanceNoticeDays': 7,
  };

  static const Map<String, dynamic> defaultTeamTimeSettings = {
    'enabled': true,
    'clockInOut': true,
    'correctionRequests': true,
    'managerEdits': true,
    // Off by default — an owner has to explicitly opt in to letting
    // employees edit their own clock in/out times directly, rather
    // than going through the correction-request approval flow.
    'employeeSelfEdit': false,
    'roundingRule': '15 minutes',
    // Geofencing — checked against ONE fixed point for the whole
    // company (wherever they're based out of — a storage shed, a
    // home office, whatever), not tied to individual job sites. Set
    // by capturing the device's GPS position directly when an owner
    // taps "Set Clock-In Zone," not typed in as an address. Null
    // coordinates mean no zone has been set yet, in which case the
    // geofence check is skipped entirely regardless of mode. Clock-in
    // and clock-out are independently configurable since they have
    // different stakes: clock-in can reasonably require being
    // on-site, but clock-out should never be able to trap someone
    // who genuinely can't get back — it only ever notifies, never
    // blocks.
    // clockInGeofenceMode: 'off' | 'strict' | 'lenient'
    //   off = no check. strict = blocked outside radius, employee
    //   sees why. lenient = allowed outside radius, but employee gets
    //   an "are you sure?" confirmation and managers/owners are
    //   notified.
    'clockInGeofenceMode': 'off',
    // clockOutGeofenceEnabled: false | true — no blocking mode exists
    // for clock-out by design. When true, clocking out far from the
    // zone is always allowed through silently, and managers/owners
    // just get notified — this is deliberately friction-free so a
    // forgotten clock-out stays easy to fix.
    'clockOutGeofenceEnabled': false,
    'geofenceRadiusMeters': 500,
    'clockInZoneLatitude': null,
    'clockInZoneLongitude': null,
    // Whether the Start Break / End Break controls show up on the
    // clock screen at all. On by default; an owner can turn this off
    // company-wide if they don't want breaks tracked through the app.
    'breaksEnabled': true,
  };

  static const Map<String, dynamic> defaultMessagingSettings = {
    'enabled': true,
    'directMessages': true,
    'crewMessages': true,
    'announcements': true,
  };

  static const Map<String, dynamic> defaultJobsSettings = {
    'enabled': true,
    'requireCrewAssignment': false,
    'allowJobCancel': true,
    'showJobHistory': true,
    'multipleDestinationDirections': true,
    // Controls how far ahead employees/managers without jobs.viewAll
    // can see upcoming jobs: 'nextJob' (only the job right after the
    // one they're currently on), 'day', 'week', or 'month'. Owners
    // and anyone else with jobs.viewAll always see everything
    // regardless of this setting — it only narrows the assigned-only
    // view.
    'visibilityWindow': 'week',
  };

  static const Map<String, dynamic> defaultPayrollSettings = {
    'enabled': true,
    'payPeriods': true,
    'payrollSummary': true,
    'exports': true,
    'payPeriodType': 'weekly',
  };

  static const Map<String, dynamic> defaultFeedbackSettings = {
    'enabled': true,
    'bugReports': true,
    'featureRequests': true,
    'questions': true,
    'screenshots': true,
  };

  /// New: vehicles module settings (Section 15 lists Vehicles as a
  /// required toggleable module — it was missing from the original
  /// settings model entirely).
  static const Map<String, dynamic> defaultVehiclesSettings = {
    'enabled': true,
    'requireVehicleForJobs': false,
  };

  /// Safety behaviors, not a feature to show/hide — currently gates
  /// vehicle/equipment hard-deletes behind a type-to-confirm step.
  /// Defaults to on, matching "safe by default" for anything with
  /// this name.
  static const Map<String, dynamic> defaultDataProtectionSettings = {
    'requireConfirmationForDeletes': true,
  };

  final String companyId;
  final Map<String, dynamic> companyInfo;
  final Map<String, bool> dashboardFeatures;
  final Map<String, dynamic> timeOff;
  final Map<String, dynamic> teamTime;
  final Map<String, dynamic> messaging;
  final Map<String, dynamic> jobs;
  final Map<String, dynamic> payroll;
  final Map<String, dynamic> feedback;
  final Map<String, dynamic> vehicles;
  final Map<String, dynamic> dataProtection;
  final Map<String, dynamic> customSettings;
  final DateTime updatedAt;

  const CompanySettingsModel({
    required this.companyId,
    required this.companyInfo,
    required this.dashboardFeatures,
    required this.timeOff,
    required this.teamTime,
    required this.messaging,
    required this.jobs,
    required this.payroll,
    required this.feedback,
    required this.vehicles,
    this.dataProtection = defaultDataProtectionSettings,
    required this.customSettings,
    required this.updatedAt,
  });

  factory CompanySettingsModel.defaults({
    required String companyId,
    String companyName = '',
    String businessEmail = '',
    String phone = '',
    String address = '',
  }) {
    return CompanySettingsModel(
      companyId: companyId.trim(),
      companyInfo: {
        'companyName': companyName.trim(),
        'businessEmail': businessEmail.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'timezone': 'America/Chicago',
        'weekStartDay': 'monday',
        // New: display terminology + basic branding (Section 15).
        'crewTerminology': 'crew', // 'crew' or 'team'
        'logoUrl': '',
        'industryType': '',
      },
      dashboardFeatures: Map<String, bool>.from(
        defaultDashboardFeatures,
      ),
      timeOff: Map<String, dynamic>.from(
        defaultTimeOffSettings,
      ),
      teamTime: Map<String, dynamic>.from(
        defaultTeamTimeSettings,
      ),
      messaging: Map<String, dynamic>.from(
        defaultMessagingSettings,
      ),
      jobs: Map<String, dynamic>.from(
        defaultJobsSettings,
      ),
      payroll: Map<String, dynamic>.from(
        defaultPayrollSettings,
      ),
      feedback: Map<String, dynamic>.from(
        defaultFeedbackSettings,
      ),
      vehicles: Map<String, dynamic>.from(
        defaultVehiclesSettings,
      ),
      dataProtection: Map<String, dynamic>.from(
        defaultDataProtectionSettings,
      ),
      customSettings: <String, dynamic>{},
      updatedAt: DateTime(2026),
    );
  }

  factory CompanySettingsModel.fromCompanyMap({
    required String companyId,
    required Map<String, dynamic> companyMap,
  }) {
    final settings = _asMap(companyMap['settings']);
    final storedCompanyInfo = _asMap(settings['companyInfo']);

    final companyInfo = <String, dynamic>{
      'companyName': _firstNonEmptyString([
        storedCompanyInfo['companyName'],
        // Migration-safe: company_model.dart writes 'companyName' at the
        // top level; older docs (or company_settings_service before this
        // fix) may have written 'name' instead.
        companyMap['companyName'],
        companyMap['name'],
      ]),
      'businessEmail': _firstNonEmptyString([
        storedCompanyInfo['businessEmail'],
        companyMap['businessEmail'],
        companyMap['email'],
      ]),
      'phone': _firstNonEmptyString([
        storedCompanyInfo['phone'],
        companyMap['phone'],
      ]),
      'address': _firstNonEmptyString([
        storedCompanyInfo['address'],
        companyMap['address'],
      ]),
      'timezone': _firstNonEmptyString(
        [
          storedCompanyInfo['timezone'],
          companyMap['timezone'],
        ],
        fallback: 'America/Chicago',
      ),
      'weekStartDay': _normalizedWeekStartDay(
        _firstNonEmptyString(
          [
            storedCompanyInfo['weekStartDay'],
            companyMap['weekStartDay'],
          ],
          fallback: 'monday',
        ),
      ),
      'crewTerminology': _normalizedCrewTerminology(
        storedCompanyInfo['crewTerminology'],
      ),
      'logoUrl': storedCompanyInfo['logoUrl']?.toString().trim() ?? '',
      'industryType': storedCompanyInfo['industryType']?.toString().trim() ?? '',
    };

    final dashboardFeatures = _boolMap(
      settings['dashboardFeatures'],
      defaultDashboardFeatures,
    );

    final timeOff = _normalizedTimeOffSettings(
      _mergeMap(
        settings['timeOff'],
        defaultTimeOffSettings,
      ),
    );

    final teamTime = _normalizedTeamTimeSettings(
      _mergeMap(
        settings['teamTime'],
        defaultTeamTimeSettings,
      ),
    );

    final messaging = _normalizedMessagingSettings(
      _mergeMap(
        settings['messaging'],
        defaultMessagingSettings,
      ),
    );

    final jobs = _normalizedJobsSettings(
      _mergeMap(
        settings['jobs'],
        defaultJobsSettings,
      ),
    );

    final payroll = _normalizedPayrollSettings(
      _mergeMap(
        settings['payroll'],
        defaultPayrollSettings,
      ),
    );

    final feedback = _normalizedFeedbackSettings(
      _mergeMap(
        settings['feedback'],
        defaultFeedbackSettings,
      ),
    );

    final vehicles = _normalizedVehiclesSettings(
      _mergeMap(
        settings['vehicles'],
        defaultVehiclesSettings,
      ),
    );

    final dataProtection = _normalizedDataProtectionSettings(
      _mergeMap(
        settings['dataProtection'],
        defaultDataProtectionSettings,
      ),
    );

    return CompanySettingsModel(
      companyId: companyId.trim(),
      companyInfo: companyInfo,
      dashboardFeatures: dashboardFeatures,
      timeOff: timeOff,
      teamTime: teamTime,
      messaging: messaging,
      jobs: jobs,
      payroll: payroll,
      feedback: feedback,
      vehicles: vehicles,
      dataProtection: dataProtection,
      customSettings: _asMap(settings['customSettings']),
      updatedAt: _dateFrom(settings['updatedAt']) ??
          _dateFrom(companyMap['updatedAt']) ??
          DateTime.now(),
    );
  }

  factory CompanySettingsModel.fromMap({
    required String companyId,
    required Map<String, dynamic> data,
  }) {
    return CompanySettingsModel.fromCompanyMap(
      companyId: companyId,
      companyMap: data,
    );
  }

  Map<String, dynamic> toCompanyUpdateMap() {
    final sanitizedCompanyInfo = <String, dynamic>{
      'companyName': companyName,
      'businessEmail': businessEmail,
      'phone': phone,
      'address': address,
      'timezone': timezone,
      'weekStartDay': weekStartDay,
      'crewTerminology': crewTerminology,
      'logoUrl': logoUrl,
      'industryType': industryType,
    };

    return {
      // Fixed: was 'name', which collided with company_model.dart's
      // 'companyName' field on the same document. Both now agree.
      'companyName': companyName,
      'businessEmail': businessEmail,
      'phone': phone,
      'address': address,
      'timezone': timezone,
      'weekStartDay': weekStartDay,
      'settings': {
        'companyInfo': sanitizedCompanyInfo,
        'dashboardFeatures': Map<String, bool>.from(
          dashboardFeatures,
        ),
        'timeOff': Map<String, dynamic>.from(timeOff),
        'teamTime': Map<String, dynamic>.from(teamTime),
        'messaging': Map<String, dynamic>.from(messaging),
        'jobs': Map<String, dynamic>.from(jobs),
        'payroll': Map<String, dynamic>.from(payroll),
        'feedback': Map<String, dynamic>.from(feedback),
        'vehicles': Map<String, dynamic>.from(vehicles),
        'dataProtection': Map<String, dynamic>.from(dataProtection),
        'customSettings': Map<String, dynamic>.from(
          customSettings,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMap() {
    return toCompanyUpdateMap();
  }

  String get companyName {
    return companyInfo['companyName']?.toString().trim() ?? '';
  }

  String get businessEmail {
    return companyInfo['businessEmail']?.toString().trim() ?? '';
  }

  String get phone {
    return companyInfo['phone']?.toString().trim() ?? '';
  }

  String get address {
    return companyInfo['address']?.toString().trim() ?? '';
  }

  String get timezone {
    final value = companyInfo['timezone']?.toString().trim();

    if (value == null || value.isEmpty) {
      return 'America/Chicago';
    }

    return value;
  }

  String get weekStartDay {
    return _normalizedWeekStartDay(
      companyInfo['weekStartDay']?.toString() ?? 'monday',
    );
  }

  /// 'crew' or 'team' — the label to display throughout the app instead
  /// of hardcoding "Crew" everywhere (Section 15: "Optional terminology:
  /// crew/team").
  String get crewTerminology {
    return _normalizedCrewTerminology(companyInfo['crewTerminology']);
  }

  /// How far ahead employees/managers without jobs.viewAll can see
  /// upcoming jobs. See defaultJobsSettings for the meaning of each value.
  String get jobVisibilityWindow => _normalizedVisibilityWindow(jobs['visibilityWindow']);

  /// Whether hard-deletes (currently vehicles/equipment) require
  /// typing the item's name to confirm before proceeding.
  bool get requireConfirmationForDeletes => dataProtection['requireConfirmationForDeletes'] != false;

  /// 'off' | 'strict' | 'lenient' — see defaultTeamTimeSettings for
  /// what each means.
  String get clockInGeofenceMode => _normalizedGeofenceMode(teamTime['clockInGeofenceMode']);

  bool get clockOutGeofenceEnabled => teamTime['clockOutGeofenceEnabled'] == true;

  int get geofenceRadiusMeters => _normalizedGeofenceRadius(teamTime['geofenceRadiusMeters']);

  double? get clockInZoneLatitude => (teamTime['clockInZoneLatitude'] as num?)?.toDouble();
  double? get clockInZoneLongitude => (teamTime['clockInZoneLongitude'] as num?)?.toDouble();

  /// Whether an owner has actually set the zone yet — geofence checks
  /// should be skipped entirely if this is false, regardless of mode.
  bool get hasClockInZone => clockInZoneLatitude != null && clockInZoneLongitude != null;

  String get logoUrl => companyInfo['logoUrl']?.toString().trim() ?? '';
  String get industryType => companyInfo['industryType']?.toString().trim() ?? '';

  String get payPeriodType {
    final value = payroll['payPeriodType']?.toString().trim().toLowerCase();

    switch (value) {
      case 'weekly':
      case 'biweekly':
      case 'semimonthly':
      case 'monthly':
        return value!;

      default:
        return 'weekly';
    }
  }

  bool get requireGpsForClockIn {
    return false;
  }

  bool get allowEmployeeMessaging {
    return dashboardFeatures['messaging'] == true &&
        messaging['enabled'] == true;
  }

  bool get allowTimeOffRequests {
    return dashboardFeatures['timeOff'] == true &&
        timeOff['enabled'] == true;
  }

  bool get allowMultipleDestinationDirections {
    return dashboardFeatures['jobs'] == true &&
        jobs['enabled'] == true &&
        jobs['multipleDestinationDirections'] != false;
  }

  bool get timeOffEnabled {
    return dashboardFeatures['timeOff'] == true &&
        timeOff['enabled'] == true;
  }

  bool get teamTimeEnabled {
    return dashboardFeatures['teamTime'] == true &&
        teamTime['enabled'] == true;
  }

  bool get clockInOutEnabled {
    return teamTimeEnabled && teamTime['clockInOut'] == true;
  }

  bool get correctionRequestsEnabled {
    return teamTimeEnabled &&
        teamTime['correctionRequests'] == true;
  }

  bool get managerTimeEditsEnabled {
    return teamTimeEnabled && teamTime['managerEdits'] == true;
  }

  /// Whether an employee can edit their OWN clock in/out times
  /// directly, without needing a manager to approve a correction
  /// request first — a more trusting mode an owner opts into
  /// explicitly, distinct from (and off by default relative to) the
  /// existing correction-request approval flow.
  bool get employeeSelfEditEnabled {
    return teamTimeEnabled && teamTime['employeeSelfEdit'] == true;
  }

  /// Whether Start Break / End Break should show up on the clock
  /// screen at all. Defaults to true (matches defaultTeamTimeSettings)
  /// so this doesn't need a migration for existing companies whose
  /// stored settings doc predates this field.
  bool get breaksEnabled {
    return teamTimeEnabled && teamTime['breaksEnabled'] != false;
  }

  bool get messagingEnabled {
    return dashboardFeatures['messaging'] == true &&
        messaging['enabled'] == true;
  }

  bool get directMessagesEnabled {
    return messagingEnabled &&
        messaging['directMessages'] == true;
  }

  bool get crewMessagesEnabled {
    return messagingEnabled &&
        messaging['crewMessages'] == true;
  }

  bool get announcementsEnabled {
    return messagingEnabled &&
        dashboardFeatures['announcements'] == true &&
        messaging['announcements'] == true;
  }

  bool get jobsEnabled {
    return dashboardFeatures['jobs'] == true &&
        jobs['enabled'] == true;
  }

  bool get payrollEnabled {
    return dashboardFeatures['payroll'] == true &&
        payroll['enabled'] == true;
  }

  bool get feedbackEnabled {
    return dashboardFeatures['feedback'] == true &&
        feedback['enabled'] == true;
  }

  bool get vehiclesEnabled {
    return dashboardFeatures['vehicles'] == true &&
        vehicles['enabled'] == true;
  }

  CompanySettingsModel copyWith({
    String? companyId,
    Map<String, dynamic>? companyInfo,
    Map<String, bool>? dashboardFeatures,
    Map<String, dynamic>? timeOff,
    Map<String, dynamic>? teamTime,
    Map<String, dynamic>? messaging,
    Map<String, dynamic>? jobs,
    Map<String, dynamic>? payroll,
    Map<String, dynamic>? feedback,
    Map<String, dynamic>? vehicles,
    Map<String, dynamic>? dataProtection,
    Map<String, dynamic>? customSettings,
    DateTime? updatedAt,
  }) {
    return CompanySettingsModel(
      companyId: companyId ?? this.companyId,
      companyInfo: companyInfo != null
          ? Map<String, dynamic>.from(companyInfo)
          : Map<String, dynamic>.from(this.companyInfo),
      dashboardFeatures: dashboardFeatures != null
          ? Map<String, bool>.from(dashboardFeatures)
          : Map<String, bool>.from(this.dashboardFeatures),
      timeOff: timeOff != null
          ? Map<String, dynamic>.from(timeOff)
          : Map<String, dynamic>.from(this.timeOff),
      teamTime: teamTime != null
          ? Map<String, dynamic>.from(teamTime)
          : Map<String, dynamic>.from(this.teamTime),
      messaging: messaging != null
          ? Map<String, dynamic>.from(messaging)
          : Map<String, dynamic>.from(this.messaging),
      jobs: jobs != null
          ? Map<String, dynamic>.from(jobs)
          : Map<String, dynamic>.from(this.jobs),
      payroll: payroll != null
          ? Map<String, dynamic>.from(payroll)
          : Map<String, dynamic>.from(this.payroll),
      feedback: feedback != null
          ? Map<String, dynamic>.from(feedback)
          : Map<String, dynamic>.from(this.feedback),
      vehicles: vehicles != null
          ? Map<String, dynamic>.from(vehicles)
          : Map<String, dynamic>.from(this.vehicles),
      dataProtection: dataProtection != null
          ? Map<String, dynamic>.from(dataProtection)
          : Map<String, dynamic>.from(this.dataProtection),
      customSettings: customSettings != null
          ? Map<String, dynamic>.from(customSettings)
          : Map<String, dynamic>.from(this.customSettings),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Map<String, dynamic> _normalizedTimeOffSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultTimeOffSettings['enabled'] as bool,
      ),
      'pto': _boolValue(
        source['pto'],
        defaultTimeOffSettings['pto'] as bool,
      ),
      'unpaid': _boolValue(
        source['unpaid'],
        defaultTimeOffSettings['unpaid'] as bool,
      ),
      'sick': _boolValue(
        source['sick'],
        defaultTimeOffSettings['sick'] as bool,
      ),
      'bereavement': _boolValue(
        source['bereavement'],
        defaultTimeOffSettings['bereavement'] as bool,
      ),
      'juryDuty': _boolValue(
        source['juryDuty'],
        defaultTimeOffSettings['juryDuty'] as bool,
      ),
      'managerApprovalRequired': _boolValue(
        source['managerApprovalRequired'],
        defaultTimeOffSettings['managerApprovalRequired'] as bool,
      ),
      'allowPartialDays': _boolValue(
        source['allowPartialDays'],
        defaultTimeOffSettings['allowPartialDays'] as bool,
      ),
      'defaultPtoHours': _nonNegativeNumber(
        source['defaultPtoHours'],
        defaultTimeOffSettings['defaultPtoHours'] as num,
      ),
      'minimumAdvanceNoticeDays': _nonNegativeInteger(
        source['minimumAdvanceNoticeDays'],
        defaultTimeOffSettings['minimumAdvanceNoticeDays'] as int,
      ),
    };
  }

  static Map<String, dynamic> _normalizedTeamTimeSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultTeamTimeSettings['enabled'] as bool,
      ),
      'clockInOut': _boolValue(
        source['clockInOut'],
        defaultTeamTimeSettings['clockInOut'] as bool,
      ),
      'correctionRequests': _boolValue(
        source['correctionRequests'],
        defaultTeamTimeSettings['correctionRequests'] as bool,
      ),
      'managerEdits': _boolValue(
        source['managerEdits'],
        defaultTeamTimeSettings['managerEdits'] as bool,
      ),
      'employeeSelfEdit': _boolValue(
        source['employeeSelfEdit'],
        defaultTeamTimeSettings['employeeSelfEdit'] as bool,
      ),
      'roundingRule': _normalizedRoundingRule(
        source['roundingRule'],
      ),
      'clockInGeofenceMode': _normalizedGeofenceMode(source['clockInGeofenceMode']),
      'clockOutGeofenceEnabled': _boolValue(
        source['clockOutGeofenceEnabled'],
        defaultTeamTimeSettings['clockOutGeofenceEnabled'] as bool,
      ),
      'geofenceRadiusMeters': _normalizedGeofenceRadius(source['geofenceRadiusMeters']),
      'clockInZoneLatitude': (source['clockInZoneLatitude'] as num?)?.toDouble(),
      'clockInZoneLongitude': (source['clockInZoneLongitude'] as num?)?.toDouble(),
      'breaksEnabled': _boolValue(
        source['breaksEnabled'],
        defaultTeamTimeSettings['breaksEnabled'] as bool,
      ),
    };
  }

  static String _normalizedGeofenceMode(dynamic value) {
    const validModes = {'off', 'strict', 'lenient'};
    final stringValue = value?.toString();
    if (stringValue != null && validModes.contains(stringValue)) {
      return stringValue;
    }
    return defaultTeamTimeSettings['clockInGeofenceMode'] as String;
  }

  static int _normalizedGeofenceRadius(dynamic value) {
    final intValue = (value as num?)?.toInt();
    if (intValue == null || intValue < 50 || intValue > 10000) {
      return defaultTeamTimeSettings['geofenceRadiusMeters'] as int;
    }
    return intValue;
  }

  static Map<String, dynamic> _normalizedMessagingSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultMessagingSettings['enabled'] as bool,
      ),
      'directMessages': _boolValue(
        source['directMessages'],
        defaultMessagingSettings['directMessages'] as bool,
      ),
      'crewMessages': _boolValue(
        source['crewMessages'],
        defaultMessagingSettings['crewMessages'] as bool,
      ),
      'announcements': _boolValue(
        source['announcements'],
        defaultMessagingSettings['announcements'] as bool,
      ),
    };
  }

  static Map<String, dynamic> _normalizedJobsSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultJobsSettings['enabled'] as bool,
      ),
      'requireCrewAssignment': _boolValue(
        source['requireCrewAssignment'],
        defaultJobsSettings['requireCrewAssignment'] as bool,
      ),
      'allowJobCancel': _boolValue(
        source['allowJobCancel'],
        defaultJobsSettings['allowJobCancel'] as bool,
      ),
      'showJobHistory': _boolValue(
        source['showJobHistory'],
        defaultJobsSettings['showJobHistory'] as bool,
      ),
      'multipleDestinationDirections': _boolValue(
        source['multipleDestinationDirections'],
        defaultJobsSettings['multipleDestinationDirections'] as bool,
      ),
      'visibilityWindow': _normalizedVisibilityWindow(source['visibilityWindow']),
    };
  }

  static String _normalizedVisibilityWindow(dynamic value) {
    const validValues = {'nextJob', 'day', 'week', 'month'};
    final stringValue = value?.toString();
    if (stringValue != null && validValues.contains(stringValue)) {
      return stringValue;
    }
    return defaultJobsSettings['visibilityWindow'] as String;
  }

  static Map<String, dynamic> _normalizedPayrollSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultPayrollSettings['enabled'] as bool,
      ),
      'payPeriods': _boolValue(
        source['payPeriods'],
        defaultPayrollSettings['payPeriods'] as bool,
      ),
      'payrollSummary': _boolValue(
        source['payrollSummary'],
        defaultPayrollSettings['payrollSummary'] as bool,
      ),
      'exports': _boolValue(
        source['exports'],
        defaultPayrollSettings['exports'] as bool,
      ),
      'payPeriodType': _normalizedPayPeriodType(
        source['payPeriodType'],
      ),
    };
  }

  static Map<String, dynamic> _normalizedFeedbackSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultFeedbackSettings['enabled'] as bool,
      ),
      'bugReports': _boolValue(
        source['bugReports'],
        defaultFeedbackSettings['bugReports'] as bool,
      ),
      'featureRequests': _boolValue(
        source['featureRequests'],
        defaultFeedbackSettings['featureRequests'] as bool,
      ),
      'questions': _boolValue(
        source['questions'],
        defaultFeedbackSettings['questions'] as bool,
      ),
      'screenshots': _boolValue(
        source['screenshots'],
        defaultFeedbackSettings['screenshots'] as bool,
      ),
    };
  }

  static Map<String, dynamic> _normalizedVehiclesSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'enabled': _boolValue(
        source['enabled'],
        defaultVehiclesSettings['enabled'] as bool,
      ),
      'requireVehicleForJobs': _boolValue(
        source['requireVehicleForJobs'],
        defaultVehiclesSettings['requireVehicleForJobs'] as bool,
      ),
    };
  }

  static Map<String, dynamic> _normalizedDataProtectionSettings(
    Map<String, dynamic> source,
  ) {
    return {
      'requireConfirmationForDeletes': _boolValue(
        source['requireConfirmationForDeletes'],
        defaultDataProtectionSettings['requireConfirmationForDeletes'] as bool,
      ),
    };
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return value.map<String, dynamic>(
        (key, dynamic mapValue) {
          return MapEntry(
            key.toString(),
            mapValue,
          );
        },
      );
    }

    return <String, dynamic>{};
  }

  static Map<String, dynamic> _mergeMap(
    dynamic value,
    Map<String, dynamic> defaults,
  ) {
    return <String, dynamic>{
      ...defaults,
      ..._asMap(value),
    };
  }

  static Map<String, bool> _boolMap(
    dynamic value,
    Map<String, bool> defaults,
  ) {
    final source = _asMap(value);

    return defaults.map((key, defaultValue) {
      return MapEntry(
        key,
        _boolValue(source[key], defaultValue),
      );
    });
  }

  static bool _boolValue(
    dynamic value,
    bool fallback,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      if (normalized == 'true' ||
          normalized == 'yes' ||
          normalized == '1' ||
          normalized == 'enabled') {
        return true;
      }

      if (normalized == 'false' ||
          normalized == 'no' ||
          normalized == '0' ||
          normalized == 'disabled') {
        return false;
      }
    }

    return fallback;
  }

  static num _nonNegativeNumber(
    dynamic value,
    num fallback,
  ) {
    num? parsedValue;

    if (value is num) {
      parsedValue = value;
    } else if (value is String) {
      parsedValue = num.tryParse(value.trim());
    }

    if (parsedValue == null || parsedValue < 0) {
      return fallback;
    }

    return parsedValue;
  }

  static int _nonNegativeInteger(
    dynamic value,
    int fallback,
  ) {
    int? parsedValue;

    if (value is int) {
      parsedValue = value;
    } else if (value is num) {
      parsedValue = value.round();
    } else if (value is String) {
      parsedValue = int.tryParse(value.trim());
    }

    if (parsedValue == null || parsedValue < 0) {
      return fallback;
    }

    return parsedValue;
  }

  static String _normalizedRoundingRule(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();

    switch (normalized) {
      case '5 minutes':
        return '5 minutes';

      case '10 minutes':
        return '10 minutes';

      case '15 minutes':
        return '15 minutes';

      case 'none':
      default:
        return 'none';
    }
  }

  static String _normalizedPayPeriodType(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();

    switch (normalized) {
      case 'weekly':
      case 'biweekly':
      case 'semimonthly':
      case 'monthly':
        return normalized!;

      default:
        return 'weekly';
    }
  }

  static String _normalizedWeekStartDay(String value) {
    final normalized = value.trim().toLowerCase();

    switch (normalized) {
      case 'sunday':
      case 'monday':
      case 'tuesday':
      case 'wednesday':
      case 'thursday':
      case 'friday':
      case 'saturday':
        return normalized;

      default:
        return 'monday';
    }
  }

  static String _normalizedCrewTerminology(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'team' ? 'team' : 'crew';
  }

  static String _firstNonEmptyString(
    List<dynamic> values, {
    String fallback = '',
  }) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        return text;
      }
    }

    return fallback;
  }

  static DateTime? _dateFrom(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } catch (_) {
        return null;
      }
    }

    if (value is String) {
      return DateTime.tryParse(value.trim());
    }

    return null;
  }
}
