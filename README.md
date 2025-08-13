# 📸 Cloud Capture: La Plataforma Inteligente de Captura de Datos en Campo

![Versión](https://img.shields.io/badge/versión-1.0.0-blue.svg)
![Plataforma](https://img.shields.io/badge/plataforma-Android-green.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-Full%20Suite-FFA611?logo=firebase)

En un mundo donde los datos son el activo más valioso, ¿cómo verificas que el trabajo en campo se está realizando correctamente y en el lugar exacto? ¿Cómo transformas una simple fotografía en una prueba irrefutable y un dato procesable para tu negocio?

**Cloud Capture** no es solo una aplicación para tomar fotos. Es el puente entre tus operaciones de campo y tu centro de mando digital. Es una herramienta diseñada para dar certeza, velocidad y control a empresas con equipos distribuidos, donde cada captura es un registro verificado que se integra fluidamente en el flujo de trabajo de la compañía.

Esta plataforma fue concebida como una solución de marca blanca ("White-Label"), lista para ser adaptada a la identidad de cualquier corporación, siendo **OXXO** nuestro caso de uso principal para la v1.0.

---

## ✨ La Magia Detrás de Cámaras: Funcionalidades Clave

Cloud Capture v1.0 está construido sobre una base sólida y escalable, enfocada en la seguridad y la eficiencia del usuario.

*   🔐 **Autenticación Robusta y Segura:** Utilizamos **Firebase Authentication** para gestionar el acceso, garantizando que solo el personal autorizado pueda utilizar la aplicación.

*   🏢 **Gestión Centralizada en la Nube:** Olvídate de configuraciones manuales. Con **Cloud Firestore**, los administradores pueden gestionar usuarios, compañías y credenciales FTP de forma remota, aplicando cambios a toda la flota de dispositivos al instante.

*   📱 **Control de Dispositivos por Cuenta:** Una lógica de negocio personalizada previene el uso no autorizado de cuentas, limitando el número de dispositivos que pueden asociarse a un único usuario.

*   🚀 **Flujo de Trabajo Optimizado para el Campo:**
    *   **Captura Rápida:** Acceso directo a la cámara del dispositivo.
    *   **Nomenclatura Automática:** Cada foto se nombra con el formato `FECHA_CONTADOR.jpg`, donde el contador es diario y persistente, eliminando errores manuales.
    *   **Operación Offline:** Las fotos pendientes de envío se guardan de forma segura en el dispositivo, permitiendo trabajar incluso sin conexión a internet.
    *   **Rendimiento Superior:** Generamos miniaturas en la caché local para que la visualización de galerías sea instantánea y fluida.

*   ☁️ **Subida Transparente a Servidor FTP:**
    *   **Alta Calidad:** Los archivos originales se envían al servidor FTP sin pérdida de calidad.
    *   **Organización Automática:** La app crea carpetas en el servidor con la fecha del día del envío (`AAAA-MM-DD`), manteniendo todo perfectamente organizado.

*   📂 **Historial Completo y Persistente:**
    *   **Todo Registrado:** Un historial persistente de cada archivo enviado, agrupado por fecha en carpetas expandibles.
    *   **Acceso Visual:** Visualiza las miniaturas de las fotos ya enviadas, cargando desde la caché local primero o desde el FTP como respaldo para garantizar el acceso.

---

## 🛠️ Cómo Poner en Marcha Cloud Capture

Para ejecutar este proyecto en tu entorno local, necesitarás configurar tanto tu máquina como un proyecto de Firebase.

### **1. Prerrequisitos de Software**

Asegúrate de tener instalado lo siguiente:

*   **Flutter SDK:** Versión 3.0.0 o superior.
*   **Git:** Para clonar el repositorio.
*   **Un Editor de Código:** Como Visual Studio Code con la extensión de Flutter.

### **2. Configuración del Proyecto Firebase (Paso Crítico)**

La aplicación no funcionará sin un backend de Firebase que la respalde. Debes crear tu propio proyecto.

1.  **Crea un Proyecto en Firebase:** Ve a la [Consola de Firebase](https://console.firebase.google.com/) y crea un nuevo proyecto.
2.  **Activa los Servicios:**
    *   **Authentication:** Habilita el proveedor de inicio de sesión **"Correo electrónico/Contraseña"**.
    *   **Cloud Firestore:** Crea una base de datos en **Modo de producción**.
3.  **Crea las Colecciones en Firestore:**
    *   Crea una colección llamada `companies`. Dentro, añade un documento con los campos: `companyName` (String), `ftpHost` (String), `ftpUser` (String), `ftpPassword` (String) y `ftpPort` (Number).
    *   Crea una colección llamada `users`. Dentro, añade un documento que tenga un campo `companyId` (String) cuyo valor sea el ID del documento que creaste en la colección `companies`.
4.  **Añade Usuarios de Prueba:** En la sección de Authentication, crea manualmente un usuario de prueba (con email y contraseña). Su "UID" deberá ser el ID que uses para el documento de la colección `users`.

### **3. Conexión de tu App con Firebase**

Esta es la forma moderna de conectar tu app Flutter.

1.  **Instala las Herramientas de Firebase:** Si no las tienes, abre una terminal y corre:
    ```bash
    dart pub global activate flutterfire_cli
    ```
2.  **Inicia Sesión y Configura:** En la raíz de tu proyecto de Flutter, corre los siguientes comandos:
    ```bash
    firebase login
    flutterfire configure
    ```
3.  Sigue las instrucciones en pantalla para seleccionar tu proyecto de Firebase y la plataforma (Android). Esto generará automáticamente el archivo `lib/firebase_options.dart` con las credenciales de **TU** proyecto.

### **4. Ejecución del Proyecto**

1.  **Clona el Repositorio (si aplica):**
    ```bash
    git clone [URL_DEL_REPOSITORIO]
    cd [NOMBRE_DE_LA_CARPETA]
    ```
2.  **Instala las Dependencias:**
    ```bash
    flutter pub get
    ```
3.  **Ejecuta la Aplicación:** Con un emulador abierto o un dispositivo físico conectado, corre:
    ```bash
    flutter run
    ```

¡Y listo! La aplicación debería compilarse y ejecutarse, conectada a tu propio backend de Firebase.

---

> Desarrollado con precisión por **Foxbyte**