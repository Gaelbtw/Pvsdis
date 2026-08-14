import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App mínima que se muestra cuando la base de datos no se pudo abrir y el POS
/// no puede arrancar.
///
/// Es una app aparte y no una pantalla dentro de la normal porque el fallo
/// ocurre ANTES de que exista base de datos, sesión o configuración del
/// negocio: nada de lo que las pantallas normales dan por hecho está
/// disponible todavía. Por eso tampoco usa `AppColors` (que se pinta con el
/// color de marca guardado en la base) ni la barra de ventana propia.
///
/// El objetivo es que el cliente no vea un error rojo de Flutter ni una
/// ventana que se cierra sola. Un cliente asustado que ve un error
/// incomprensible borra la carpeta de datos "para que se arregle", y ahí sí se
/// pierde el negocio entero.
class ErrorArranqueApp extends StatelessWidget {
  const ErrorArranqueApp({
    super.key,
    required this.titulo,
    required this.mensaje,
    this.detalle,
  });

  /// Encabezado corto, en lenguaje de negocio ("No se pudo abrir el sistema").
  final String titulo;

  /// Explicación de qué pasó y qué hacer, dirigida al dueño del negocio.
  final String mensaje;

  /// Información técnica (rutas, versiones) para copiar y mandar por WhatsApp.
  /// Va en un bloque aparte para que no compita con el mensaje principal.
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pv Control',
      debugShowCheckedModeBanner: false,
      home: _PantallaError(titulo: titulo, mensaje: mensaje, detalle: detalle),
    );
  }
}

class _PantallaError extends StatelessWidget {
  const _PantallaError({
    required this.titulo,
    required this.mensaje,
    this.detalle,
  });

  final String titulo;
  final String mensaje;
  final String? detalle;

  static const _fondo = Color(0xFFF8F6F2);
  static const _texto = Color(0xFF2D2B28);
  static const _textoSuave = Color(0xFF6E6A64);
  static const _acento = Color(0xFFEF6C00);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF0EBE5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _acento.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.warning_amber_rounded,
                            color: _acento, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _texto,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    mensaje,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: _texto,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFE0A3)),
                    ),
                    child: const Text(
                      'No borres ni muevas la carpeta de datos. Tu información '
                      'sigue completa: este aviso existe justamente para no '
                      'tocarla hasta resolverlo.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF7A5A00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (detalle != null) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'DETALLE TÉCNICO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _textoSuave,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _fondo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        detalle!,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          fontFamily: 'monospace',
                          color: _textoSuave,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: '$titulo\n\n$mensaje\n\n${detalle ?? ''}'),
                        ),
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('Copiar para soporte'),
                        style: TextButton.styleFrom(foregroundColor: _textoSuave),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        // exit(0) y no SystemNavigator.pop(): en Windows
                        // escritorio pop() no cierra el proceso y la ventana
                        // se quedaría colgada sin nada que hacer.
                        onPressed: () => exit(0),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _texto,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cerrar',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
