// lib/home_page.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'pendientes_tab.dart'; // Asegúrate de que este archivo exista
import 'enviados_tab.dart';
import 'user_data_service.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final userDataService = UserDataService();

  Future<void> signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    userDataService.clear();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
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
              // Se elimina el atributo 'icon' de las pestañas
              Tab(text: 'Pendientes'),
              Tab(text: 'Enviados'),
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