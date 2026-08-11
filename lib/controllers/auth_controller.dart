import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/security/login_throttle.dart';
import '../core/security/password_hasher.dart';

enum LoginStatus { success, usuarioNoEncontrado, contrasenaIncorrecta }

/// Datos que cruzan al isolate de [_buscarPinCoincidente]. Solo tipos
/// simples: lo que se envía a `compute` tiene que ser serializable, y las
/// filas crudas de sqflite no lo son de forma confiable.
class _EntradaVerificacionPin {
  const _EntradaVerificacionPin({required this.pin, required this.hashes});

  final String pin;
  final List<String> hashes;
}

/// Índice del primer hash de [entrada] que corresponde al PIN, o `null` si
/// ninguno coincide. Función de nivel superior (requisito de `compute`).
int? _buscarPinCoincidente(_EntradaVerificacionPin entrada) {
  for (var i = 0; i < entrada.hashes.length; i++) {
    if (PasswordHasher.verify(entrada.pin, entrada.hashes[i])) return i;
  }
  return null;
}

class LoginResult {
  final LoginStatus status;
  final Map<String, dynamic>? usuario;

  const LoginResult(this.status, this.usuario);
}

class Authcontroller {
  final dbHelper = DatabaseHelper();
  final _throttle = LoginThrottle.instancia;

  /// Verifica usuario y contraseña.
  ///
  /// Lanza si el usuario está temporalmente bloqueado por intentos fallidos
  /// (ver [LoginThrottle]); devuelve [LoginResult] en cualquier otro caso.
  /// El throttle se consulta ANTES de tocar la base para no gastar un bcrypt
  /// en un intento que se iba a rechazar igual.
  Future<LoginResult> login(String nombre, String password) async {
    final clave = LoginThrottle.claveUsuario(nombre);
    _throttle.verificarPuedeIntentar(clave);

    final db = await dbHelper.database;

    final result = await db.query(
      'Usuarios',
      where: 'LOWER(nombre) = ?',
      whereArgs: [nombre.toLowerCase()],
      limit: 1,
    );

    if (result.isEmpty) {
      _throttle.registrarFallo(clave);
      return const LoginResult(LoginStatus.usuarioNoEncontrado, null);
    }

    final usuario = result.first;
    final contrasenaAlmacenada = usuario['contra']?.toString() ?? '';

    if (!PasswordHasher.verify(password, contrasenaAlmacenada)) {
      _throttle.registrarFallo(clave);
      return const LoginResult(LoginStatus.contrasenaIncorrecta, null);
    }

    _throttle.registrarExito(clave);
    return LoginResult(LoginStatus.success, usuario);
  }

  /// Login rápido por PIN: identifica al usuario probando el [pin] contra el
  /// hash de cada usuario que tenga uno configurado. Como el PIN se guarda
  /// hasheado (bcrypt), no se puede buscar por igualdad en SQL. Devuelve
  /// [LoginStatus.usuarioNoEncontrado] si ningún PIN coincide.
  ///
  /// Todos los intentos por PIN comparten una única clave de throttle: a
  /// diferencia del login por nombre, aquí no se sabe a quién se está
  /// intentando suplantar hasta que el PIN acierta. Es justo el caso que más
  /// necesita el límite —4 dígitos son solo 10.000 combinaciones—, así que
  /// agruparlos es lo correcto y no una simplificación.
  Future<LoginResult> loginConPin(String pin) async {
    _throttle.verificarPuedeIntentar(LoginThrottle.clavePin);

    final db = await dbHelper.database;

    final usuarios = await db.query('Usuarios', where: 'pin IS NOT NULL');

    // La comparación corre en un isolate aparte, NO en el hilo de UI.
    //
    // `BCrypt.checkpw` es síncrono y lento a propósito (ese es el punto de
    // bcrypt), y aquí se ejecuta una vez por cada usuario con PIN hasta dar
    // con el correcto. Haciéndolo en el hilo principal, un PIN equivocado
    // —que recorre la lista entera— congelaba la ventana: con 10 usuarios
    // son ~10 verificaciones seguidas, y en el CPU de una terminal de punto
    // de venta cada una cuesta bastante más que en una PC de escritorio.
    // Con `compute` la UI sigue respondiendo y el spinner del login puede
    // animarse mientras tanto.
    final indice = await compute(
      _buscarPinCoincidente,
      _EntradaVerificacionPin(
        pin: pin,
        hashes: [for (final u in usuarios) u['pin']?.toString() ?? ''],
      ),
    );

    if (indice != null) {
      _throttle.registrarExito(LoginThrottle.clavePin);
      return LoginResult(LoginStatus.success, usuarios[indice]);
    }

    _throttle.registrarFallo(LoginThrottle.clavePin);
    return const LoginResult(LoginStatus.usuarioNoEncontrado, null);
  }

  /// Indica si ya existe al menos un usuario registrado. Se usa para saber
  /// si la app debe pedir crear la cuenta de administrador (primer arranque)
  /// en vez de mostrar el login.
  Future<bool> existenUsuarios() async {
    final db = await dbHelper.database;
    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM Usuarios'),
        ) ??
        0;
    return total > 0;
  }
}
