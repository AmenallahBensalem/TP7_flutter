import 'package:flutter/material.dart';

import 'auth_repository.dart';
import 'auth_widgets.dart';

class AuthForm extends StatefulWidget {
  const AuthForm({super.key, required this.repository, this.message});

  final AuthRepository repository;
  final String? message;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _register = false;
  bool _submitting = false;
  bool _hideGateMessage = false;

  @override
  void didUpdateWidget(covariant AuthForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) {
      _hideGateMessage = false;
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _hideGateMessage = true;
    });
    try {
      final email = _email.text.trim();
      if (_register) {
        await widget.repository.signUp(
          fullName: _name.text.trim(),
          email: email,
          phone: _phone.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        setState(() {
          _register = false;
          _password.clear();
          _confirmation.clear();
        });
        if (widget.repository.auth.currentSession == null) {
          _showFeedback(
            'Inscription envoyée. Si Supabase vous envoie un email de '
            'confirmation, ouvrez le lien. Un admin doit ensuite valider votre compte.',
            success: true,
          );
        }
      } else {
        await widget.repository.signIn(email, _password.text);
        if (mounted) _password.clear();
      }
    } catch (error) {
      if (mounted) {
        _showFeedback(AuthRepository.errorMessage(error), success: false);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showFeedback(String message, {required bool success}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: success
              ? const Color(0xFF246447)
              : colors.errorContainer,
          content: Text(
            message,
            style: TextStyle(
              color: success ? Colors.white : colors.onErrorContainer,
            ),
          ),
        ),
      );
  }

  Widget _field({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String? Function(String) validate,
    TextInputType? keyboard,
    required String autofill,
    bool obscure = false,
    bool last = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CustomTextField(
        key: ValueKey(label),
        label: label,
        icon: icon,
        controller: controller,
        enabled: !_submitting,
        keyboard: keyboard,
        autofill: autofill,
        password: obscure,
        onSubmitted: last ? _submit : null,
        validate: validate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = _hideGateMessage ? null : widget.message;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: AuthCard(
        child: AutofillGroup(
          child: Form(
            key: _form,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_register),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              tween: Tween(begin: 0, end: 1),
              curve: Curves.easeOut,
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthHeader(register: _register),
                  const SizedBox(height: 24),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          style: TextStyle(color: colors.onSurface),
                        ),
                      ),
                    ),
                  if (_register)
                    _field(
                      label: 'Nom complet',
                      icon: Icons.person_outline,
                      controller: _name,
                      autofill: AutofillHints.name,
                      validate: (value) => value.trim().isEmpty
                          ? 'Saisissez votre nom complet.'
                          : null,
                    ),
                  _field(
                    label: 'Email',
                    icon: Icons.mail_outline,
                    controller: _email,
                    keyboard: TextInputType.emailAddress,
                    autofill: AutofillHints.email,
                    validate: (value) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(value.trim())
                        ? null
                        : 'Saisissez une adresse email valide.',
                  ),
                  if (_register)
                    _field(
                      label: 'Téléphone',
                      icon: Icons.phone_outlined,
                      controller: _phone,
                      keyboard: TextInputType.phone,
                      autofill: AutofillHints.telephoneNumber,
                      validate: (value) {
                        final number = value.trim().replaceAll(
                          RegExp(r'[\s().-]'),
                          '',
                        );
                        return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)
                            ? null
                            : 'Saisissez un numéro de 7 à 15 chiffres.';
                      },
                    ),
                  _field(
                    label: 'Mot de passe',
                    icon: Icons.lock_outline,
                    controller: _password,
                    obscure: true,
                    last: !_register,
                    autofill: _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                    validate: (value) {
                      if (value.isEmpty) {
                        return 'Saisissez votre mot de passe.';
                      }
                      return _register && value.length < 8
                          ? 'Utilisez au moins 8 caractères.'
                          : null;
                    },
                  ),
                  if (_register)
                    _field(
                      label: 'Confirmer le mot de passe',
                      icon: Icons.lock_outline,
                      controller: _confirmation,
                      obscure: true,
                      last: true,
                      autofill: AutofillHints.newPassword,
                      validate: (value) {
                        if (value.isEmpty) {
                          return 'Confirmez votre mot de passe.';
                        }
                        return value == _password.text
                            ? null
                            : 'Les mots de passe doivent être identiques.';
                      },
                    ),
                  PrimaryButton(
                    label: _register ? 'S’inscrire' : 'Se connecter',
                    loading: _submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _register
                            ? 'Déjà un compte ?'
                            : 'Pas encore de compte ?',
                      ),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () {
                                _form.currentState?.reset();
                                ScaffoldMessenger.of(
                                  context,
                                ).hideCurrentSnackBar();
                                setState(() {
                                  _register = !_register;
                                  _hideGateMessage = true;
                                });
                              },
                        child: Text(
                          _register ? 'Se connecter' : 'Créer un compte',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }
}
