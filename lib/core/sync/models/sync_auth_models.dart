import '../network/jwt_utils.dart';

/// Modelos Dart que espejan los DTOs de autenticación del backend
/// (`EsqPos.Application.DTOs`, ver
/// `C:\dev\EsqueletoPOS\src\EsqPos.Application\DTOs\AuthDtos.cs`). Los
/// nombres de campo JSON quedan en camelCase porque así serializa
/// `System.Text.Json` los `record` de C# por defecto.

/// Espejo de `LoginDto`. Cuerpo de `POST /api/auth/login`.
class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

/// Espejo de `RefreshTokenRequestDto`. Cuerpo de `POST /api/auth/refresh-token`
/// y `POST /api/auth/logout`.
class RefreshTokenRequest {
  final String refreshToken;

  const RefreshTokenRequest(this.refreshToken);

  Map<String, dynamic> toJson() => {'refreshToken': refreshToken};
}

/// Espejo de `LoginResponseDto`. Respuesta de login y de refresh (el
/// backend rota el refresh token en cada llamada, así que ambos endpoints
/// devuelven la misma forma).
class LoginResponse {
  final String usuarioId;
  final String email;
  final String nombreCompleto;
  final List<String> roles;
  final String? sucursalId;
  final String accessToken;
  final DateTime accessTokenExpiraEn;
  final String refreshToken;

  const LoginResponse({
    required this.usuarioId,
    required this.email,
    required this.nombreCompleto,
    required this.roles,
    this.sucursalId,
    required this.accessToken,
    required this.accessTokenExpiraEn,
    required this.refreshToken,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      usuarioId: json['usuarioId'] as String,
      email: json['email'] as String,
      nombreCompleto: json['nombreCompleto'] as String,
      roles: (json['roles'] as List<dynamic>? ?? const []).map((e) => e as String).toList(),
      sucursalId: json['sucursalId'] as String?,
      accessToken: json['accessToken'] as String,
      accessTokenExpiraEn: DateTime.parse(json['accessTokenExpiraEn'] as String),
      refreshToken: json['refreshToken'] as String,
    );
  }
}

/// Snapshot persistido de la sesión de sincronización: lo que devuelve el
/// login/refresh más el `tenant_id` ya decodificado del JWT (ver
/// [JwtUtils]), para no tener que redecodificar el token cada vez que se
/// necesita el tenant actual.
class SesionSync {
  final String usuarioId;
  final String email;
  final String nombreCompleto;
  final List<String> roles;
  final String? sucursalId;
  final String accessToken;
  final DateTime accessTokenExpiraEn;
  final String refreshToken;
  final String? tenantId;

  const SesionSync({
    required this.usuarioId,
    required this.email,
    required this.nombreCompleto,
    required this.roles,
    this.sucursalId,
    required this.accessToken,
    required this.accessTokenExpiraEn,
    required this.refreshToken,
    this.tenantId,
  });

  factory SesionSync.desdeLogin(LoginResponse login) {
    return SesionSync(
      usuarioId: login.usuarioId,
      email: login.email,
      nombreCompleto: login.nombreCompleto,
      roles: login.roles,
      sucursalId: login.sucursalId,
      accessToken: login.accessToken,
      accessTokenExpiraEn: login.accessTokenExpiraEn,
      refreshToken: login.refreshToken,
      tenantId: JwtUtils.tenantIdDe(login.accessToken),
    );
  }

  /// Margen de seguridad para refrescar el access token *antes* de que el
  /// backend lo rechace: evita que una llamada en curso falle por haber
  /// expirado a mitad de camino (el backend expira en ~30 min, ver
  /// `docs/sync-desktop-fase2.md` §5).
  static const _margenRefresh = Duration(seconds: 60);

  bool get accessTokenExpirado => DateTime.now().toUtc().isAfter(accessTokenExpiraEn);

  bool get accessTokenPorExpirar =>
      DateTime.now().toUtc().isAfter(accessTokenExpiraEn.subtract(_margenRefresh));

  Map<String, dynamic> toMap() => {
        'usuarioId': usuarioId,
        'email': email,
        'nombreCompleto': nombreCompleto,
        'roles': roles,
        'sucursalId': sucursalId,
        'accessToken': accessToken,
        'accessTokenExpiraEn': accessTokenExpiraEn.toIso8601String(),
        'refreshToken': refreshToken,
        'tenantId': tenantId,
      };

  factory SesionSync.fromMap(Map<String, dynamic> map) => SesionSync(
        usuarioId: map['usuarioId'] as String,
        email: map['email'] as String,
        nombreCompleto: map['nombreCompleto'] as String,
        roles: (map['roles'] as List<dynamic>? ?? const []).map((e) => e as String).toList(),
        sucursalId: map['sucursalId'] as String?,
        accessToken: map['accessToken'] as String,
        accessTokenExpiraEn: DateTime.parse(map['accessTokenExpiraEn'] as String),
        refreshToken: map['refreshToken'] as String,
        tenantId: map['tenantId'] as String?,
      );
}
