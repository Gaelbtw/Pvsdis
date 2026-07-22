/// Espejo de `SucursalDto` (backend, ver
/// `C:\dev\EsqueletoPOS\src\EsqPos.Application\DTOs\SucursalDtos.cs`).
/// Respuesta de `GET /api/sucursales` / `GET /api/sucursales/{id}`.
class SucursalDto {
  final String id;
  final String nombre;
  final String? direccion;
  final String? telefono;
  final bool esPrincipal;
  final bool activo;
  final DateTime fechaCreacion;

  const SucursalDto({
    required this.id,
    required this.nombre,
    this.direccion,
    this.telefono,
    required this.esPrincipal,
    required this.activo,
    required this.fechaCreacion,
  });

  factory SucursalDto.fromJson(Map<String, dynamic> json) {
    return SucursalDto(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      direccion: json['direccion'] as String?,
      telefono: json['telefono'] as String?,
      esPrincipal: json['esPrincipal'] as bool,
      activo: json['activo'] as bool,
      fechaCreacion: DateTime.parse(json['fechaCreacion'] as String),
    );
  }
}
