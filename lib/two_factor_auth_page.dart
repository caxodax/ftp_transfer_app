// lib/two_factor_auth_page.dart

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:base32/base32.dart';
import 'package:otp/otp.dart';

import 'home_page.dart';
import 'user_data_service.dart';
import 'login_page.dart';

class TwoFactorAuthPage extends StatefulWidget {
  final User user;

  const TwoFactorAuthPage({super.key, required this.user});

  @override
  State<TwoFactorAuthPage> createState() => _TwoFactorAuthPageState();
}

class _TwoFactorAuthPageState extends State<TwoFactorAuthPage> {
  final TextEditingController _otpController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false;

  String? _twoFactorSecret;          // Secreto Base32
  bool _twoFactorConfigured = false; // Para decidir si mostrar QR

  @override
  void initState() {
    super.initState();
    _loadTwoFactorState();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  // -------- Helpers secreto TOTP --------
  String _normalizeSecret(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');

  String _generateBase32Secret([int byteLength = 20]) {
    final rnd = Random.secure();
    final bytes =
        Uint8List.fromList(List<int>.generate(byteLength, (_) => rnd.nextInt(256)));
    return base32.encode(bytes).toUpperCase().replaceAll('=', '');
  }

  // -------- Carga/creación del estado 2FA --------
  Future<void> _loadTwoFactorState() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(widget.user.uid);

      // Si la red anda mal, evita quedar colgado:
      final doc = await docRef.get().timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;
        final dbSecret = (data['twoFactorSecret'] as String? ?? '').trim();
        final configured = (data['twoFactorConfigured'] as bool? ?? false);

        if (dbSecret.isEmpty) {
          // No hay secreto -> crear uno y dejar configured=false para mostrar QR
          final newSecret = _generateBase32Secret();
          await docRef.set(
            {'twoFactorSecret': newSecret, 'twoFactorConfigured': false},
            SetOptions(merge: true),
          );
          if (!mounted) return;
          setState(() {
            _twoFactorSecret = newSecret;
            _twoFactorConfigured = false;
          });
          UserDataService().twoFactorSecret = newSecret;
        } else {
          final normalized = _normalizeSecret(dbSecret);
          setState(() {
            _twoFactorSecret = normalized;
            _twoFactorConfigured = configured;
          });
          UserDataService().twoFactorSecret = normalized;
        }
      } else {
        // Documento no existe -> crearlo
        final newSecret = _generateBase32Secret();
        await docRef.set({
          'email': widget.user.email,
          'twoFactorSecret': newSecret,
          'twoFactorConfigured': false,
        }, SetOptions(merge: true));
        if (!mounted) return;
        setState(() {
          _twoFactorSecret = newSecret;
          _twoFactorConfigured = false;
        });
        UserDataService().twoFactorSecret = newSecret;
      }
    } catch (e) {
      // Captura cualquier error (permisos, red, timeout, etc.)
      setState(() {
        _errorMessage =
            'No se pudo cargar la configuración 2FA. ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markConfiguredTrue() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set({'twoFactorConfigured': true}, SetOptions(merge: true));
      if (mounted) setState(() => _twoFactorConfigured = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No se pudo marcar el 2FA como configurado. ${e.toString()}';
      });
    }
  }

