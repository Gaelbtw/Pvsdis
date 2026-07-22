import 'dart:math';

/// Genera identificadores GUID v4 (RFC 4122) para las filas que participan
/// en la sincronización con el backend EsqPOS: cada entidad sincronizable
/// usa como `Id` real un GUID generado en el cliente (nunca el servidor lo
/// asigna) -- así una venta registrada offline en dos dispositivos distintos
/// nunca puede colisionar (ver `docs/sync-desktop-fase2.md` en el repo
/// EsqueletoPOS). Sin dependencia de un paquete `uuid`: son ~15 líneas sobre
/// `Random.secure()`, no vale la pena sumar una dependencia para esto (mismo
/// criterio que ya se usó en `lib/core/sync/` para el resto de la Fase 2).
class GuidGenerator {
  GuidGenerator._();

  static final Random _random = Random.secure();

  /// Un GUID v4 en formato estándar con guiones minúsculas
  /// (`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`), donde `y` es `8`, `9`, `a` o
  /// `b` según exige la variante RFC 4122.
  static String nuevo() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Version 4 (aleatorio): los 4 bits altos del byte 6 quedan en 0100.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Variante RFC 4122: los 2 bits altos del byte 8 quedan en 10.
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    String hex(int inicio, int fin) =>
        bytes.sublist(inicio, fin).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
