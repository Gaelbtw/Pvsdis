import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../core/config/app_config.dart';

/// Abre el cajón de dinero enviando el pulso ESC/POS de apertura ("drawer
/// kick") a la impresora térmica, que es la que tiene el cajón conectado a su
/// puerto RJ11. Hay dos caminos, según cómo esté conectada la impresora:
///
/// 1. **Spooler de Windows** (por defecto): se manda en modo **RAW** a la cola
///    de impresión. Se hace así porque `package:printing` solo imprime PDF (que
///    el driver rasteriza) y nunca deja llegar bytes crudos a la impresora, que
///    es lo que el cajón necesita.
/// 2. **Puerto serie** (`Configuracion.cajonPuerto` = `'COM1'`, `'COM3'`, ...):
///    se abre el puerto y se escriben los bytes directamente. Es el camino
///    obligado cuando la impresora está conectada por serie y no tiene driver
///    instalado: sin driver no hay cola a la que mandar nada.
///
/// Solo actúa en Windows; en otras plataformas es un no-op. **Nunca lanza**: si
/// no hay impresora, el puerto no existe, el spooler falla o la impresora está
/// apagada, se traga el error para no tumbar una venta ni un cierre de caja por
/// culpa del cajón.
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

  /// Envía el pulso de apertura sin mirar el interruptor de configuración: es
  /// lo que usa el botón de "Probar cajón" de la pantalla de Configuración.
  ///
  /// Devuelve `true` si el pulso salió (no si el cajón abrió de verdad: el
  /// cajón no responde nada, así que eso solo puede verlo el usuario).
  static Future<bool> abrir() async {
    if (!Platform.isWindows) return false;
    try {
      final datos = Uint8List.fromList(_pulsoApertura);
      final puerto = AppConfig.actual.cajonPuerto?.trim();

      if (puerto != null && puerto.isNotEmpty) {
        return _enviarPorPuertoSerie(puerto, AppConfig.actual.cajonBaudios, datos);
      }

      return _enviarRaw(datos);
    } catch (_) {
      // best-effort: el cajón nunca debe interrumpir la operación.
      return false;
    }
  }

  /// Escribe [datos] en un puerto serie de Windows (`COM1`, `COM3`, ...).
  ///
  /// El nombre se antepone con `\\.\` a propósito: sin ese prefijo, Windows no
  /// puede abrir puertos de dos dígitos (`COM10` en adelante), un caso muy común
  /// cuando la impresora es USB-serie y Windows le asigna un número alto.
  static bool _enviarPorPuertoSerie(String puerto, int baudios, Uint8List datos) {
    final nombre = r'\\.\' + puerto.toUpperCase();
    final nombreNativo = nombre.toNativeUtf16();
    final dcb = calloc<DCB>();
    final timeouts = calloc<COMMTIMEOUTS>();
    final buffer = calloc<Uint8>(datos.length);
    final escritos = calloc<Uint32>();

    var handle = INVALID_HANDLE_VALUE;

    try {
      handle = CreateFile(
        nombreNativo,
        GENERIC_WRITE,
        0, // exclusivo: nadie más debe estar escribiendo en el puerto
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL,
      );
      if (handle == INVALID_HANDLE_VALUE) return false;

      // 8N1 es la configuración de fábrica de las impresoras térmicas; lo
      // único que suele variar entre modelos es la velocidad.
      dcb.ref.DCBlength = sizeOf<DCB>();
      if (GetCommState(handle, dcb) == 0) return false;
      dcb.ref
        ..BaudRate = baudios
        ..ByteSize = 8
        ..Parity = NOPARITY
        ..StopBits = ONESTOPBIT;
      if (SetCommState(handle, dcb) == 0) return false;

      // Sin tiempo límite, escribir en un puerto existente pero sin nada
      // conectado bloquea el hilo de la interfaz de forma indefinida: la app se
      // congelaría al cobrar. 500 ms es de sobra para 5 bytes.
      timeouts.ref
        ..ReadIntervalTimeout = 0
        ..ReadTotalTimeoutMultiplier = 0
        ..ReadTotalTimeoutConstant = 0
        ..WriteTotalTimeoutMultiplier = 0
        ..WriteTotalTimeoutConstant = 500;
      SetCommTimeouts(handle, timeouts);

      buffer.asTypedList(datos.length).setAll(0, datos);
      if (WriteFile(handle, buffer, datos.length, escritos, nullptr) == 0) {
        return false;
      }
      FlushFileBuffers(handle);
      return escritos.value == datos.length;
    } finally {
      if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
      calloc.free(nombreNativo);
      calloc.free(dcb);
      calloc.free(timeouts);
      calloc.free(buffer);
      calloc.free(escritos);
    }
  }

  static bool _enviarRaw(Uint8List datos) {
    final nombre = _nombreImpresora();
    if (nombre == null) return false;

    final printerName = nombre.toNativeUtf16();
    final phPrinter = calloc<IntPtr>();
    final docInfo = calloc<DOC_INFO_1>();
    final docName = 'Cajon'.toNativeUtf16();
    final rawType = 'RAW'.toNativeUtf16();
    final buffer = calloc<Uint8>(datos.length);
    final escritos = calloc<Uint32>();

    try {
      if (OpenPrinter(printerName, phPrinter, nullptr) == 0) return false;
      final hPrinter = phPrinter.value;
      try {
        docInfo.ref
          ..pDocName = docName
          ..pOutputFile = nullptr
          ..pDatatype = rawType;

        if (StartDocPrinter(hPrinter, 1, docInfo) == 0) return false;
        try {
          if (StartPagePrinter(hPrinter) == 0) return false;
          buffer.asTypedList(datos.length).setAll(0, datos);
          WritePrinter(hPrinter, buffer.cast(), datos.length, escritos);
          EndPagePrinter(hPrinter);
          return escritos.value == datos.length;
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
