// lib/main.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app_theme.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Cierra sesión SOLO en arranques en frío (cuando el proceso inicia).
  // Si la app se fue a segundo plano y vuelve, este código NO se ejecuta de nuevo,
  // por lo que la sesión se mantiene en ese caso.
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {
    // Si hubiera algún error cerrando sesión, continuamos igual.
  }

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
      // La app arranca en el AuthWrapper (mostrando el Splash mientras decide)
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
    // 1) Una espera mínima de 2.5s para que el splash se vea.
    // 2) La primera respuesta del estado de autenticación de Firebase.
    final result = await Future.wait([
      Future.delayed(const Duration(milliseconds: 2500)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);

    // Resultado de autenticación en result[1]
    final user = result[1] as User?;

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
    // Mientras se ejecuta la lógica de inicialización,
    // mostramos la SplashPage.
    return const SplashPage();
  }
}
