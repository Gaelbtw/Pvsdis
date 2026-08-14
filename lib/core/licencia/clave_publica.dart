/// Clave pública Ed25519 con la que la app verifica los archivos `.lic`.
///
/// # Lista vacía = licenciamiento APAGADO
///
/// Mientras esta lista esté vacía, [LicenciaService] reporta `sinLicencia` y
/// **todo funciona sin restricción**, exactamente igual que antes de que
/// existiera este módulo.
///
/// Eso es deliberado. Los primeros clientes se instalan presencialmente y con
/// contrato en papel: no necesitan licenciamiento técnico, y activarlo antes de
/// tiempo solo agrega una forma nueva de que a alguien se le caiga la caja un
/// sábado. El código está listo y probado para el día que haga falta; encender
/// el interruptor es pegar aquí 32 bytes.
///
/// # Cómo se enciende
///
/// 1. Genera el par de llaves **una sola vez**:
///
///    ```
///    dart run tool/emitir_licencia.dart generar-llaves --salida C:\llaves\pvcontrol
///    ```
///
/// 2. El comando imprime la clave pública ya formateada como la lista de abajo.
///    Pégala aquí y recompila.
///
/// 3. Guarda `pvcontrol.privada` **fuera del repositorio**, con respaldo.
///
/// # Si pierdes la llave privada
///
/// No hay forma de recuperarla, y ninguna licencia nueva será aceptada por las
/// versiones ya instaladas. Tendrías que generar otro par, publicar una versión
/// con la clave pública nueva y reemitir todas las licencias vigentes. Trátala
/// como el respaldo del negocio: dos copias, en dos lugares distintos.
///
/// # Qué NO poner aquí
///
/// La clave **privada**. Va compilada dentro del .exe que está en la
/// computadora de cada cliente: cualquiera puede extraer estos 32 bytes. Con la
/// pública solo se pueden *verificar* licencias, que es justo lo que queremos.
library;

const List<int> clavePublicaLicencias = <int>[
  // Pega aquí los 32 bytes que imprime `generar-llaves`.
];

/// `true` cuando hay una clave pública compilada y, por lo tanto, el
/// licenciamiento está activo en esta compilación.
bool get licenciamientoActivo => clavePublicaLicencias.length == 32;
