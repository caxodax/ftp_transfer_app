// lib/user_data_service.dart

// Un Singleton para almacenar la información de la sesión del usuario.
class UserDataService {
  // --- Singleton Setup ---
  // Esto asegura que solo exista una instancia de esta clase en toda la app.
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

  // Método para cargar los datos después del login
  void loadData({
    required String companyName,
    required String ftpHost,
    required String ftpUser,
    required String ftpPassword,
    required int ftpPort,
  }) {
    this.companyName = companyName;
    this.ftpHost = ftpHost;
    this.ftpUser = ftpUser;
    this.ftpPassword = ftpPassword;
    this.ftpPort = ftpPort;
  }

  // Método para limpiar los datos al cerrar sesión
  void clear() {
    companyName = null;
    ftpHost = null;
    ftpUser = null;
    ftpPassword = null;
    ftpPort = null;
  }
}