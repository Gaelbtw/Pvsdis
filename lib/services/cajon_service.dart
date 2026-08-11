import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../core/config/app_config.dart';

/// Abre el cajón de dinero enviando el pulso ESC/POS de apertura ("drawer
/// kick") directamente a la impresora en modo **RAW** a través del spooler de
/// Windows. Se hace así porque `package:printing` solo imprime PDF (que el
/// driver rasteriza) y nunca deja llegar bytes crudos a la impresora, que es lo
/// que el cajón necesita. El cajón debe estar conectado al puerto RJ11 de la
/// impresora térmica.
///
/// Solo actúa en Windows; en otras plataformas es un no-op. **Nunca lanza**: si
/// no hay impresora, el spooler falla o la impresora está apagada, se traga el
/// error para no tumbar una venta ni un cierre de caja por culpa del cajón.
class CajonService {
  /// `ESC p m t1 t2` — pulso de apertura estándar (m=0 → pin 2 del conector;
  /// t1=25, t2=250 → tiempos on/off del pulso). Es el comando que aceptan la
  /// gran mayoría de las impresoras térmicas ESC/POS.
  static const List<int> _pulsoApertura = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  /// Abre el cajón solo si la configuración lo tiene activado
  /// ([Configuracion.abrirCajonEfectivo]). Es lo que llaman la venta en
  /// efectivo y el cierre de caja.
  static Future<void> abrirSiCorresponde() async {
    if (!AppConfig.actual.abrirCajonEfectivo) return;
    await abrir();
  }

  /// Envía el pulso de apertura sin mirar la configuración (para un botón
  /// manual de "abrir cajón", si se agrega más adelante).
  static Future<void> abrir() async {
    if (!Platform.isWindows) return;
    try {
      _enviarRaw(Uint8List.fromList(_pulsoApertura));
    } catch (_) {
      // best-effort: el cajón nunca debe interrumpir la operación.
    }
  }

  static void _enviarRaw(Uint8List datos) {
    final nombre = _nombreImpresora();
    if (nombre == null) return;

    final printerName = nombre.toNativeUtf16();
    final phPrinter = calloc<IntPtr>();
    final docInfo = calloc<DOC_INFO_1>();
    final docName = 'Cajon'.toNativeUtf16();
    final rawType = 'RAW'.toNativeUtf16();
    final buffer = calloc<Uint8>(datos.length);
    final escritos = calloc<Uint32>();

    try {
      if (OpenPrinter(printerName, phPrinter, nullptr) == 0) return;
      final hPrinter = phPrinter.value;
      try {
        docInfo.ref
          ..pDocName = docName
          ..pOutputFile = nullptr
          ..pDatatype = rawType;

        if (StartDocPrinter(hPrinter, 1, docInfo) == 0) return;
        try {
          if (StartPagePrinter(hPrinter) == 0) return;
          buffer.asTypedList(datos.length).setAll(0, datos);
          WritePrinter(hPrinter, buffer.cast(), datos.length, escritos);
          EndPagePrinter(hPrinter);
        } finally {
          EndDocPrinter(hPrinter);
        }
      } finally {
        ClosePrinter(hPrinter);
      }
    } finally {
      calloc.free(printerName);
      calloc.free(phPrinter);
      calloc.free(docInfo);
      calloc.free(docName);
      calloc.free(rawType);
      calloc.free(buffer);
      calloc.free(escritos);
    }
  }

  /// La impresora configurada para tickets, o la predeterminada de Windows si
  /// no se eligió ninguna.
  static String? _nombreImpresora() {
    final configurada = AppConfig.actual.impresoraNombre;
    if (configurada != null && configurada.trim().isNotEmpty) return configurada;
    return _impresoraPredeterminada();
  }

  static String? _impresoraPredeterminada() {
    final tam = calloc<Uint32>();
    // Primera llamada con buffer nulo: falla a propósito y deja en `tam` la
    // cantidad de caracteres que necesita el nombre.
    GetDefaultPrinter(nullptr, tam);
    final n = tam.value;
    if (n == 0) {
      calloc.free(tam);
      return null;
    }
    final buffer = calloc<Uint16>(n);
    try {
      if (GetDefaultPrinter(buffer.cast<Utf16>(), tam) == 0) return null;
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
      calloc.free(tam);
    }
  }
}
