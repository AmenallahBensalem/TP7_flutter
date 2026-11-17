import 'package:flutter/material.dart';

class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [colors.surfaceContainerHigh, colors.surface]
              : const [Color(0xFFE6DAFB), Color(0xFFF8F4FF), Color(0xFFFDFBFF)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (viewport.maxHeight - 32)
                      .clamp(0, double.infinity)
                      .toDouble(),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 3,
                      shadowColor: colors.primary.withValues(alpha: 0.20),
                      color: colors.surface,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(
                          viewport.maxWidth < 380 ? 24 : 32,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.register});

  final bool register;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(
              Icons.groups_rounded,
              color: colors.onPrimary,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            register ? 'Créer un compte' : 'Bienvenue',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          register
              ? 'Remplissez le formulaire, un administrateur validera votre demande'
              : 'Connectez-vous pour accéder à la salle d’attente',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class CustomTextField extends StatefulWidget {
  const CustomTextField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    required this.autofill,
    required this.validate,
    required this.enabled,
    this.keyboard,
    this.password = false,
    this.onSubmitted,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String autofill;
  final String? Function(String) validate;
  final bool enabled;
  final TextInputType? keyboard;
  final bool password;
  final VoidCallback? onSubmitted;

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon, size: 20),
        suffixIcon: widget.password
            ? IconButton(
                tooltip: _visible
                    ? 'Masquer ${widget.label.toLowerCase()}'
                    : 'Afficher ${widget.label.toLowerCase()}',
                onPressed: widget.enabled
                    ? () => setState(() => _visible = !_visible)
                    : null,
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              )
            : null,
      ),
      enabled: widget.enabled,
      keyboardType: widget.keyboard,
      autofillHints: [widget.autofill],
      obscureText: widget.password && !_visible,
      textInputAction: widget.onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onFieldSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted!(),
      validator: (value) => widget.validate(value ?? ''),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        disabledBackgroundColor: colors.primaryContainer,
        disabledForegroundColor: colors.onPrimaryContainer,
      ),
      child: loading
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onPrimaryContainer,
                semanticsLabel: 'En cours…',
              ),
            )
          : Text(label),
    );
  }
}
