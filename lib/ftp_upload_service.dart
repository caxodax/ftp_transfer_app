// lib/ftp_upload_service.dart
//
// Servicio de subida FTP secuencial con:
// - Prueba de conexión explícita (PWD) antes de subir
// - Detección de duplicados por nombre + tamaño
// - Verificación post-subida
// - Resultado individual por archivo y estado global del lote
// - Mensajes de error claros diferenciando conexión / permisos / verificación

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:intl/intl.dart';

import 'user_data_service.dart';

// ---------------------------------------------------------------------------
// Enums de estado
// ---------------------------------------------------------------------------

enum FileUploadStatus {
  /// Subido y confirmado en el servidor (tamaño coincide).
  verified,

  /// Ya existía con el mismo nombre y tamaño: se considera resuelto.
  duplicate,

  /// Error en cualquier paso: no resuelto, queda en pendientes.
  failed,
}

enum BatchUploadStatus {
  /// Todos los archivos están resueltos (verified o duplicate).
  success,

  /// Algunos resueltos, otros fallidos.
  partial,

  /// Ningún archivo quedó resuelto.
  failed,
}

// ---------------------------------------------------------------------------
// Modelos de resultado
// ---------------------------------------------------------------------------

class FileUploadResult {
  final String fileName;
  final String remotePath;
  final int localSize;
  final FileUploadStatus status;
  final DateTime timestamp;

  /// Información adicional: motivo de fallo, detalle de duplicado, etc.
  final String? note;

  const FileUploadResult({
    required this.fileName,
    required this.remotePath,
    required this.localSize,
    required this.status,
    required this.timestamp,
    this.note,
  });
}

class BatchUploadResult {
  final List<FileUploadResult> files;

  /// Ruta remota relativa del directorio donde se subieron los archivos.
  /// Formato: "{carpeta}/{yyyy-MM-dd}"
  final String ftpFolder;

  /// Solo la fecha, para compatibilidad con el historial de SharedPreferences.
  final String dateDir;

  final DateTime sentAt;

  /// Mensaje de error de conexión a nivel de lote (si aplica).
  final String? connectionError;

  const BatchUploadResult({
    required this.files,
    required this.ftpFolder,
    required this.dateDir,
    required this.sentAt,
    this.connectionError,
  });

  int get totalFiles => files.length;

  int get verifiedCount =>
      files.where((f) => f.status == FileUploadStatus.verified).length;

  int get duplicateCount =>
      files.where((f) => f.status == FileUploadStatus.duplicate).length;

  int get failedCount =>
      files.where((f) => f.status == FileUploadStatus.failed).length;

  BatchUploadStatus get status {
    if (failedCount == 0) return BatchUploadStatus.success;
    if (verifiedCount + duplicateCount == 0) return BatchUploadStatus.failed;
    return BatchUploadStatus.partial;
  }

  /// Nombres de archivos resueltos (verified + duplicate).
  /// Estos son los que deben eliminarse de pendientes.
  List<String> get resolvedFileNames => files
      .where((f) =>
          f.status == FileUploadStatus.verified ||
          f.status == FileUploadStatus.duplicate)
      .map((f) => f.fileName)
      .toList();
}

// ---------------------------------------------------------------------------
// Servicio principal
// ---------------------------------------------------------------------------

