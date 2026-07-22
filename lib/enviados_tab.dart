// lib/enviados_tab.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'user_data_service.dart';

class EnviadosTab extends StatefulWidget {
  const EnviadosTab({super.key});

  @override
  EnviadosTabState createState() => EnviadosTabState();
}

class EnviadosTabState extends State<EnviadosTab> {
  Map<String, List<dynamic>> _sentItemsHistory = {};
  bool _isLoading = false;

  // ---- Keys por usuario para evitar mezcla entre cuentas ----
  String get _uid => UserDataService().userId ?? 'unknown';
  String get _sentHistoryKey => 'sent_items_history_$_uid';

  // ---- Lista de archivos de cache (thumbnails) creados por este usuario ----
  String get _thumbCacheListKey => 'thumb_cache_files_$_uid';

  @override
  void initState() {
    super.initState();
    _loadSentHistory();
  }

  Future<void> _loadSentHistory() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final String historyJson = prefs.getString(_sentHistoryKey) ?? '{}';
    final Map<String, dynamic> decodedHistory = jsonDecode(historyJson);

    final sortedKeys = decodedHistory.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final Map<String, List<dynamic>> sortedHistory = {
      for (var k in sortedKeys) k: (decodedHistory[k] as List<dynamic>)
    };

    if (mounted) {
      setState(() {
        _sentItemsHistory = sortedHistory;
        _isLoading = false;
      });
    }
  }

  void _showSentDetailDialog(String date, String fileName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          elevation: 0,
          title: const Text('Detalle del Envío'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Archivo:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(fileName),
              const SizedBox(height: 16),
              const Text('Fecha de Envío:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(date),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cerrar'),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        );
      },
    );
  }

  void _showImagePreview(String date, String fileName) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'preview',
      barrierColor: Colors.black,
      pageBuilder: (ctx, a1, a2) {
        return SafeArea(
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Center(
                  child: FutureBuilder<File>(
                    future: _getThumbnail(date, fileName),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return const Text(
                          'No se pudo cargar la imagen',
                          style: TextStyle(color: Colors.white),
                        );
                      }

                      return InteractiveViewer(
                        clipBehavior: Clip.none,
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 1.0,
                        maxScale: 6.0,
                        boundaryMargin: const EdgeInsets.all(120),
                        child: Image.file(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),
                ),

                // Botón cerrar
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),

                // Texto abajo
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    color: Colors.black.withOpacity(0.45),
                    child: Text(
                      '$date • $fileName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteHistoryEntry(String date, {String? fileName}) async {
    final prefs = await SharedPreferences.getInstance();
    final String historyJson = prefs.getString(_sentHistoryKey) ?? '{}';
    final Map<String, dynamic> history = jsonDecode(historyJson);

    if (fileName != null) {
      (history[date] as List?)?.remove(fileName);
      if ((history[date] as List?)?.isEmpty ?? false) {
        history.remove(date);
      }
    } else {
      history.remove(date);
    }

    await prefs.setString(_sentHistoryKey, jsonEncode(history));
    await _loadSentHistory();
  }

  void _showDeleteHistoryConfirmation(String date, {String? fileName}) {
    final isDeletingFolder = fileName == null;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          elevation: 0,
          title: Text(isDeletingFolder ? 'Borrar Registro de Carpeta' : 'Borrar Registro'),
          content: Text(
            isDeletingFolder
                ? '¿Estás seguro de que quieres borrar el registro de todos los envíos del día $date?\n(Esto no afecta a los archivos en el servidor)'
                : '¿Estás seguro de que quieres borrar el registro del archivo $fileName?\n(Esto no afecta al archivo en el servidor)',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Borrar'),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteHistoryEntry(date, fileName: fileName);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _registerThumbCacheFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_thumbCacheListKey) ?? [];
    if (!list.contains(path)) {
      list.add(path);
      await prefs.setStringList(_thumbCacheListKey, list);
    }
  }

  Future<File> _getThumbnail(String dateFolder, String fileName) async {
    final cacheDir = await getTemporaryDirectory();

    // ✅ Evita colisiones en cache entre fechas
    final safeName = '${dateFolder}__${fileName}'.replaceAll('/', '_');
    final thumbnailFile = File('${cacheDir.path}/$safeName');

    if (await thumbnailFile.exists()) {
      // Registrar (por si viene de una sesión previa y no quedó en la lista)
      await _registerThumbCacheFile(thumbnailFile.path);
      return thumbnailFile;
    }

    final userData = UserDataService();
    final carpeta = userData.carpeta?.trim();

    if (carpeta == null || carpeta.isEmpty) {
      throw Exception('Este usuario no tiene "carpeta" asignada en la BD.');
    }

    final ftpConnect = FTPConnect(
      userData.ftpHost!,
      user: userData.ftpUser!,
      pass: userData.ftpPassword!,
      port: userData.ftpPort!,
      timeout: 30,
    );

    try {
      await ftpConnect.connect();
      await ftpConnect.sendCustomCommand('TYPE I');

      // ✅ NUEVO: /{carpeta}/{dateFolder}/fileName
      await ftpConnect.changeDirectory(carpeta);
      await ftpConnect.changeDirectory(dateFolder);

      await ftpConnect.downloadFile(fileName, thumbnailFile);

      // ✅ Registrar el archivo descargado para limpieza en logout
      await _registerThumbCacheFile(thumbnailFile.path);

      await ftpConnect.disconnect();
      return thumbnailFile;
    } catch (e) {
      try {
        await ftpConnect.disconnect();
      } catch (_) {}
      throw Exception('Failed to download image');
    }
  }

  @override
  Widget build(BuildContext context) {
    final TabController? tabController = DefaultTabController.of(context);
    tabController?.addListener(() {
      if (!tabController.indexIsChanging && tabController.index == 1) {
        _loadSentHistory();
      }
    });

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_sentItemsHistory.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadSentHistory,
        child: Stack(
          children: <Widget>[
            ListView(),
            const Center(
              child: Text(
                'No hay registros de fotos enviadas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSentHistory,
      child: ListView.builder(
        itemCount: _sentItemsHistory.keys.length,
        itemBuilder: (context, index) {
          String date = _sentItemsHistory.keys.elementAt(index);
          List<dynamic> files = _sentItemsHistory[date]!;
          return ExpansionTile(
            collapsedIconColor: Colors.black,
            iconColor: Colors.black,
            title: Text('Envíos del $date (${files.length} fotos)'),
            trailing: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              onPressed: () => _showDeleteHistoryConfirmation(date),
              child: const Text('Borrar'),
            ),
            leading: null,
            children: [
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 4.0,
                    mainAxisSpacing: 4.0,
                  ),
                  itemCount: files.length,
                  itemBuilder: (context, gridIndex) {
                    final fileName = files[gridIndex].toString();
                    return GestureDetector(
                      onTap: () => _showImagePreview(date, fileName),
                      onLongPress: () => _showSentDetailDialog(date, fileName),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: FutureBuilder<File>(
                          future: _getThumbnail(date, fileName),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Container(color: Colors.grey[200]);
                            }
                            if (snapshot.hasError || !snapshot.hasData) {
                              return Container(color: Colors.grey[300]);
                            }
                            return Image.file(snapshot.data!, fit: BoxFit.cover);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
