import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:beta_app/services/otp_handoff_service.dart';
import 'package:beta_app/services/otp_navigation_policy.dart';

class OtpBrowserScreen extends StatefulWidget {
  const OtpBrowserScreen({
    super.key,
    required this.initialUri,
    required this.origin,
    required this.method,
    required this.handoffService,
  });

  final Uri initialUri;
  final String origin;
  final String method;
  final OtpHandoffService handoffService;

  @override
  State<OtpBrowserScreen> createState() => _OtpBrowserScreenState();
}

class _OtpBrowserScreenState extends State<OtpBrowserScreen> {
  final TextEditingController _codeController = TextEditingController();
  InAppWebViewController? _controller;
  String? _pageTitle;
  bool _loading = true;
  bool _transferring = false;
  bool _finished = false;
  OtpHandoffSession? _activeSession;
  String? _status;
  late final Set<String> _allowedOrigins = <String>{widget.origin};

  String? _httpsOrigin(Uri? uri) => OtpNavigationPolicy.httpsOrigin(uri);

  Future<bool> _authorizeNavigation(Uri? uri) async {
    final origin = _httpsOrigin(uri);
    if (origin == null) {
      if (mounted) {
        setState(() => _status = 'Navegación bloqueada: solo se permiten sitios HTTPS seguros en el puerto estándar.');
      }
      return false;
    }
    if (_allowedOrigins.contains(origin)) return true;
    if (!mounted) return false;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Permitir redirección?'),
        content: Text(
          'El sitio quiere abrir otro dominio:\\n\\n${uri!.host}\\n\\n'
          'Solo se permitirá durante esta sesión privada. El código OTP '
          'seguirá limitado al sitio original: ${widget.origin}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Bloquear'),
          ),
          FilledButton(
            key: const Key('otp-allow-redirect-origin'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Permitir este dominio'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return false;
    _allowedOrigins.add(origin);
    setState(() => _status = 'Dominio autorizado para esta sesión: ${uri!.host}.');
    return true;
  }

  Future<bool> _isOnOriginalOrigin() async {
    final current = await _controller?.getUrl();
    return _httpsOrigin(current == null ? null : Uri.tryParse(current.toString())) ==
        widget.origin;
  }

  @override
  void dispose() {
    _codeController.dispose();
    unawaited(_cancelAndClose());
    super.dispose();
  }

  Future<void> _cancelAndClose() async {
    final session = _activeSession;
    if (!_finished && session != null) {
      try {
        await widget.handoffService.cancelSession(session);
      } catch (_) {
        // Expired or already-consumed sessions are already unusable.
      }
    }
    widget.handoffService.close();
  }

  Future<bool> _focusedFieldCanReceiveCode() async {
    final controller = _controller;
    if (controller == null || !await _isOnOriginalOrigin()) return false;
    final result = await controller.evaluateJavascript(source: '''
      (() => {
        const el = document.activeElement;
        if (!el || el.tagName !== 'INPUT') return false;
        const type = (el.type || 'text').toLowerCase();
        if (!['text', 'tel', 'number'].includes(type)) return false;
        const hints = [
          el.name || '',
          el.id || '',
          el.getAttribute('aria-label') || '',
          el.getAttribute('autocomplete') || ''
        ].join(' ').toLowerCase();
        const hasOtpHint = /otp|one.?time|verification|verify|security.?code|auth.?code/.test(hints);
        const numericInput = type === 'tel' || type === 'number';
        const shortField = el.maxLength > 0 && el.maxLength <= 10;
        return hasOtpHint || (numericInput && shortField);
      })();
    ''');
    return result == true;
  }

  Future<bool> _fillFocusedField(String code) async {
    final controller = _controller;
    // Never insert a code into an identity-provider or redirected domain.
    if (controller == null || !await _isOnOriginalOrigin()) return false;
    final encodedCode = jsonEncode(code);
    final result = await controller.evaluateJavascript(source: '''
      (() => {
        const code = $encodedCode;
        const el = document.activeElement;
        if (!el || el.tagName !== 'INPUT') return false;
        const type = (el.type || 'text').toLowerCase();
        if (!['text', 'tel', 'number'].includes(type)) return false;
        const hints = [
          el.name || '',
          el.id || '',
          el.getAttribute('aria-label') || '',
          el.getAttribute('autocomplete') || ''
        ].join(' ').toLowerCase();
        const hasOtpHint = /otp|one.?time|verification|verify|security.?code|auth.?code/.test(hints);
        const numericInput = type === 'tel' || type === 'number';
        const shortField = el.maxLength > 0 && el.maxLength <= 10;
        if (!(hasOtpHint || (numericInput && shortField))) return false;
        const setter = Object.getOwnPropertyDescriptor(
          HTMLInputElement.prototype, 'value'
        ).set;
        setter.call(el, code);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      })();
    ''');
    return result == true;
  }

  Future<void> _transferCode() async {
    if (_transferring || _finished) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{4,10}$').hasMatch(code)) {
      setState(() => _status = 'Escribe un código de 4 a 10 dígitos.');
      return;
    }

    final onOriginalSite = await _isOnOriginalOrigin();
    if (!mounted) return;
    if (!onOriginalSite) {
      setState(() => _status =
          'La verificación debe completarse en el sitio original (${widget.origin}). Vuelve a ese sitio antes de transferir el código.');
      return;
    }

    final canFill = await _focusedFieldCanReceiveCode();
    if (!mounted) return;
    if (!canFill) {
      setState(() => _status =
          'Primero toca el campo del código en la página. Solo se rellenan campos OTP compatibles.');
      return;
    }

    setState(() {
      _transferring = true;
      _status = 'Transfiriendo una sola vez…';
    });

    try {
      // Create the 90-second backend session only after the user has the code
      // ready, so browsing/login time cannot consume the OTP lifetime.
      final session = await widget.handoffService.createSession(
        origin: widget.origin,
        method: widget.method,
      );
      if (!mounted) return;
      _activeSession = session;
      final codeFromRelay = await widget.handoffService.submitAndConsume(
        session: session,
        code: code,
      );
      if (!mounted) return;
      final filled = await _fillFocusedField(codeFromRelay);
      if (!mounted) return;
      if (!filled) {
        setState(() {
          _finished = true;
          _status =
              'El código se consumió de forma segura, pero el campo perdió el foco. Inicia una verificación nueva.';
          _codeController.clear();
        });
        return;
      }
      setState(() {
        _finished = true;
        _status = 'Código transferido al campo seleccionado. Revisa la página y confirma allí.';
        _codeController.clear();
      });
      HapticFeedback.selectionClick();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  void _closeBrowser() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.initialUri.host;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_pageTitle ?? 'Navegador privado',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(host, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar navegador',
            onPressed: _transferring ? null : _closeBrowser,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sesión privada · redirecciones HTTPS con autorización · OTP solo para el sitio original',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  key: const ValueKey('otp-private-webview'),
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.initialUri.toString()),
                  ),
                  initialSettings: InAppWebViewSettings(
                    incognito: true,
                    cacheEnabled: false,
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    useShouldOverrideUrlLoading: true,
                    // Incognito storage is discarded when this WebView closes.
                    supportMultipleWindows: false,
                    allowFileAccess: false,
                    allowContentAccess: false,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                    thirdPartyCookiesEnabled: false,
                    geolocationEnabled: false,
                    safeBrowsingEnabled: true,
                    mediaPlaybackRequiresUserGesture: true,
                    disableContextMenu: true,
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                  },
                  onPermissionRequest: (controller, request) async {
                    // OTP login pages do not need camera, microphone, or location.
                    return PermissionResponse(
                      action: PermissionResponseAction.DENY,
                      resources: const [],
                    );
                  },
                  onLoadStart: (controller, url) {
                    if (mounted) setState(() => _loading = true);
                  },
                  onLoadStop: (controller, url) async {
                    if (!mounted) return;
                    setState(() {
                      _loading = false;
                      _pageTitle = url?.host;
                    });
                  },
                  onUpdateVisitedHistory: (controller, url, isReload) async {
                    final origin = _httpsOrigin(url);
                    if (origin == null || !_allowedOrigins.contains(origin)) {
                      await controller.stopLoading();
                      if (mounted) {
                        setState(() => _status =
                            'Navegación detenida: el dominio no está autorizado para esta sesión.');
                      }
                    }
                  },
                  onTitleChanged: (controller, title) {
                    if (mounted && title != null) {
                      setState(() => _pageTitle = title);
                    }
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    final allowed = await _authorizeNavigation(action.request.url);
                    return allowed
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                ),
                if (_loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('otp-private-code-input'),
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 10,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Código de verificación',
                      hintText: 'Escribe aquí el código recibido',
                      counterText: '',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('otp-private-transfer'),
                    onPressed: _transferring || _finished
                        ? null
                        : _transferCode,
                    icon: _transferring
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(_transferring
                        ? 'Transfiriendo…'
                        : 'Transferir al campo seleccionado'),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _status!,
                      key: const Key('otp-private-status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const Text(
                    'La sesión temporal se crea al transferir el código y vence en 90 segundos.',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
