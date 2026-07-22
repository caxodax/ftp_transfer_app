// lib/user_data_service.dart
// Un Singleton para almacenar la información de la sesión del usuario.
class UserDataService {
  // --- Singleton Setup ---
  static final UserDataService _instance = UserDataService._internal();
  factory UserDataService() {
    return _instance;
  }
  UserDataService._internal();

  // --- Datos de la Sesión ---
  String? companyName;
  String? companyId; // ID del documento en la colección 'companies'
  String? ftpHost;
  String? ftpUser;
  String? ftpPassword;
  int? ftpPort;

  String? userId; // ID del usuario (Firebase Auth UID)
  String? carpeta; // ✅ Carpeta base del usuario (Firestore: users/{uid}.carpeta)

  String? twoFactorSecret; // Clave secreta para 2FA

  // Método para cargar los datos después del login
  void loadData({
    required String companyName,
    required String companyId, // ID del documento en 'companies'
    required String ftpHost,
    required String ftpUser,
    required String ftpPassword,
    required int ftpPort,
    required String userId, // UID
    required String carpeta, // ✅ requerida para el FTP por usuario
    String? twoFactorSecret, // Permitimos que sea nulo inicialmente
  }) {
    this.companyName = companyName;
    this.companyId = companyId;
    this.ftpHost = ftpHost;
    this.ftpUser = ftpUser;
    this.ftpPassword = ftpPassword;
    this.ftpPort = ftpPort;

    this.userId = userId;
    this.carpeta = carpeta;

    this.twoFactorSecret = twoFactorSecret; // Asignamos la clave secreta
  }

  // Método para limpiar los datos al cerrar sesión
  void clear() {
    companyName = null;
    companyId = null;
    ftpHost = null;
    ftpUser = null;
    ftpPassword = null;
    ftpPort = null;

    userId = null;
    carpeta = null;

    twoFactorSecret = null;
  }
}
