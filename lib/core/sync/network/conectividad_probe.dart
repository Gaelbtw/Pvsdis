import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../config/backend_config.dart';

/// Chequeo simple de "¿el backend responde ahora mismo?", para el badge
/// en línea/sin conexión mencionado en `BackendConfig`.
///
/// Deliberadamente NO usa `connectivity_plus`: esa dependencia solo confirma
/// que el dispositivo tiene una interfaz de red activa (wifi/datos), no que
/// el backend en particular sea alcanzable (puede estar caído, o el
/// dispositivo puede estar en una red sin salida a él). Un `GET /health`
/// real contesta la pregunta que de verdad importa para decidir si se puede
/// sincronizar, con un timeout corto para no bloquear la UI.
class ConectividadProbe {
  ConectividadProbe({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 3);

  /// `true` si el backend respondió `GET /health` con éxito dentro del
  /// timeout corto. Cualquier falla (red, timeout, backend caído, respuesta
  /// de error) se trata como "sin conexión" -- este probe nunca lanza.
  Future<bool> hayConexion() async {
    try {
      final respuesta = await _client.get(BackendConfig.healthUri).timeout(_timeout);
      return respuesta.statusCode >= 200 && respuesta.statusCode < 300;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } on HttpException {
      return false;
    }
  }

  void close() => _client.close();
}
