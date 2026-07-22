// lib/pendientes_tab.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'ftp_upload_service.dart';
import 'upload_audit_service.dart';
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

  // ---- Keys por usuario para evitar mezcla entre cuentas ----
  String get _uid => UserDataService().userId ?? 'unknown';

  String get _pendingKey => 'pending_images_$_uid';
  String get _sentHistoryKey => 'sent_items_history_$_uid';
  String get _counterDateKey => 'photo_counter_date_$_uid';
  String get _counterNumberKey => 'photo_counter_number_$_uid';

  @override
  void initState() {
    super.initState();
    _loadPendingImages();
  }

  Future<void> _loadPendingImages() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pendingImagePaths = prefs.getStringList(_pendingKey) ?? [];
    });
  }

  Future<void> _savePendingImages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingKey, _pendingImagePaths);
  }

  Future<void> _recordSentItem(String date, String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    final String existingHistoryJson = prefs.getString(_sentHistoryKey) ?? '{}';
    final Map<String, dynamic> history = jsonDecode(existingHistoryJson);

    history.putIfAbsent(date, () => []);
    final list = (history[date] as List);

    // Evitar duplicados
    if (!list.contains(fileName)) {
      list.add(fileName);
    }

    final String updatedHistoryJson = jsonEncode(history);
    await prefs.setString(_sentHistoryKey, updatedHistoryJson);
  }

  Future<int> _getNextPhotoNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final String todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String lastDate = prefs.getString(_counterDateKey) ?? '';
    int nextNumber;

    if (lastDate == todayString) {
      nextNumber = (prefs.getInt(_counterNumberKey) ?? 0) + 1;
    } else {
      nextNumber = 1;
    }

    await prefs.setString(_counterDateKey, todayString);
    await prefs.setInt(_counterNumberKey, nextNumber);
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

      // Crear thumbnail en cache temporal
      final imageBytes = await pickedFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes)!;
      final thumbnail = img.copyResize(originalImage, width: 200);
      final cacheDir = await getTemporaryDirectory();
      final thumbnailPath = '${cacheDir.path}/$newFileName';
      await File(thumbnailPath).writeAsBytes(img.encodeJpg(thumbnail, quality: 85));

      // Renombrar en el mismo directorio del picker
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
        if (await thumbnailToDelete.exists()) {
          await thumbnailToDelete.delete();
        }
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
          content: Text(
            '¿Estás seguro de que quieres eliminar las ${_selectedImagePaths.length} fotos seleccionadas?',
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

    final userData = UserDataService();
    final carpeta = userData.carpeta?.trim();

    if (carpeta == null || carpeta.isEmpty) {
      setState(() {
        _uploadStatus =
            'Error: este usuario no tiene "carpeta" asignada en la BD.';
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _uploadStatus = '');
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Iniciando proceso...';
    });

    final List<String> pathsToProcess = List.from(_selectedImagePaths);

    // Ejecutar subida secuencial con verificación y detección de duplicados
    final result = await FtpUploadService().uploadBatch(
      localPaths: pathsToProcess,
      userData: userData,
      onProgress: (msg) {
        if (mounted) setState(() => _uploadStatus = msg);
      },
    );

    // Guardar auditoría en Firestore
    final auditResult = await UploadAuditService().saveBatchResult(result, userData);

    // Registrar en historial local (SharedPrefs) los archivos resueltos
    // para que aparezcan en la pestaña "Enviados"
    for (final fileResult in result.files) {
      if (fileResult.status == FileUploadStatus.verified ||
          fileResult.status == FileUploadStatus.duplicate) {
        await _recordSentItem(result.dateDir, fileResult.fileName);
      }
    }

    // Eliminación selectiva: solo quitar de pendientes los resueltos
    final resolvedNames = result.resolvedFileNames.toSet();
    setState(() {
      _pendingImagePaths.removeWhere(
        (path) => resolvedNames.contains(_baseName(path)),
      );
      _selectedImagePaths.removeWhere(
        (path) => resolvedNames.contains(_baseName(path)),
      );
    });
    await _savePendingImages();

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });
      // Mostrar resumen del lote al usuario
      _showUploadResult(result, auditResult);
    }
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  /// Extrae el nombre de archivo de una ruta completa.
  String _baseName(String path) =>
      path.split(RegExp(r'[/\\]')).last;

  // ── Diálogo de resultado del lote ─────────────────────────────────────────

  void _showUploadResult(BatchUploadResult result, AuditSaveResult auditResult) {
    final statusIcon = switch (result.status) {
      BatchUploadStatus.success => const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF2ECC71),
          size: 52,
        ),
      BatchUploadStatus.partial => const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFF39C12),
          size: 52,
        ),
      BatchUploadStatus.failed => const Icon(
          Icons.cancel_rounded,
          color: Color(0xFFE74C3C),
          size: 52,
        ),
    };

    final statusTitle = switch (result.status) {
      BatchUploadStatus.success => 'Envio completado',
      BatchUploadStatus.partial => 'Envio parcial',
      BatchUploadStatus.failed => 'Envio fallido',
    };

    final failedFiles = result.files
        .where((f) => f.status == FileUploadStatus.failed)
        .toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Column(
          children: [
            statusIcon,
            const SizedBox(height: 8),
            Text(
              statusTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resumen numérico
            _ResultRow(
              icon: Icons.folder_rounded,
              label: 'Total procesados',
              value: '${result.totalFiles}',
            ),
            _ResultRow(
              icon: Icons.cloud_done_rounded,
              iconColor: const Color(0xFF2ECC71),
              label: 'Verificados en servidor',
              value: '${result.verifiedCount}',
            ),
            _ResultRow(
              icon: Icons.copy_rounded,
              iconColor: const Color(0xFF3498DB),
              label: 'Duplicados (ya existían)',
              value: '${result.duplicateCount}',
            ),
            _ResultRow(
              icon: Icons.error_outline_rounded,
              iconColor: const Color(0xFFE74C3C),
              label: 'Fallidos (quedan pendientes)',
              value: '${result.failedCount}',
            ),
            
            // Advertencia de Firebase
            if (!auditResult.success) ...[
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Advertencia de Auditoría',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            auditResult.errorMessage ?? 'No se pudo guardar la auditoría en Firestore.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Connection Error de FTP
            if (result.connectionError != null) ...[
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                             'Error de Conexión FTP',
                             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                          ),
                          const SizedBox(height: 4),
                          Text(
                             result.connectionError!,
                             style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Detalle de fallidos
            if (failedFiles.isNotEmpty) ...[
              const Divider(height: 20),
              const Text(
                'Detalle de errores:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: failedFiles.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          if (f.note != null)
                            Text(
                              f.note!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
  void _showImagePreview(String path) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final bool isSelected = _selectedImagePaths.contains(path);
        return Dialog(
          insetPadding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  path.split('/').last,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _toggleSelection(path);
                    },
                    icon: Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    ),
                    label: Text(isSelected ? 'Quitar selección' : 'Seleccionar'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showDeleteConfirmation(path);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Borrar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // "Seleccionar todo"
  void _onSelectAllChanged(bool? value) {
    if (value == null) return;
    setState(() {
      if (value) {
        _selectedImagePaths
          ..clear()
          ..addAll(_pendingImagePaths);
      } else {
        _selectedImagePaths.clear();
      }
    });
  }

  bool get _isAllSelected =>
      _pendingImagePaths.isNotEmpty && _selectedImagePaths.length == _pendingImagePaths.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50.0),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.red),
            tooltip: 'Tomar Foto',
            onPressed: _isUploading ? null : _takePhoto,
          ),
          actions: [
            if (_selectedImagePaths.isNotEmpty && !_isUploading)
              TextButton(
                onPressed: _showDeleteSelectedConfirmation,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
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
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(
                    _uploadStatus,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          if (!_isUploading && _uploadStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                _uploadStatus,
                textAlign: TextAlign.center,
              ),
            ),
          if (_pendingImagePaths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Checkbox(
                    value: _isAllSelected,
                    onChanged: _isUploading ? null : _onSelectAllChanged,
                  ),
                  const Text('Seleccionar todo'),
                ],
              ),
            ),
          Expanded(
            child: _pendingImagePaths.isEmpty
                ? const Center(
                    child: Text(
                      'Aún no hay fotos pendientes.\n¡Usa la cámara para añadir una!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8.0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8.0,
                      mainAxisSpacing: 8.0,
                      childAspectRatio: 3 / 4,
                    ),
                    itemCount: _pendingImagePaths.length,
                    itemBuilder: (context, index) {
                      final imagePath = _pendingImagePaths[index];
                      final isSelected = _selectedImagePaths.contains(imagePath);

                      return GestureDetector(
                        onTap: () {
                          if (isSelected) {
                            _toggleSelection(imagePath);
                          } else {
                            _showImagePreview(imagePath);
                          }
                        },
                        onLongPress: () => _toggleSelection(imagePath),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(imagePath),
                                fit: BoxFit.cover,
                              ),
                              if (isSelected)
                                Container(
                                  color: Colors.black.withOpacity(0.6),
                                  child: const Center(
                                    child: Text(
                                      'SEL',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 24,
                                      ),
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
        ],
      ),
      bottomNavigationBar: (_selectedImagePaths.isNotEmpty && !_isUploading)
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _uploadSelectedImages,
                    child: Text('Enviar (${_selectedImagePaths.length})'),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: null,
    );
  }
}

// ---------------------------------------------------------------------------
// Widget auxiliar para las filas del resumen de resultado
// ---------------------------------------------------------------------------

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;

  const _ResultRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
