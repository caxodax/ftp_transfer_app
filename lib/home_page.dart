// lib/home_page.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mi_app_ftp/login_page.dart';
import 'pendientes_tab.dart';
import 'enviados_tab.dart';
import 'user_data_service.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final userDataService = UserDataService();

  Future<void> signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    userDataService.clear();

    // Al cerrar sesión, volvemos manualmente al Login
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ya no necesitamos FutureBuilder. Los datos se cargan antes de llegar aquí.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          // El título ahora debería mostrar el nombre de la compañía directamente.
          title: Text(userDataService.companyName ?? 'Mi App'),
          actions: [
            IconButton(
              onPressed: () => signOut(context),
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar sesión',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.camera_alt), text: 'Pendientes'),
              Tab(icon: Icon(Icons.check_circle), text: 'Enviados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PendientesTab(),
            EnviadosTab(),
          ],
        ),
      ),
    );
  }
}