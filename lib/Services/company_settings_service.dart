import 'package:cloud_firestore/cloud_firestore.dart';

import '../Models/company_settings_model.dart';

class CompanySettingsService {
  final FirebaseFirestore _firestore;

  CompanySettingsService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _companyRef(String companyId) {
    return _firestore.collection('companies').doc(companyId);
  }

  Future<CompanySettingsModel> getCompanySettings(String companyId) async {
    final normalizedCompanyId = companyId.trim();

    if (normalizedCompanyId.isEmpty) {
      throw ArgumentError('A company ID is required to load company settings.');
    }

    final companyDoc = await _companyRef(normalizedCompanyId).get();
    final companyData = companyDoc.data();

    if (companyData == null) {
      return CompanySettingsModel.defaults(
        companyId: normalizedCompanyId,
      );
    }

    return CompanySettingsModel.fromCompanyMap(
      companyId: normalizedCompanyId,
      companyMap: companyData,
    );
  }

  Stream<CompanySettingsModel> watchCompanySettings(String companyId) {
    final normalizedCompanyId = companyId.trim();

    if (normalizedCompanyId.isEmpty) {
      return Stream<CompanySettingsModel>.error(
        ArgumentError(
          'A company ID is required to watch company settings.',
        ),
      );
    }

    return _companyRef(normalizedCompanyId).snapshots().map((companyDoc) {
      final companyData = companyDoc.data();

      if (companyData == null) {
        return CompanySettingsModel.defaults(
          companyId: normalizedCompanyId,
        );
      }

      return CompanySettingsModel.fromCompanyMap(
        companyId: normalizedCompanyId,
        companyMap: companyData,
      );
    });
  }

  Future<void> saveCompanySettings(
    CompanySettingsModel settings,
  ) async {
    final normalizedCompanyId = settings.companyId.trim();

    if (normalizedCompanyId.isEmpty) {
      throw ArgumentError('A company ID is required to save settings.');
    }

    final normalizedSettings = normalizeParentChildSettings(settings);

    await _companyRef(normalizedCompanyId).set(
      normalizedSettings.toCompanyUpdateMap(),
      SetOptions(merge: true),
    );
  }

  CompanySettingsModel normalizeParentChildSettings(
    CompanySettingsModel settings,
  ) {
    final dashboardFeatures = Map<String, bool>.from(
      settings.dashboardFeatures,
    );

    final timeOff = Map<String, dynamic>.from(settings.timeOff);
    final teamTime = Map<String, dynamic>.from(settings.teamTime);
    final messaging = Map<String, dynamic>.from(settings.messaging);
    final jobs = Map<String, dynamic>.from(settings.jobs);
    final payroll = Map<String, dynamic>.from(settings.payroll);
    final feedback = Map<String, dynamic>.from(settings.feedback);
    final vehicles = Map<String, dynamic>.from(settings.vehicles);

    if (dashboardFeatures['timeOff'] == false ||
        timeOff['enabled'] != true) {
      dashboardFeatures['timeOff'] = false;
      timeOff['enabled'] = false;
      timeOff['pto'] = false;
      timeOff['unpaid'] = false;
      timeOff['sick'] = false;
      timeOff['bereavement'] = false;
      timeOff['juryDuty'] = false;
      timeOff['managerApprovalRequired'] = false;
      timeOff['allowPartialDays'] = false;
    }

    if (dashboardFeatures['teamTime'] == false ||
        teamTime['enabled'] != true) {
      dashboardFeatures['teamTime'] = false;
      teamTime['enabled'] = false;
      teamTime['clockInOut'] = false;
      teamTime['correctionRequests'] = false;
      teamTime['managerEdits'] = false;
    }

    if (dashboardFeatures['messaging'] == false ||
        messaging['enabled'] != true) {
      dashboardFeatures['messaging'] = false;
      messaging['enabled'] = false;
      messaging['directMessages'] = false;
      messaging['crewMessages'] = false;
      messaging['announcements'] = false;
      dashboardFeatures['announcements'] = false;
    }

    if (dashboardFeatures['announcements'] == false ||
        messaging['announcements'] != true ||
        messaging['enabled'] != true) {
      dashboardFeatures['announcements'] = false;
      messaging['announcements'] = false;
    }

    if (dashboardFeatures['jobs'] == false || jobs['enabled'] != true) {
      dashboardFeatures['jobs'] = false;
      jobs['enabled'] = false;
      jobs['requireCrewAssignment'] = false;
      jobs['allowJobCancel'] = false;
      jobs['showJobHistory'] = false;
      jobs['multipleDestinationDirections'] = false;
    }

    if (dashboardFeatures['payroll'] == false ||
        payroll['enabled'] != true) {
      dashboardFeatures['payroll'] = false;
      payroll['enabled'] = false;
      payroll['payPeriods'] = false;
      payroll['payrollSummary'] = false;
      payroll['exports'] = false;
    }

    if (dashboardFeatures['feedback'] == false ||
        feedback['enabled'] != true) {
      dashboardFeatures['feedback'] = false;
      feedback['enabled'] = false;
      feedback['bugReports'] = false;
      feedback['featureRequests'] = false;
      feedback['questions'] = false;
      feedback['screenshots'] = false;
    }

    if (dashboardFeatures['vehicles'] == false ||
        vehicles['enabled'] != true) {
      dashboardFeatures['vehicles'] = false;
      vehicles['enabled'] = false;
      vehicles['requireVehicleForJobs'] = false;
    }

    return settings.copyWith(
      dashboardFeatures: dashboardFeatures,
      timeOff: timeOff,
      teamTime: teamTime,
      messaging: messaging,
      jobs: jobs,
      payroll: payroll,
      feedback: feedback,
      vehicles: vehicles,
      updatedAt: DateTime.now(),
    );
  }

