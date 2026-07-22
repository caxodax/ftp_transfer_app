// lib/upload_audit_service.dart
//
// Servicio de auditoría: guarda el resultado de cada lote de subida
// en la colección "upload_batches" de Firestore.
//
// Ahora retorna un AuditSaveResult para que la UI pueda mostrar
// advertencias si Firestore falla (ej. PERMISSION_DENIED).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'ftp_upload_service.dart';
import 'user_data_service.dart';

// ---------------------------------------------------------------------------
// Resultado de la auditoría
// ---------------------------------------------------------------------------

class AuditSaveResult {
  /// Si la auditoría se guardó correctamente en Firestore.
  final bool success;

  /// Mensaje de error si falló (ej: "PERMISSION_DENIED").
  final String? errorMessage;

  const AuditSaveResult({required this.success, this.errorMessage});
}

// ---------------------------------------------------------------------------
// Servicio
// ---------------------------------------------------------------------------

class UploadAuditService {
  final FirebaseFirestore _db;

  UploadAuditService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Guarda en Firestore el resultado completo del lote.
  ///
  /// Retorna un [AuditSaveResult] indicando si se guardó correctamente
  /// y el mensaje de error si falló.
  ///
  /// Estructura del documento en `upload_batches/{auto-id}`:
  /// ```
  /// {
  ///   userId, userEmail, companyId, sentAt,
  ///   status, totalFiles, verifiedCount, duplicateCount, failedCount,
  ///   ftpFolder,
  ///   files: [
  ///     { fileName, remotePath, size, status, verifiedAt, note? }
  ///   ]
  /// }
  /// ```
  Future<AuditSaveResult> saveBatchResult(
    BatchUploadResult result,
    UserDataService userData,
  ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        const msg = 'Usuario no autenticado: no se puede guardar la auditoría.';
        debugPrint('[UploadAuditService] $msg');
        return const AuditSaveResult(success: false, errorMessage: msg);
      }

      final filesPayload = result.files.map((f) {
        final entry = <String, dynamic>{
          'fileName': f.fileName,
          'remotePath': f.remotePath,
          'size': f.localSize,
          'status': f.status.name, // "verified" | "duplicate" | "failed"
          'verifiedAt': Timestamp.fromDate(f.timestamp),
        };
        if (f.note != null) entry['note'] = f.note;
        return entry;
      }).toList();

      final doc = <String, dynamic>{
        'userId': userData.userId,
        'userEmail': currentUser.email,
        'companyId': userData.companyId,
        'sentAt': Timestamp.fromDate(result.sentAt),
        'status': result.status.name, // "success" | "partial" | "failed"
        'totalFiles': result.totalFiles,
        'verifiedCount': result.verifiedCount,
        'duplicateCount': result.duplicateCount,
        'failedCount': result.failedCount,
        'ftpFolder': result.ftpFolder,
        'files': filesPayload,
      };

      await _db.collection('upload_batches').add(doc);
      debugPrint(
        '[UploadAuditService] Lote guardado: '
        '${result.status.name} | '
        'verified=${result.verifiedCount} '
        'duplicate=${result.duplicateCount} '
        'failed=${result.failedCount}',
      );
      return const AuditSaveResult(success: true);
    } catch (e) {
      final errorStr = e.toString();
      String userMessage;

      if (errorStr.contains('PERMISSION_DENIED') ||
          errorStr.contains('permission-denied')) {
        userMessage =
            'Firestore rechazó la escritura (PERMISSION_DENIED). '
            'Las reglas de seguridad no permiten crear documentos en '
            'la colección "upload_batches". Contacta al administrador.';
      } else if (errorStr.contains('UNAVAILABLE') ||
          errorStr.contains('unavailable')) {
        userMessage =
            'Firestore no está disponible. Verifica tu conexión a internet.';
      } else if (errorStr.contains('UNAUTHENTICATED') ||
          errorStr.contains('unauthenticated')) {
        userMessage =
            'Sesión expirada: no se pudo autenticar con Firestore. '
            'Intenta cerrar sesión y volver a iniciar.';
      } else {
        userMessage = 'Error al guardar auditoría en Firestore: $errorStr';
      }

      debugPrint('[UploadAuditService] $userMessage');
      return AuditSaveResult(success: false, errorMessage: userMessage);
    }
  }
}
