// lib/main.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app_theme.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'splash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud Capture App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.globalTheme,
      // La app ahora arranca directamente en el AuthWrapper
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    // Ejecutamos dos futuros en paralelo:
    // 1. Una espera mínima de 2.5 segundos para que el splash se vea.
    // 2. La primera respuesta del estado de autenticación de Firebase.
    final result = await Future.wait([
      Future.delayed(const Duration(milliseconds: 2500)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);

    // Después de que AMBOS futuros se completen, procedemos.
    // El resultado de la autenticación está en result[1].
    final user = result[1] as User?;

    // Usamos 'mounted' para asegurarnos de que el widget todavía existe
    // antes de intentar navegar.
    if (mounted) {
      if (user != null) {
        // Si hay usuario, vamos a HomePage
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomePage()),
        );
      } else {
        // Si no hay usuario, vamos a LoginPage
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mientras la lógica de inicialización se ejecuta,
    // mostramos la SplashPage. Esta es ahora la única responsabilidad
    // de la SplashPage.
    return const SplashPage();
  }
}