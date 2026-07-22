/// Modelos Dart que espejan `EsqPos.Application.DTOs.SyncDtos` (backend,
/// ver `C:\dev\EsqueletoPOS\src\EsqPos.Application\DTOs\SyncDtos.cs`) y el
/// contrato descrito en `docs/sync-desktop-fase2.md` §2.
///
/// `elementos`/`datos` no se tipan contra un modelo de dominio por entidad:
/// el backend serializa cada entidad "tal cual" (`Producto`, `Venta`,
/// `Promocion` con sus hijos, etc. -- ver `SyncPullResponseDto.Elementos`,
/// tipado `List<object>` en el propio backend porque varía por entidad), así
/// que acá se exponen como `Map<String, dynamic>` genérico. El mapeo campo
/// por campo a las tablas espejo locales (columna `guid_sync`) es el
/// siguiente paso de esta integración, no esta fase (ver
/// `lib/core/sync/README-fase2.md`).
///
/// Espejo de `SyncPullResponseDto`. Respuesta de
/// `GET /api/sync/{entidad}?desde=&limite=`.
class SyncPullResponse {
  final List<Map<String, dynamic>> elementos;
  final bool hayMas;
  final DateTime ultimaFechaModificacion;

  const SyncPullResponse({
    required this.elementos,
    required this.hayMas,
    required this.ultimaFechaModificacion,
  });

  factory SyncPullResponse.fromJson(Map<String, dynamic> json) {
    return SyncPullResponse(
      elementos: (json['elementos'] as List<dynamic>? ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      hayMas: json['hayMas'] as bool? ?? false,
      ultimaFechaModificacion: DateTime.parse(json['ultimaFechaModificacion'] as String),
    );
  }
}

/// Espejo de `SyncPushItemDto`: un cambio local dentro del lote de
/// `POST /api/sync/push`. `datos` debe incluir al menos `id` (el GUID
/// asignado en el cliente) y las columnas que espera la entidad del lado
/// del servidor.
class SyncPushItem {
  final String entidad;
  final Map<String, dynamic> datos;

  const SyncPushItem({required this.entidad, required this.datos});

  Map<String, dynamic> toJson() => {'entidad': entidad, 'datos': datos};
}

/// Espejo de `SyncPushRequestDto`. El orden de [cambios] importa: el
/// backend aplica cada ítem por separado y en orden (no es transaccional
/// entre ítems), así que el cliente debe mandar padre antes que hijo
/// (`Venta` antes que `VentaDetalle`, etc. -- ver
/// `docs/sync-desktop-fase2.md` §2.3). Esta clase no reordena nada.
class SyncPushRequest {
  final List<SyncPushItem> cambios;

  const SyncPushRequest(this.cambios);

  Map<String, dynamic> toJson() => {'cambios': cambios.map((c) => c.toJson()).toList()};
}

/// Espejo de `SyncPushResultItemDto`. `resultado` es uno de "Insertado",
/// "Actualizado" u "OmitidoServidorGana" (ver docs §2.3 y §3).
class SyncPushResultItem {
  final String entidad;
  final String id;
  final String resultado;

  const SyncPushResultItem({required this.entidad, required this.id, required this.resultado});

  factory SyncPushResultItem.fromJson(Map<String, dynamic> json) {
    return SyncPushResultItem(
      entidad: json['entidad'] as String,
      id: json['id'] as String,
      resultado: json['resultado'] as String,
    );
  }

  /// `true` si el servidor ignoró este ítem porque la entidad es
  /// ServidorGana y la fila ya existía: quien llama debe hacer un pull
  /// después para quedar consistente, no reintentar el push.
  bool get omitidoPorServidor => resultado == 'OmitidoServidorGana';
}

/// Espejo de `SyncPushResponseDto`. Respuesta de `POST /api/sync/push`.
class SyncPushResponse {
  final List<SyncPushResultItem> resultados;

  const SyncPushResponse(this.resultados);

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) {
    return SyncPushResponse(
      (json['resultados'] as List<dynamic>? ?? const [])
          .map((e) => SyncPushResultItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
