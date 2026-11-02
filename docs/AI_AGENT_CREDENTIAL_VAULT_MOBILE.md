# Integración móvil: AI Agent Ultimate Credential Vault

## Clientes
- Android nativo: `app/src/main/java/com/example/data/credentials/CredentialVaultService.kt`
- Flutter (Android/iOS): `flutter_app/lib/services/credential_vault_service.dart`

Ambos clientes usan HTTPS y el mismo contrato. La identidad procede exclusivamente del usuario autenticado de Firebase; el UID no se envía en el cuerpo ni se acepta desde el cliente.

## Configuración pendiente
No se fija una URL de producción hasta verificar que el Worker esté desplegado.
- Android: establecer `AI_AGENT_BASE_URL` como Gradle project property HTTPS; se incorpora a BuildConfig.
- Flutter: compilar con `--dart-define=AI_AGENT_BASE_URL=https://<worker-host-verificado>`.

## Contrato
- `GET /v1/credentials`: lista metadatos únicamente.
- `POST /v1/credentials`: crea activa o borrador.
- `PATCH /v1/credentials/{id}`: actualiza.
- `DELETE /v1/credentials/{id}`: elimina.

Los clientes no pueden recuperar contraseñas en texto plano. El servidor cifra los secretos; los campos secretos solo viajan al servidor durante creación/actualización mediante TLS.

## Estado
Estos clientes de red son una capa de servicio. Falta conectar la interfaz de gestión en ambas aplicaciones y validar compilaciones/integración contra un Worker desplegado. No se debe habilitar producción hasta verificar el host, aplicar migraciones D1 y desplegar el backend.
