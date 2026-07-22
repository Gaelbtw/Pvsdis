import 'dart:convert';

/// Decodifica el payload de un JWT sin verificar la firma -- eso ya lo hizo
/// el backend al emitirlo y al validar cada request; el cliente solo
/// necesita leer claims como `tenant_id` para guardarlos/mostrarlos en
/// memoria. Evita sumar un paquete completo de JWT (con verificación de
/// firma, que acá no aplica) solo para leer dos campos.
class JwtUtils {
  JwtUtils._();

  /// Devuelve los claims del JWT como mapa, o `null` si el token no tiene
  /// el formato esperado (tres segmentos separados por `.`) o el payload no
  /// es JSON válido.
  static Map<String, dynamic>? decodificarPayload(String token) {
    final partes = token.split('.');
    if (partes.length != 3) return null;

    try {
      final normalizado = base64Url.normalize(partes[1]);
      final decodificado = utf8.decode(base64Url.decode(normalizado));
      final json = jsonDecode(decodificado);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// Claim `tenant_id` que el backend agrega a todo JWT emitido
  /// (`TokenService`, ver `docs/sync-desktop-fase2.md` §5). `null` si el
  /// token no se pudo decodificar o no trae el claim.
  static String? tenantIdDe(String token) => decodificarPayload(token)?['tenant_id'] as String?;
}
