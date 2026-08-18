import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../Firebase/firestore_schema.dart';
import '../../Services/auth_service.dart';
import '../../Services/company_service.dart';
import '../../Services/legal_acceptance_service.dart';
import '../../theme/app_theme.dart';
import '../legal_document_screen.dart';

class RegisterCompanyScreen extends StatefulWidget {
  const RegisterCompanyScreen({super.key});

  @override
  State<RegisterCompanyScreen> createState() => _RegisterCompanyScreenState();
}

class _RegisterCompanyScreenState extends State<RegisterCompanyScreen> {
  final AuthService _authService = AuthService();
  final CompanyService _companyService = CompanyService();
  final LegalAcceptanceService _legalAcceptanceService = LegalAcceptanceService();

  final _formKey = GlobalKey<FormState>();

  final _companyNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _termsError = false;

  late final TapGestureRecognizer _termsLinkRecognizer;
  late final TapGestureRecognizer _privacyLinkRecognizer;

  @override
  void initState() {
    super.initState();
    _termsLinkRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(FSLegalDocumentType.companyTerms);
    _privacyLinkRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument(FSLegalDocumentType.privacyPolicy);
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _termsLinkRecognizer.dispose();
    _privacyLinkRecognizer.dispose();
    super.dispose();
  }

  void _openDocument(String documentType) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LegalDocumentScreen(documentType: documentType)),
    );
  }

  String get _companyDisplayName =>
      _companyNameController.text.trim().isEmpty ? 'your company' : _companyNameController.text.trim();

  // Built from the same literal fragments the RichText below renders,
  // so the plain-text version stored on the acceptance event (Section
  // 11.7) is guaranteed word-for-word identical to what the user saw
  // and tapped through, rather than two copies that could drift.
  static const _authorityPrefix = 'I represent that I am authorized to bind ';
  static const _authorityMiddle = ', and I agree on its behalf to the ';
  static const _termsLinkLabel = 'Company Terms of Service';
  static const _authorityBetween = '. I acknowledge the ';
  static const _privacyLinkLabel = 'Privacy Policy';
  static const _authoritySuffix = '.';

  String get _authorityText =>
      '$_authorityPrefix$_companyDisplayName$_authorityMiddle$_termsLinkLabel$_authorityBetween$_privacyLinkLabel$_authoritySuffix';

  static const _acceptButtonText = 'Create company and accept';

  Future<void> _createCompanyAccount() async {
    final formValid = _formKey.currentState!.validate();

    setState(() {
      _termsError = !_acceptedTerms;
    });

    if (!formValid || !_acceptedTerms) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.registerCompanyOwner(
        companyName: _companyNameController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );

      // Record terms/privacy acceptance now that the company exists.
      // Two things happen here: the old single-timestamp flag (kept so
      // existing company.hasAcceptedTerms reads still work) and the
      // real evidence-grade acceptance events (Section 11.7) — one per
      // document, since each is its own version/hash/checkbox text
      // that could change independently later.
      try {
        final profile = await _authService.getCurrentUserProfile();
        await _companyService.acceptTermsAndPrivacy(
          companyId: profile.activeCompanyId,
          userId: profile.uid,
        );

        final authorityText = _authorityText;
        for (final documentType in [FSLegalDocumentType.companyTerms, FSLegalDocumentType.privacyPolicy]) {
          await _legalAcceptanceService.recordAcceptance(
            documentType: documentType,
            userId: profile.uid,
            verifiedIdentifier: profile.email,
            capacity: FSLegalCapacity.organizationRepresentative,
            organizationId: profile.activeCompanyId,
            organizationDisplayedName: _companyNameController.text.trim(),
            role: FSRoles.owner,
            authorityText: authorityText,
            checkboxText: authorityText,
            buttonText: _acceptButtonText,
          );
        }
      } catch (_) {
        // Registration itself already succeeded; don't block the user
        // over a failure to record this timestamp. It can be recorded
        // again the next time terms are shown, if needed.
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Company account created successfully.'),
        ),
      );

      // AuthGate has already switched to the new dashboard underneath
      // this screen (it's listening to the same auth state change) —
      // pop back to root so that becomes visible instead of leaving
      // this confirmation screen sitting on top of it.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_authService.friendlyAuthErrorMessage(e)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }

    return null;
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    if (!value.contains('@') || !value.contains('.')) {
      return 'Enter a valid email';
    }

    return null;
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }

    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirm your password';
    }

    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }

    return null;
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
          'Create Company Account',
          style: TextStyle(
            color: AppTheme.darkText,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Start BlueField',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Create your company workspace and owner account.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.mutedText,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _BlueFieldTextField(
                          controller: _companyNameController,
                          label: 'Company Name',
                          icon: Icons.business_outlined,
                          validator: (value) =>
                              _requiredValidator(value, 'Company name'),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _BlueFieldTextField(
                                controller: _firstNameController,
                                label: 'First Name',
                                icon: Icons.person_outline,
                                validator: (value) =>
                                    _requiredValidator(value, 'First name'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _BlueFieldTextField(
                                controller: _lastNameController,
                                label: 'Last Name',
                                icon: Icons.person_outline,
                                validator: (value) =>
                                    _requiredValidator(value, 'Last name'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _BlueFieldTextField(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: _emailValidator,
                        ),
                        const SizedBox(height: 14),
                        _BlueFieldTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          validator: _passwordValidator,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _BlueFieldTextField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscureConfirmPassword,
                          validator: _confirmPasswordValidator,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              _acceptedTerms = !_acceptedTerms;
                              if (_acceptedTerms) _termsError = false;
                            });
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: _acceptedTerms,
                                onChanged: (value) {
                                  setState(() {
                                    _acceptedTerms = value ?? false;
                                    if (_acceptedTerms) _termsError = false;
                                  });
                                },
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: _termsError ? Colors.red : AppTheme.mutedText,
                                      ),
                                      children: [
                                        TextSpan(text: _authorityPrefix + _companyDisplayName + _authorityMiddle),
                                        TextSpan(
                                          text: _termsLinkLabel,
                                          style: const TextStyle(color: AppTheme.blue, decoration: TextDecoration.underline),
                                          recognizer: _termsLinkRecognizer,
                                        ),
                                        const TextSpan(text: _authorityBetween),
                                        TextSpan(
                                          text: _privacyLinkLabel,
                                          style: const TextStyle(color: AppTheme.blue, decoration: TextDecoration.underline),
                                          recognizer: _privacyLinkRecognizer,
                                        ),
                                        const TextSpan(text: _authoritySuffix),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_termsError)
                          const Padding(
                            padding: EdgeInsets.only(left: 44, top: 2),
                            child: Text(
                              'You must accept the Terms of Service and Privacy Policy to continue.',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed:
                                _isLoading ? null : _createCompanyAccount,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    _acceptButtonText,
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlueFieldTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;

  const _BlueFieldTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppTheme.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
