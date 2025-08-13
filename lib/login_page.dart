// lib/login_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'user_data_service.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> signInAndLoadData() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final user = userCredential.user;
      if (user == null) { throw Exception('No se pudo obtener el usuario.'); }
      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();
      if (!userDoc.exists) { throw 'Usuario no registrado por el administrador.'; }
      final userData = userDoc.data()!;
      final companyId = userData['companyId'] as String?;
      if (companyId == null || companyId.isEmpty) { throw 'Usuario no asociado a ninguna compañía.'; }
      final companyDoc = await FirebaseFirestore.instance.collection('companies').doc(companyId).get();
      if (!companyDoc.exists) { throw 'La compañía asociada no existe.'; }
      final companyData = companyDoc.data()!;
      UserDataService().loadData(
        companyName: companyData['companyName'], ftpHost: companyData['ftpHost'], ftpUser: companyData['ftpUser'],
        ftpPassword: companyData['ftpPassword'], ftpPort: companyData['ftpPort'],
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => HomePage()));
      }
    } on FirebaseAuthException {
      setState(() { _errorMessage = 'Email o contraseña incorrectos.'; });
    } catch (e) {
      await FirebaseAuth.instance.signOut(); 
      UserDataService().clear(); 
      setState(() { _errorMessage = e.toString(); });
    } finally {
      if(mounted) { setState(() { _isLoading = false; }); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(flex: 2),

              Image.asset(
                AppTheme.logoAsset,
                height: 80, // Un logo más sutil y elegante
              ),
              const SizedBox(height: 60.0),

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo Electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24.0),

              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 14.0), textAlign: TextAlign.center),
                ),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: signInAndLoadData,
                        child: const Text('Entrar'),
                      ),
              ),
              const Spacer(flex: 3),
              const Padding(
                padding: EdgeInsets.only(bottom: 24.0),
                child: Text(
                  'Diseñado por Cloud Capture',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}