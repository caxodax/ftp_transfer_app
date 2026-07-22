// lib/home_page.dart

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_page.dart';
import 'pendientes_tab.dart';
import 'enviados_tab.dart';
import 'user_data_service.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final userDataService = UserDataService();

  String get _uid => userDataService.userId ?? 'unknown';

  // Key donde guardamos qué archivos de cache (thumbnails) creó este usuario
  String get _thumbCacheListKey => 'thumb_cache_files_$_uid';

  Future<void> _clearUserThumbCache() async {
    final prefs = await SharedPreferences.getInstance();
    final files = prefs.getStringList(_thumbCacheListKey) ?? [];

    for (final path in files) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {
        // ignorar errores individuales
      }
    }

    // limpiar la lista
    await prefs.remove(_thumbCacheListKey);
  }

  Future<void> signOut(BuildContext context) async {
    // 1) limpiar cache del usuario (antes de limpiar userDataService)
    await _clearUserThumbCache();

    // 2) logout auth
    await FirebaseAuth.instance.signOut();

    // 3) limpiar data en memoria
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
