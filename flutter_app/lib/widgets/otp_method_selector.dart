import 'package:flutter/material.dart';

enum OtpVerificationMethod {
  email,
  sms,
  authenticator,
}

extension OtpVerificationMethodLabel on OtpVerificationMethod {
  String get title => switch (this) {
        OtpVerificationMethod.email => 'Correo electrónico',
        OtpVerificationMethod.sms => 'Mensaje SMS',
        OtpVerificationMethod.authenticator => 'Aplicación autenticadora',
      };

  String get description => switch (this) {
        OtpVerificationMethod.email =>
          'Código enviado por el servicio al correo de la cuenta.',
        OtpVerificationMethod.sms =>
          'Código enviado por el servicio mediante mensaje de texto.',
        OtpVerificationMethod.authenticator =>
          'Código temporal de una app compatible, como Google o Microsoft Authenticator.',
      };

  IconData get icon => switch (this) {
        OtpVerificationMethod.email => Icons.email_outlined,
        OtpVerificationMethod.sms => Icons.sms_outlined,
        OtpVerificationMethod.authenticator => Icons.security_outlined,
      };
}

/// Lets the user choose a verification channel offered by the website.
///
/// This widget deliberately does not read inboxes, SMS, authenticator apps,
/// persist OTP values, or send codes to AI. A verified browser-session handoff
/// must be connected before any code can be transferred to a website.
class OtpMethodSelector extends StatelessWidget {
  const OtpMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.onChanged,
    this.availableMethods = const {
      OtpVerificationMethod.email,
      OtpVerificationMethod.sms,
      OtpVerificationMethod.authenticator,
    },
  });

  final OtpVerificationMethod? selectedMethod;
  final ValueChanged<OtpVerificationMethod> onChanged;
  final Set<OtpVerificationMethod> availableMethods;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Método de verificación',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Elige uno de los métodos que la página indique como disponibles.',
        ),
        const SizedBox(height: 10),
        for (final method in OtpVerificationMethod.values)
          Card(
            key: Key('otp-method-${method.name}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<OtpVerificationMethod>(
              value: method,
              groupValue: selectedMethod,
              onChanged: availableMethods.contains(method)
                  ? (value) {
                      if (value != null) onChanged(value);
                    }
                  : null,
              secondary: Icon(
                method.icon,
                color: availableMethods.contains(method)
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              title: Text(method.title),
              subtitle: Text(
                availableMethods.contains(method)
                    ? method.description
                    : 'No ofrecido por esta página.',
              ),
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Protección: esta pantalla solo permite elegir el método. '
                    'No lee SMS ni correos, no accede a otras apps autenticadoras '
                    'y no guarda ni envía códigos OTP. La transferencia segura '
                    'al navegador requiere conectar el flujo de sesión verificada.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