class FtpUploadService {
  /// Sube una lista de rutas locales de forma secuencial.
  ///
  /// Por cada archivo:
  ///   1. Verifica si ya existe en el FTP (duplicado).
  ///   2. Si no existe, lo sube.
  ///   3. Verifica la subida comparando tamaño.
  ///
  /// [onProgress] recibe mensajes de estado para mostrar en la UI.
  Future<BatchUploadResult> uploadBatch({
    required List<String> localPaths,
    required UserDataService userData,
    void Function(String message)? onProgress,
  }) async {
    final dateDir = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final carpeta = userData.carpeta!.trim();
    final ftpFolder = '$carpeta/$dateDir';
    final sentAt = DateTime.now();

    final ftpConnect = FTPConnect(
      userData.ftpHost!,
      user: userData.ftpUser!,
      pass: userData.ftpPassword!,
      port: userData.ftpPort!,
      timeout: 30,
    );

    final List<FileUploadResult> results = [];
    String? connectionError;

    try {
      // ── Paso 0: Conectar y verificar sesión ──────────────────────────────
      onProgress?.call('Conectando al servidor FTP...');
      await ftpConnect.connect();

      // Verificar que la sesión está activa con PWD
      onProgress?.call('Verificando sesión FTP...');
      final pwdResponse = await ftpConnect.sendCustomCommand('PWD');
      debugPrint('[FtpUploadService] PWD response: $pwdResponse');

      // Forzar modo binario para transferencias
      await ftpConnect.sendCustomCommand('TYPE I');

      // Intentar activar modo pasivo explícitamente
      try {
        await ftpConnect.sendCustomCommand('PASV');
        debugPrint('[FtpUploadService] Modo pasivo activado');
      } catch (e) {
        debugPrint('[FtpUploadService] PASV no soportado o ya activo: $e');
      }

      // Navegar / crear carpeta de usuario
      onProgress?.call('Preparando directorio remoto...');
      try {
        await ftpConnect.createFolderIfNotExist(carpeta);
        await ftpConnect.changeDirectory(carpeta);
      } catch (e) {
        throw _FtpPermissionException(
          'No se pudo crear o acceder a la carpeta "$carpeta". '
          'Verifica que la cuenta FTP tenga permisos de escritura. '
          'Detalle: ${e.toString()}',
        );
      }

      // Navegar / crear carpeta de fecha
      try {
        await ftpConnect.createFolderIfNotExist(dateDir);
        await ftpConnect.changeDirectory(dateDir);
      } catch (e) {
        throw _FtpPermissionException(
          'No se pudo crear o acceder a la carpeta de fecha "$dateDir" '
          'dentro de "$carpeta". Verifica permisos de escritura. '
          'Detalle: ${e.toString()}',
        );
      }

      // Verificar que realmente estamos en el directorio correcto
      final currentDir = await ftpConnect.currentDirectory();
      debugPrint('[FtpUploadService] Directorio actual: $currentDir');

      // Listado inicial para detectar duplicados
      onProgress?.call('Verificando archivos existentes en el servidor...');
      var remoteEntries = await _listSafe(ftpConnect);

      for (int i = 0; i < localPaths.length; i++) {
        final localPath = localPaths[i];
        final fileName = _baseName(localPath);
        final remotePath = '/$ftpFolder/$fileName';
        final file = File(localPath);

        late int localSize;
        try {
          localSize = await file.length();
        } catch (_) {
          // Si no podemos leer el archivo, fallamos directamente
          results.add(FileUploadResult(
            fileName: fileName,
            remotePath: remotePath,
            localSize: 0,
            status: FileUploadStatus.failed,
            timestamp: DateTime.now(),
            note: 'No se pudo leer el archivo local.',
          ));
          continue;
        }

        onProgress?.call(
          'Procesando ${i + 1}/${localPaths.length}: $fileName',
        );

        try {
          // ── Paso 1: Verificar si existe en el servidor ──────────────────
          final existing = _findEntry(remoteEntries, fileName);

          if (existing != null) {
            if (existing.size == localSize) {
              // Duplicado válido: mismo nombre, mismo tamaño, misma carpeta
              results.add(FileUploadResult(
                fileName: fileName,
                remotePath: remotePath,
                localSize: localSize,
                status: FileUploadStatus.duplicate,
                timestamp: DateTime.now(),
                note:
                    'El archivo ya existía en el servidor con el mismo nombre y tamaño.',
              ));
              continue;
            } else {
              // Existe pero con tamaño distinto → conflicto, NO sobrescribir
              results.add(FileUploadResult(
                fileName: fileName,
                remotePath: remotePath,
                localSize: localSize,
                status: FileUploadStatus.failed,
                timestamp: DateTime.now(),
                note:
                    'Conflicto: el archivo ya existe en el servidor pero '
                    'con un tamaño distinto '
                    '(local: $localSize bytes, remoto: ${existing.size} bytes). '
                    'No se sobrescribió.',
              ));
              continue;
            }
          }

          // ── Paso 2: Subir archivo ───────────────────────────────────────
          onProgress?.call(
            'Subiendo ${i + 1}/${localPaths.length}: $fileName',
          );

          bool uploadSuccess = false;
          try {
            uploadSuccess = await ftpConnect.uploadFile(file);
          } catch (e) {
            results.add(FileUploadResult(
              fileName: fileName,
              remotePath: remotePath,
              localSize: localSize,
              status: FileUploadStatus.failed,
              timestamp: DateTime.now(),
              note:
                  'FTP: la subida lanzó una excepción. '
                  'Esto puede indicar un problema de permisos o conexión interrumpida. '
                  'Detalle: ${e.toString()}',
            ));
            continue;
          }

          if (!uploadSuccess) {
            results.add(FileUploadResult(
              fileName: fileName,
              remotePath: remotePath,
              localSize: localSize,
              status: FileUploadStatus.failed,
              timestamp: DateTime.now(),
              note:
                  'FTP: uploadFile() devolvió false. '
                  'La transferencia no se completó. Posibles causas: '
                  'permisos insuficientes, disco lleno en el servidor, '
                  'o conexión inestable.',
            ));
            continue;
          }

          // ── Paso 3: Verificar la subida con nuevo listado ───────────────
          onProgress?.call(
            'Verificando ${i + 1}/${localPaths.length}: $fileName',
          );
          remoteEntries = await _listSafe(ftpConnect);
          final uploaded = _findEntry(remoteEntries, fileName);

          if (uploaded == null) {
            // Intentar un segundo listado después de una breve pausa
            debugPrint(
              '[FtpUploadService] Archivo no encontrado en primer intento, '
              'reintentando listado...',
            );
            await Future.delayed(const Duration(seconds: 2));
            remoteEntries = await _listSafe(ftpConnect);
            final retryUploaded = _findEntry(remoteEntries, fileName);

            if (retryUploaded == null) {
              results.add(FileUploadResult(
                fileName: fileName,
                remotePath: remotePath,
                localSize: localSize,
                status: FileUploadStatus.failed,
                timestamp: DateTime.now(),
                note:
                    'FTP: conexión exitosa pero la subida falló. '
                    'El archivo no aparece en el servidor tras dos verificaciones. '
                    'Causas probables: la cuenta FTP no tiene permiso de escritura '
                    'en la carpeta "$carpeta/$dateDir", o el servidor rechazó '
                    'silenciosamente la transferencia.',
              ));
            } else if (retryUploaded.size == localSize) {
              results.add(FileUploadResult(
                fileName: fileName,
                remotePath: remotePath,
                localSize: localSize,
                status: FileUploadStatus.verified,
                timestamp: DateTime.now(),
                note: 'Verificado en segundo intento (latencia del servidor).',
              ));
            } else {
              results.add(FileUploadResult(
                fileName: fileName,
                remotePath: remotePath,
                localSize: localSize,
                status: FileUploadStatus.failed,
                timestamp: DateTime.now(),
                note:
                    'El archivo se subió pero el tamaño no coincide '
                    '(local: $localSize bytes, remoto: ${retryUploaded.size} bytes). '
                    'Posible transferencia incompleta.',
              ));
            }
          } else if (uploaded.size == localSize) {
            results.add(FileUploadResult(
              fileName: fileName,
              remotePath: remotePath,
              localSize: localSize,
              status: FileUploadStatus.verified,
              timestamp: DateTime.now(),
            ));
          } else {
            // Tamaño no coincide post-subida (posible corrupción)
            results.add(FileUploadResult(
              fileName: fileName,
              remotePath: remotePath,
              localSize: localSize,
              status: FileUploadStatus.failed,
              timestamp: DateTime.now(),
              note:
                  'El archivo se subió pero el tamaño no coincide '
                  '(local: $localSize bytes, remoto: ${uploaded.size} bytes). '
                  'Posible transferencia incompleta.',
            ));
          }
        } catch (e) {
          results.add(FileUploadResult(
            fileName: fileName,
            remotePath: remotePath,
            localSize: localSize,
            status: FileUploadStatus.failed,
            timestamp: DateTime.now(),
            note: 'Error al procesar el archivo: ${e.toString()}',
          ));
        }
      }
    } on _FtpPermissionException catch (e) {
      // Error de permisos al crear/navegar carpetas
      connectionError = e.message;
      final processedNames = results.map((r) => r.fileName).toSet();
      for (final localPath in localPaths) {
        final fileName = _baseName(localPath);
        if (!processedNames.contains(fileName)) {
          final file = File(localPath);
          int sz = 0;
          try {
            sz = await file.length();
          } catch (_) {}
          results.add(FileUploadResult(
            fileName: fileName,
            remotePath: '/$ftpFolder/$fileName',
            localSize: sz,
            status: FileUploadStatus.failed,
            timestamp: DateTime.now(),
            note: 'Error de permisos FTP: ${e.message}',
          ));
        }
      }
    } on SocketException catch (e) {
      // Error de red / DNS / timeout
      connectionError =
          'Error de conexión de red: no se pudo conectar al servidor FTP. '
          'Verifica tu conexión a internet y que el host/puerto sean correctos. '
          'Detalle: ${e.message}';
      final processedNames = results.map((r) => r.fileName).toSet();
      for (final localPath in localPaths) {
        final fileName = _baseName(localPath);
        if (!processedNames.contains(fileName)) {
          final file = File(localPath);
          int sz = 0;
          try {
            sz = await file.length();
          } catch (_) {}
          results.add(FileUploadResult(
            fileName: fileName,
            remotePath: '/$ftpFolder/$fileName',
            localSize: sz,
            status: FileUploadStatus.failed,
            timestamp: DateTime.now(),
            note: connectionError!,
          ));
        }
      }
    } catch (e) {
      // Fallo genérico a nivel de conexión
      final errorStr = e.toString();
      if (errorStr.contains('530') || errorStr.contains('Login')) {
        connectionError =
            'Credenciales FTP inválidas: el servidor rechazó el usuario o '
            'contraseña. Verifica los datos de conexión en tu perfil.';
      } else if (errorStr.contains('Connection refused') ||
          errorStr.contains('timed out')) {
        connectionError =
            'No se pudo conectar al servidor FTP. '
            'El servidor puede estar caído o el puerto es incorrecto.';
      } else {
        connectionError = 'Error de conexión FTP: $errorStr';
      }

      final processedNames = results.map((r) => r.fileName).toSet();
      for (final localPath in localPaths) {
        final fileName = _baseName(localPath);
        if (!processedNames.contains(fileName)) {
          final file = File(localPath);
          int sz = 0;
          try {
            sz = await file.length();
          } catch (_) {}
          results.add(FileUploadResult(
            fileName: fileName,
            remotePath: '/$ftpFolder/$fileName',
            localSize: sz,
            status: FileUploadStatus.failed,
            timestamp: DateTime.now(),
            note: connectionError!,
          ));
        }
      }
    } finally {
      try {
        await ftpConnect.disconnect();
      } catch (e) {
        debugPrint('[FtpUploadService] Error al desconectar: $e');
      }
    }

    return BatchUploadResult(
      files: results,
      ftpFolder: ftpFolder,
      dateDir: dateDir,
      sentAt: sentAt,
      connectionError: connectionError,
    );
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  /// Lista el directorio actual silenciando errores (ej. directorio vacío).
  Future<List<FTPEntry>> _listSafe(FTPConnect ftp) async {
    try {
      return await ftp.listDirectoryContent();
    } catch (e) {
      debugPrint('[FtpUploadService] listDirectoryContent falló: $e');
      return [];
    }
  }

  /// Busca una entrada por nombre en la lista remota.
  FTPEntry? _findEntry(List<FTPEntry> entries, String name) {
    try {
      return entries.firstWhere((e) => e.name == name);
    } catch (_) {
      return null;
    }
  }

  /// Extrae el nombre de archivo de una ruta completa.
  String _baseName(String path) {
    // Compatible con separadores Unix y Windows
    return path.split(RegExp(r'[/\\]')).last;
  }
}

// ---------------------------------------------------------------------------
// Excepción interna para diferenciar errores de permisos
// ---------------------------------------------------------------------------

class _FtpPermissionException implements Exception {
  final String message;
  _FtpPermissionException(this.message);

  @override
  String toString() => message;
}
