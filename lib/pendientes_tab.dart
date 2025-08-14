// lib/pendientes_tab.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'user_data_service.dart';

class PendientesTab extends StatefulWidget {
  const PendientesTab({super.key});

  @override
  PendientesTabState createState() => PendientesTabState();
}

class PendientesTabState extends State<PendientesTab> {
  List<String> _pendingImagePaths = [];
  final List<String> _selectedImagePaths = [];
  bool _isUploading = false;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadPendingImages();
  }

  Future<void> _loadPendingImages() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pendingImagePaths = prefs.getStringList('pending_images') ?? [];
    });
  }

  Future<void> _savePendingImages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pending_images', _pendingImagePaths);
  }

  Future<void> _recordSentItem(String date, String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    final String existingHistoryJson = prefs.getString('sent_items_history') ?? '{}';
    final Map<String, dynamic> history = jsonDecode(existingHistoryJson);
    if (history[date] == null) { history[date] = []; }
    (history[date] as List).add(fileName);
    final String updatedHistoryJson = jsonEncode(history);
    await prefs.setString('sent_items_history', updatedHistoryJson);
  }

  Future<int> _getNextPhotoNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final String todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String lastDate = prefs.getString('photo_counter_date') ?? '';
    int nextNumber;
    if (lastDate == todayString) {
      nextNumber = (prefs.getInt('photo_counter_number') ?? 0) + 1;
    } else {
      nextNumber = 1;
    }
    await prefs.setString('photo_counter_date', todayString);
    await prefs.setInt('photo_counter_number', nextNumber);
    return nextNumber;
  }

  Future<void> _takePhoto() async {
    if (_isUploading) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );

    if (pickedFile != null) {
      final int photoNumber = await _getNextPhotoNumber();
      final String datePrefix = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String newFileName = '${datePrefix}_$photoNumber.jpg';
      final imageBytes = await pickedFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes)!;
      final thumbnail = img.copyResize(originalImage, width: 200);
      final cacheDir = await getTemporaryDirectory();
      final thumbnailPath = '${cacheDir.path}/$newFileName';
      await File(thumbnailPath).writeAsBytes(img.encodeJpg(thumbnail, quality: 85));
      final Directory directory = Directory(pickedFile.path).parent;
      final String newPath = '${directory.path}/$newFileName';
      final File renamedFile = await File(pickedFile.path).rename(newPath);
      setState(() {
        _pendingImagePaths.add(renamedFile.path);
      });
      await _savePendingImages();
    }
  }

  void _toggleSelection(String path) {
    if (_isUploading) return;
    setState(() {
      if (_selectedImagePaths.contains(path)) {
        _selectedImagePaths.remove(path);
      } else {
        _selectedImagePaths.add(path);
      }
    });
  }

  Future<void> _deletePaths(List<String> pathsToDelete) async {
    setState(() {
      _pendingImagePaths.removeWhere((path) => pathsToDelete.contains(path));
      _selectedImagePaths.removeWhere((path) => pathsToDelete.contains(path));
    });
    await _savePendingImages();
    try {
      for (final path in pathsToDelete) {
        final fileName = path.split('/').last;
        final fileToDelete = File(path);
        if (await fileToDelete.exists()) await fileToDelete.delete();
        final cacheDir = await getTemporaryDirectory();
        final thumbnailToDelete = File('${cacheDir.path}/$fileName');
        if (await thumbnailToDelete.exists()) await thumbnailToDelete.delete();
      }
    } catch (e) {}
  }

  void _showDeleteConfirmation(String path) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Borrado'),
          content: const Text('¿Estás seguro de que quieres eliminar esta foto?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
              child: const Text('Borrar'),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePaths([path]);
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteSelectedConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Borrado Múltiple'),
          content: Text('¿Estás seguro de que quieres eliminar las ${_selectedImagePaths.length} fotos seleccionadas?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
              child: const Text('Borrar'),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePaths(List.from(_selectedImagePaths));
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadSelectedImages() async {
    if (_selectedImagePaths.isEmpty) return;
    setState(() {
      _isUploading = true;
      _uploadStatus = 'Iniciando conexión...';
    });
    final userData = UserDataService();
    final ftpConnect = FTPConnect(userData.ftpHost!, user: userData.ftpUser!, pass: userData.ftpPassword!, port: userData.ftpPort!, timeout: 20);
    try {
      await ftpConnect.connect();
      await ftpConnect.sendCustomCommand('TYPE I');
      final String dirName = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await ftpConnect.createFolderIfNotExist(dirName);
      await ftpConnect.changeDirectory(dirName);
      for (int i = 0; i < _selectedImagePaths.length; i++) {
        final path = _selectedImagePaths[i];
        final file = File(path);
        final fileName = path.split('/').last;
        setState(() {
          _uploadStatus = 'Subiendo ${i + 1}/${_selectedImagePaths.length}: $fileName';
        });
        await ftpConnect.uploadFile(file);
        await _recordSentItem(dirName, fileName);
      }
      setState(() {
        _pendingImagePaths.removeWhere((path) => _selectedImagePaths.contains(path));
        _selectedImagePaths.clear();
        _uploadStatus = '¡Subida completada con éxito!';
      });
      await _savePendingImages();
    } catch (e) {
      setState(() {
        _uploadStatus = 'Error durante la subida: ${e.toString()}';
      });
    } finally {
      await ftpConnect.disconnect();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadStatus = '';
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50.0),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // CAMBIO: El botón de borrar ahora es de texto para mayor simpleza
          actions: [
            if (_selectedImagePaths.isNotEmpty && !_isUploading)
              TextButton(
                onPressed: _showDeleteSelectedConfirmation,
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
                child: const Text('Borrar Sel.'),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(children: [const CircularProgressIndicator(), const SizedBox(height: 10), Text(_uploadStatus, textAlign: TextAlign.center)]),
            ),
          Expanded(
            child: _pendingImagePaths.isEmpty
                ? const Center(child: Text('Aún no hay fotos pendientes.\n¡Usa la cámara para añadir una!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.grey)))
                : GridView.builder(
                    padding: const EdgeInsets.all(4.0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4.0, mainAxisSpacing: 4.0),
                    itemCount: _pendingImagePaths.length,
                    itemBuilder: (context, index) {
                      final imagePath = _pendingImagePaths[index];
                      final isSelected = _selectedImagePaths.contains(imagePath);
                      return GestureDetector(
                        onTap: () => _toggleSelection(imagePath),
                        onLongPress: () => _showDeleteConfirmation(imagePath),
                        // CAMBIO: Se usa un Container en lugar de Card para un look más simple
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300, width: 0.5),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(imagePath), fit: BoxFit.cover),
                              // CAMBIO: Se simplifica el overlay de selección
                              if (isSelected)
                                Container(
                                  color: Colors.black.withOpacity(0.6),
                                  child: Center(
                                    child: Text(
                                      'SEL',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // CAMBIO: El botón de enviar ahora es un ElevatedButton estándar
          if (_selectedImagePaths.isNotEmpty && !_isUploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _uploadSelectedImages,
                  child: Text('Enviar (${_selectedImagePaths.length})'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePhoto,
        tooltip: 'Tomar Foto',
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}