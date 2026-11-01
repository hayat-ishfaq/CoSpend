import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/firebase_error_mapper.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/loading_button.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/password_field.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final nameErr = Validators.name(name);
    final emailErr = Validators.email(email);
    final passErr = Validators.password(password);
    final confirmErr = Validators.confirmPassword(
      _confirmController.text,
      password,
    );

    setState(() {
      _nameError = nameErr;
      _emailError = emailErr;
      _passwordError = passErr;
      _confirmError = confirmErr;
      _formError = null;
    });

    if (nameErr != null ||
        emailErr != null ||
        passErr != null ||
        confirmErr != null) {
      return;
    }

    ref
        .read(authActionsProvider.notifier)
        .signUp(name: name, email: email, password: password);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(authActionsProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final error = next.error!;
        final message = error is AppException
            ? error.message
            : FirebaseErrorMapper.messageFor(error);

        setState(() {
          _formError = message;
          if (message.toLowerCase().contains('already exists')) {
            _emailError = 'Email already registered';
          }
        });

        showAppSnack(
          context,
          message,
          error: true,
        );
      } else if ((previous?.isLoading ?? false) &&
          !next.isLoading &&
          !next.hasError) {
        setState(() {
          _formError = null;
        });
      }
    });

    final submitting = ref.watch(authActionsProvider).isLoading;

    // Provide contextual action in error banner if account already exists
    String? bannerActionLabel;
    VoidCallback? bannerAction;
    if (_formError != null) {
      final lower = _formError!.toLowerCase();
      if (lower.contains('already exists') || lower.contains('already in use')) {
        bannerActionLabel = 'Sign in instead';
        bannerAction = () => context.go(Routes.login);
      }
    }

    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'A free ${AppConstants.appName} account, ready in seconds.',
      footer: Center(
        child: TextButton(
          onPressed: () => context.go(Routes.login),
          child: const Text('Already have an account? Sign in'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Full name',
              hintText: 'Alex Morgan',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              errorText: _nameError,
            ),
            onChanged: (_) {
              if (_nameError != null || _formError != null) {
                setState(() {
                  _nameError = Validators.name(_nameController.text.trim());
                  _formError = null;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'alex@example.com',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              errorText: _emailError,
            ),
            onChanged: (_) {
              if (_emailError != null || _formError != null) {
                setState(() {
                  _emailError = Validators.email(_emailController.text.trim());
                  _formError = null;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _passwordController,
            errorText: _passwordError,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirmController,
            label: 'Confirm password',
            errorText: _confirmError,
            autofillHints: const [AutofillHints.newPassword],
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          if (_formError != null)
            AuthErrorBanner(
              message: _formError!,
              actionLabel: bannerActionLabel,
              onAction: bannerAction,
              onDismiss: () => setState(() => _formError = null),
            ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                children: [
                  const TextSpan(text: 'By creating an account you agree to our '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse(AppConstants.termsOfServiceUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: const Text(
                        'Terms',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF1E3A5F),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' and '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () async {
                        final uri = Uri.parse(AppConstants.privacyPolicyUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF1E3A5F),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          LoadingButton(
            label: 'Create account',
            isLoading: submitting,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}