  // Regenerar secreto SOLO si aún no está configurado
  Future<void> _regenerateSecretIfAllowed() async {
    if (_twoFactorConfigured) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final newSecret = _generateBase32Secret();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .set(
            {'twoFactorSecret': newSecret, 'twoFactorConfigured': false},
            SetOptions(merge: true),
          );
      if (!mounted) return;
      setState(() => _twoFactorSecret = newSecret);
      UserDataService().twoFactorSecret = newSecret;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo regenerar el secreto. ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -------- Verificación TOTP --------
  bool _verifyTotp(String code, String secret) {
    final now = DateTime.now();
    final candidates = <int>[
      now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
      now.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    ];

    for (final t in candidates) {
      final expected = OTP.generateTOTPCodeString(
        secret,
        t,
        interval: 30,
        length: 6,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (OTP.constantTimeVerification(code, expected)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _verifyOtpAndLogin() async {
    if (_isLoading) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    if (_twoFactorSecret == null || _twoFactorSecret!.isEmpty) {
      setState(() {
        _errorMessage = 'Error: Clave secreta 2FA no encontrada.';
        _isLoading = false;
      });
      return;
    }

    try {
      final inputCode = _otpController.text.trim();
      if (inputCode.length != 6 || !RegExp(r'^\d{6}$').hasMatch(inputCode)) {
        throw 'El código debe tener 6 dígitos numéricos.';
      }

      final isValid = _verifyTotp(inputCode, _twoFactorSecret!);
      if (!isValid) throw 'Código 2FA incorrecto. Inténtalo de nuevo.';

      // Si es la PRIMERA verificación, marcar como configurado
      if (!_twoFactorConfigured) {
        await _markConfiguredTrue();
      }

      // Cargar datos de compañía y continuar
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      if (!userDoc.exists) throw 'Usuario no registrado por el administrador.';

      final userData = userDoc.data()!;
      final companyId = userData['companyId'] as String?;
      if (companyId == null || companyId.isEmpty) {
        throw 'Usuario no asociado a ninguna compañía.';
      }

      final companyDoc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .get();

      if (!companyDoc.exists) throw 'La compañía asociada no existe.';

      final companyData = companyDoc.data()!;
      UserDataService().loadData(
        companyName: companyData['companyName'],
        ftpHost: companyData['ftpHost'],
        ftpUser: companyData['ftpUser'],
        ftpPassword: companyData['ftpPassword'],
        ftpPort: companyData['ftpPort'],
        userId: widget.user.uid,
        twoFactorSecret: _twoFactorSecret,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // otpauth:// TOTP
  String _generateTotpUri(String secret, String issuer, String accountName) {
    final label = Uri.encodeComponent('$issuer:$accountName');
    final iss = Uri.encodeComponent(issuer);
    final sec = Uri.encodeComponent(_normalizeSecret(secret));
    return 'otpauth://totp/$label?secret=$sec&issuer=$iss&algorithm=SHA1&period=30&digits=6';
  }

  @override
  Widget build(BuildContext context) {
    final userDataService = UserDataService();
    final accountName = widget.user.email ?? 'Usuario';
    final issuer = userDataService.companyName ?? 'Cloud Capture App';

    final showQrSetup =
        !_twoFactorConfigured && (_twoFactorSecret != null && _twoFactorSecret!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificación de 2 Factores'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading && _twoFactorSecret == null)
                const CircularProgressIndicator(),
              if (_errorMessage.isNotEmpty) ...[
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadTwoFactorState,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
                const SizedBox(height: 16),
              ],
              if (showQrSetup) ...[
                const Text(
                  'Escanea este código QR con Google Authenticator o Authy:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                QrImageView(
                  data: _generateTotpUri(_twoFactorSecret!, issuer, accountName),
                  version: QrVersions.auto,
                  size: 260.0,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Si el QR falla, introduce esta clave manualmente (TOTP, 6 dígitos, 30s, SHA1):',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: SelectableText(
                          _normalizeSecret(_twoFactorSecret!),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                              text: _normalizeSecret(_twoFactorSecret!)));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Secreto copiado')),
                          );
                        },
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed:
                      _twoFactorConfigured ? null : _regenerateSecretIfAllowed,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Regenerar secreto'),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Ingresa el código de 6 dígitos de tu aplicación de autenticación:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _otpController,
                decoration: const InputDecoration(
                  labelText: 'Código de Verificación',
                  hintText: 'Ej. 123456',
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _verifyOtpAndLogin,
                        child: const Text('Verificar y Entrar'),
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        await FirebaseAuth.instance.signOut();
                        if (!mounted) return;
                        UserDataService().clear();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (context) => LoginPage()),
                        );
                      },
                child: const Text('Volver al Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


