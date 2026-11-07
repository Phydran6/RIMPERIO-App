// ---------------------------------------------------------------------------
// Datei:        lib/screens/login_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Anmeldung am Server — Benutzer/Passwort (samt Zweitfaktor,
//               falls eingerichtet) oder per QR-Code.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../ui/scope.dart';
import '../ui/widgets.dart';
import 'scan_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  String? _mfaToken;
  String? _error;
  bool _busy = false;
  bool _showPw = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_user.text.isEmpty) _user.text = context.session.username ?? '';
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_mfaToken == null) {
        if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
          throw const ApiException('Bitte Benutzer und Passwort eingeben.');
        }
        final mfa = await s.loginWithPassword(_user.text.trim(), _pass.text);
        if (mfa != null && mounted) setState(() => _mfaToken = mfa);
      } else {
        await s.loginWithMfa(_mfaToken!, _code.text.trim());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 401 && _mfaToken == null ? 'Benutzer oder Passwort falsch.' : e.message;
        if (e.status == 401 && _mfaToken != null && e.message.contains('MFA-Token')) {
          _mfaToken = null; // Zweitfaktor-Fenster abgelaufen → von vorn
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final cs = context.cs;
    final mfa = _mfaToken != null;
    return Scaffold(
      body: Column(children: [
        if (!s.isSecure) const SafeArea(bottom: false, child: InsecureBanner()),
        Expanded(
          child: SafeArea(
            top: s.isSecure,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Center(child: Logo(size: 110)),
                      const SizedBox(height: 16),
                      Text(mfa ? 'Zweitfaktor' : 'Anmelden',
                          textAlign: TextAlign.center, style: context.tt.headlineSmall),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(s.isSecure ? Icons.lock_rounded : Icons.lock_open_rounded,
                            size: 14, color: s.isSecure ? const Color(0xFF30A46C) : const Color(0xFFF2555A)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(s.server?.host ?? '',
                              overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                        ),
                      ]),
                      if (s.loginNotice != null) ...[
                        const SizedBox(height: 16),
                        Card(
                          color: cs.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(s.loginNotice!, style: TextStyle(color: cs.onSecondaryContainer)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (!mfa) ...[
                        TextField(
                          controller: _user,
                          enabled: !_busy,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Benutzer', prefixIcon: Icon(Icons.person_outline)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pass,
                          enabled: !_busy,
                          obscureText: !_showPw,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Passwort',
                            prefixIcon: const Icon(Icons.key_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _showPw = !_showPw),
                            ),
                          ),
                        ),
                      ] else ...[
                        Text('Code aus der Authenticator-App oder einen Backup-Code eingeben.',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _code,
                          enabled: !_busy,
                          autofocus: true,
                          keyboardType: TextInputType.visiblePassword,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(fontSize: 22, letterSpacing: 6),
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(hintText: '123456'),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: cs.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(mfa ? 'Bestätigen' : 'Anmelden'),
                      ),
                      const SizedBox(height: 12),
                      if (mfa)
                        TextButton(
                          onPressed: _busy ? null : () => setState(() => _mfaToken = null),
                          child: const Text('Zurück'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => ScanPage.open(context),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Mit QR-Code anmelden'),
                        ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: _busy ? null : () => s.changeServer(),
                        child: const Text('Anderen Server verwenden'),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
