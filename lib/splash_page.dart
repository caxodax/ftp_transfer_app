// lib/splash_page.dart

import 'package:flutter/material.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            ScaleTransition(
              scale: _pulseAnimation,
              child: Image.asset(
                'assets/splash_logo.png',
                // CAMBIO 1: Aumentamos el tamaño del logo a 250.
                // Puedes ajustar este valor si lo necesitas.
                width: 250,
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 40.0),
              child: Text(
                'Desarrollado por Foxbyte',
                style: TextStyle(
                  // CAMBIO 2: Cambiamos el color a un negro más legible.
                  // Colors.black87 es un negro estándar muy elegante.
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500, // Le damos un poco más de peso
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}