  bool isFeatureEnabled(
    CompanySettingsModel settings,
    String featureKey,
  ) {
    if (!_dashboardToggleEnabled(settings, featureKey)) {
      return false;
    }

    switch (featureKey) {
      case 'timeOff':
        return isTimeOffEnabled(settings);

      case 'teamTime':
        return isTeamTimeEnabled(settings);

      case 'messaging':
        return isMessagingEnabled(settings);

      case 'announcements':
        return areAnnouncementsEnabled(settings);

      case 'jobs':
        return areJobsEnabled(settings);

      case 'payroll':
        return isPayrollEnabled(settings);

      case 'feedback':
        return isFeedbackEnabled(settings);

      case 'vehicles':
        return isVehiclesEnabled(settings);

      case 'schedule':
        return isScheduleEnabled(settings);

      case 'crews':
        return areCrewsEnabled(settings);

      default:
        return false;
    }
  }

  bool isTimeOffEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'timeOff') &&
        _boolValue(settings.timeOff, 'enabled');
  }

  bool isTimeOffTypeEnabled(
    CompanySettingsModel settings,
    String leaveType,
  ) {
    if (!isTimeOffEnabled(settings)) {
      return false;
    }

    switch (_normalizeKey(leaveType)) {
      case 'pto':
      case 'paidtimeoff':
        return _boolValue(settings.timeOff, 'pto');

      case 'sick':
      case 'sicktime':
        return _boolValue(settings.timeOff, 'sick');

      case 'unpaid':
      case 'unpaidtimeoff':
        return _boolValue(settings.timeOff, 'unpaid');

      case 'bereavement':
        return _boolValue(settings.timeOff, 'bereavement');

      case 'juryduty':
        return _boolValue(settings.timeOff, 'juryDuty');

      default:
        return false;
    }
  }

  bool isTimeOffManagerApprovalRequired(
    CompanySettingsModel settings,
  ) {
    return isTimeOffEnabled(settings) &&
        _boolValue(
          settings.timeOff,
          'managerApprovalRequired',
        );
  }

  bool arePartialTimeOffDaysAllowed(
    CompanySettingsModel settings,
  ) {
    return isTimeOffEnabled(settings) &&
        _boolValue(
          settings.timeOff,
          'allowPartialDays',
        );
  }

  bool isTeamTimeEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'teamTime') &&
        _boolValue(settings.teamTime, 'enabled');
  }

  bool isClockInOutEnabled(CompanySettingsModel settings) {
    return isTeamTimeEnabled(settings) &&
        _boolValue(settings.teamTime, 'clockInOut');
  }

  bool areBreaksEnabled(CompanySettingsModel settings) {
    return isClockInOutEnabled(settings) && settings.breaksEnabled;
  }

  bool areCorrectionRequestsEnabled(
    CompanySettingsModel settings,
  ) {
    return isTeamTimeEnabled(settings) &&
        _boolValue(
          settings.teamTime,
          'correctionRequests',
        );
  }

  bool areManagerTimeEditsEnabled(
    CompanySettingsModel settings,
  ) {
    return isTeamTimeEnabled(settings) &&
        _boolValue(settings.teamTime, 'managerEdits');
  }

  String teamTimeRoundingRule(
    CompanySettingsModel settings,
  ) {
    if (!isTeamTimeEnabled(settings)) {
      return 'none';
    }

    final value = settings.teamTime['roundingRule']
        ?.toString()
        .trim()
        .toLowerCase();

    switch (value) {
      case '5 minutes':
      case '10 minutes':
      case '15 minutes':
        return value!;

      case 'none':
      default:
        return 'none';
    }
  }

  bool isMessagingEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'messaging') &&
        _boolValue(settings.messaging, 'enabled');
  }

  bool areDirectMessagesEnabled(
    CompanySettingsModel settings,
  ) {
    return isMessagingEnabled(settings) &&
        _boolValue(settings.messaging, 'directMessages');
  }

  bool areCrewMessagesEnabled(
    CompanySettingsModel settings,
  ) {
    return isMessagingEnabled(settings) &&
        _boolValue(settings.messaging, 'crewMessages');
  }

  bool areAnnouncementsEnabled(
    CompanySettingsModel settings,
  ) {
    return isMessagingEnabled(settings) &&
        _dashboardToggleEnabled(settings, 'announcements') &&
        _boolValue(settings.messaging, 'announcements');
  }

  bool areJobsEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'jobs') &&
        _boolValue(settings.jobs, 'enabled');
  }

  bool isCrewAssignmentRequired(
    CompanySettingsModel settings,
  ) {
    return areJobsEnabled(settings) &&
        _boolValue(settings.jobs, 'requireCrewAssignment');
  }

  bool isJobCancellationAllowed(
    CompanySettingsModel settings,
  ) {
    return areJobsEnabled(settings) &&
        _boolValue(settings.jobs, 'allowJobCancel');
  }

  bool isJobHistoryEnabled(
    CompanySettingsModel settings,
  ) {
    return areJobsEnabled(settings) &&
        _boolValue(settings.jobs, 'showJobHistory');
  }

  bool areMultipleDestinationDirectionsEnabled(
    CompanySettingsModel settings,
  ) {
    return areJobsEnabled(settings) &&
        settings.jobs['multipleDestinationDirections'] != false;
  }

  bool isPayrollEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'payroll') &&
        _boolValue(settings.payroll, 'enabled');
  }

  bool arePayPeriodsEnabled(
    CompanySettingsModel settings,
  ) {
    return isPayrollEnabled(settings) &&
        _boolValue(settings.payroll, 'payPeriods');
  }

  bool isPayrollSummaryEnabled(
    CompanySettingsModel settings,
  ) {
    return isPayrollEnabled(settings) &&
        _boolValue(settings.payroll, 'payrollSummary');
  }

  bool arePayrollExportsEnabled(
    CompanySettingsModel settings,
  ) {
    return isPayrollEnabled(settings) &&
        _boolValue(settings.payroll, 'exports');
  }

  bool isFeedbackEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'feedback') &&
        _boolValue(settings.feedback, 'enabled');
  }

  bool areBugReportsEnabled(
    CompanySettingsModel settings,
  ) {
    return isFeedbackEnabled(settings) &&
        _boolValue(settings.feedback, 'bugReports');
  }

  bool areFeatureRequestsEnabled(
    CompanySettingsModel settings,
  ) {
    return isFeedbackEnabled(settings) &&
        _boolValue(settings.feedback, 'featureRequests');
  }

  bool areFeedbackQuestionsEnabled(
    CompanySettingsModel settings,
  ) {
    return isFeedbackEnabled(settings) &&
        _boolValue(settings.feedback, 'questions');
  }

  bool areFeedbackScreenshotsEnabled(
    CompanySettingsModel settings,
  ) {
    return isFeedbackEnabled(settings) &&
        _boolValue(settings.feedback, 'screenshots');
  }

  bool isScheduleEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'schedule');
  }

  bool areCrewsEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'crews');
  }

  bool isVehiclesEnabled(CompanySettingsModel settings) {
    return _dashboardToggleEnabled(settings, 'vehicles') &&
        _boolValue(settings.vehicles, 'enabled');
  }

  bool isVehicleRequiredForJobs(CompanySettingsModel settings) {
    return isVehiclesEnabled(settings) &&
        _boolValue(settings.vehicles, 'requireVehicleForJobs');
  }

  String disabledMessageForFeature(String featureKey) {
    switch (featureKey) {
      case 'timeOff':
        return 'Time Off has been disabled by your company.';

      case 'teamTime':
        return 'Team Time has been disabled by your company.';

      case 'clockInOut':
        return 'Clock In / Clock Out has been disabled by your company.';

      case 'breaks':
        return 'Breaks have been disabled by your company.';

      case 'correctionRequests':
        return 'Correction Requests have been disabled by your company.';

      case 'managerEdits':
        return 'Manager time edits have been disabled by your company.';

      case 'messaging':
        return 'Messaging has been disabled by your company.';

      case 'directMessages':
        return 'Direct Messages have been disabled by your company.';

      case 'crewMessages':
        return 'Crew Messages have been disabled by your company.';

      case 'announcements':
        return 'Announcements have been disabled by your company.';

      case 'jobs':
        return 'Jobs have been disabled by your company.';

      case 'jobCancellation':
        return 'Job cancellation has been disabled by your company.';

      case 'jobHistory':
        return 'Job History has been disabled by your company.';

      case 'payroll':
        return 'Payroll has been disabled by your company.';

      case 'payPeriods':
        return 'Pay Periods have been disabled by your company.';

      case 'payrollSummary':
        return 'Payroll Summary has been disabled by your company.';

      case 'payrollExports':
        return 'Payroll exports have been disabled by your company.';

      case 'feedback':
        return 'Feedback has been disabled by your company.';

      case 'bugReports':
        return 'Bug Reports have been disabled by your company.';

      case 'featureRequests':
        return 'Feature Requests have been disabled by your company.';

      case 'feedbackQuestions':
        return 'Feedback Questions have been disabled by your company.';

      case 'schedule':
        return 'Scheduling has been disabled by your company.';

      case 'crews':
        return 'Crews have been disabled by your company.';

      case 'vehicles':
        return 'Vehicles have been disabled by your company.';

      default:
        return 'This feature has been disabled by your company.';
    }
  }

  void requireTimeOffEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isTimeOffEnabled(settings),
      disabledMessageForFeature('timeOff'),
    );
  }

  void requireTimeOffTypeEnabled(
    CompanySettingsModel settings,
    String leaveType,
  ) {
    requireTimeOffEnabled(settings);

    _require(
      isTimeOffTypeEnabled(settings, leaveType),
      '$leaveType requests have been disabled by your company.',
    );
  }

  void requireTeamTimeEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isTeamTimeEnabled(settings),
      disabledMessageForFeature('teamTime'),
    );
  }

  void requireClockInOutEnabled(
    CompanySettingsModel settings,
  ) {
    requireTeamTimeEnabled(settings);

    _require(
      isClockInOutEnabled(settings),
      disabledMessageForFeature('clockInOut'),
    );
  }

  void requireBreaksEnabled(
    CompanySettingsModel settings,
  ) {
    requireClockInOutEnabled(settings);

    _require(
      areBreaksEnabled(settings),
      disabledMessageForFeature('breaks'),
    );
  }

  void requireCorrectionRequestsEnabled(
    CompanySettingsModel settings,
  ) {
    requireTeamTimeEnabled(settings);

    _require(
      areCorrectionRequestsEnabled(settings),
      disabledMessageForFeature('correctionRequests'),
    );
  }

  void requireManagerTimeEditsEnabled(
    CompanySettingsModel settings,
  ) {
    requireTeamTimeEnabled(settings);

    _require(
      areManagerTimeEditsEnabled(settings),
      disabledMessageForFeature('managerEdits'),
    );
  }

  void requireMessagingEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isMessagingEnabled(settings),
      disabledMessageForFeature('messaging'),
    );
  }

  void requireDirectMessagesEnabled(
    CompanySettingsModel settings,
  ) {
    requireMessagingEnabled(settings);

    _require(
      areDirectMessagesEnabled(settings),
      disabledMessageForFeature('directMessages'),
    );
  }

  void requireCrewMessagesEnabled(
    CompanySettingsModel settings,
  ) {
    requireMessagingEnabled(settings);

    _require(
      areCrewMessagesEnabled(settings),
      disabledMessageForFeature('crewMessages'),
    );
  }

  void requireAnnouncementsEnabled(
    CompanySettingsModel settings,
  ) {
    requireMessagingEnabled(settings);

    _require(
      areAnnouncementsEnabled(settings),
      disabledMessageForFeature('announcements'),
    );
  }

  void requireJobsEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      areJobsEnabled(settings),
      disabledMessageForFeature('jobs'),
    );
  }

  void requireJobCancellationAllowed(
    CompanySettingsModel settings,
  ) {
    requireJobsEnabled(settings);

    _require(
      isJobCancellationAllowed(settings),
      disabledMessageForFeature('jobCancellation'),
    );
  }

  void requireJobHistoryEnabled(
    CompanySettingsModel settings,
  ) {
    requireJobsEnabled(settings);

    _require(
      isJobHistoryEnabled(settings),
      disabledMessageForFeature('jobHistory'),
    );
  }

  void requirePayrollEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isPayrollEnabled(settings),
      disabledMessageForFeature('payroll'),
    );
  }

  void requirePayPeriodsEnabled(
    CompanySettingsModel settings,
  ) {
    requirePayrollEnabled(settings);

    _require(
      arePayPeriodsEnabled(settings),
      disabledMessageForFeature('payPeriods'),
    );
  }

  void requirePayrollSummaryEnabled(
    CompanySettingsModel settings,
  ) {
    requirePayrollEnabled(settings);

    _require(
      isPayrollSummaryEnabled(settings),
      disabledMessageForFeature('payrollSummary'),
    );
  }

  void requirePayrollExportsEnabled(
    CompanySettingsModel settings,
  ) {
    requirePayrollEnabled(settings);

    _require(
      arePayrollExportsEnabled(settings),
      disabledMessageForFeature('payrollExports'),
    );
  }

  void requireFeedbackEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isFeedbackEnabled(settings),
      disabledMessageForFeature('feedback'),
    );
  }

  void requireScheduleEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isScheduleEnabled(settings),
      disabledMessageForFeature('schedule'),
    );
  }

  void requireCrewsEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      areCrewsEnabled(settings),
      disabledMessageForFeature('crews'),
    );
  }

  void requireVehiclesEnabled(
    CompanySettingsModel settings,
  ) {
    _require(
      isVehiclesEnabled(settings),
      disabledMessageForFeature('vehicles'),
    );
  }

  bool _dashboardToggleEnabled(
    CompanySettingsModel settings,
    String featureKey,
  ) {
    return settings.dashboardFeatures[featureKey] == true;
  }

  bool _boolValue(
    Map<String, dynamic> source,
    String key,
  ) {
    return source[key] == true;
  }

  String _normalizeKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _require(bool condition, String message) {
    if (!condition) {
      throw StateError(message);
    }
  }
}
