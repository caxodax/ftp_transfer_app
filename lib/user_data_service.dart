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
  String? ftpHost;
  String? ftpUser;
  String? ftpPassword;
  int? ftpPort;
  String? userId; // Agregamos el ID del usuario
  String? twoFactorSecret; // Clave secreta para 2FA

  // Método para cargar los datos después del login
  void loadData({
    required String companyName,
    required String ftpHost,
    required String ftpUser,
    required String ftpPassword,
    required int ftpPort,
    required String userId, // Ahora requerimos el userId
    String? twoFactorSecret, // Permitimos que sea nulo inicialmente
  }) {
    this.companyName = companyName;
    this.ftpHost = ftpHost;
    this.ftpUser = ftpUser;
    this.ftpPassword = ftpPassword;
    this.ftpPort = ftpPort;
    this.userId = userId;
    this.twoFactorSecret = twoFactorSecret; // Asignamos la clave secreta
  }

  // Método para limpiar los datos al cerrar sesión
  void clear() {
    companyName = null;
    ftpHost = null;
    ftpUser = null;
    ftpPassword = null;
    ftpPort = null;
    userId = null;
    twoFactorSecret = null;
  }
}