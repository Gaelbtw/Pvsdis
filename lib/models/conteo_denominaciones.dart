import 'dart:convert';

import '../core/utils/money.dart';

/// Lo que el cajero contó físicamente en el cajón, desglosado por
/// denominación.
///
/// Antes el cierre pedía un solo número —"efectivo contado"— que el cajero
/// calculaba aparte, en papel o con la calculadora del celular. Ese número
/// llegaba al sistema sin nada detrás: si al día siguiente alguien discutía
/// un faltante, no había forma de saber si el error fue del conteo, de la
/// suma o de la captura.
///
/// Guardar el desglose no es burocracia: es la única evidencia de QUÉ se
/// contó. También quita la calculadora de en medio, que es de donde salen la
/// mitad de las diferencias de veinte pesos.
///
/// [monedas] va al bulto a propósito. Separar las de diez, cinco, dos y uno
/// serían cuatro campos más que nadie llena bien con prisa, y el error de
/// pesar mal un puño de monedas es de centavos. Quien no quiera desglosar
/// billetes puede capturar todo aquí: el total sigue siendo correcto.
class ConteoDenominaciones {
  /// Billetes mexicanos en circulación, del mayor al menor. El orden importa:
  /// es el orden en que se apilan al contar, y por lo tanto el orden en que
  /// se teclean.
  static const List<int> denominaciones = [1000, 500, 200, 100, 50, 20];

  /// Denominación → cuántos billetes de esa. Las que no aparecen valen cero.
  final Map<int, int> billetes;

  /// Monedas y sueltos, en pesos, sin separar por denominación.
  final double monedas;

  const ConteoDenominaciones({this.billetes = const {}, this.monedas = 0});

  static const ConteoDenominaciones vacio = ConteoDenominaciones();

  int cantidadDe(int denominacion) => billetes[denominacion] ?? 0;

  double subtotalDe(int denominacion) => (billetes[denominacion] ?? 0) * denominacion.toDouble();

  double get totalBilletes {
    var suma = 0.0;
    for (final entrada in billetes.entries) {
      suma += entrada.key * entrada.value;
    }
    return suma;
  }

  /// Cuántos billetes hay en total (no incluye monedas: no se cuentan piezas
  /// de moneda, se pesan o se calculan).
  int get piezasBilletes => billetes.values.fold(0, (a, b) => a + b);

  double get total => redondearMoneda(totalBilletes + monedas);

  /// `true` si no se capturó absolutamente nada. Distinto de un conteo que
  /// suma cero habiendo tecleado ceros: eso es un cajón vacío declarado, que
  /// es un dato válido.
  bool get sinCapturar => billetes.isEmpty && monedas == 0;

  ConteoDenominaciones conBillete(int denominacion, int cantidad) {
    final copia = Map<int, int>.from(billetes);
    if (cantidad <= 0) {
      copia.remove(denominacion);
    } else {
      copia[denominacion] = cantidad;
    }
    return ConteoDenominaciones(billetes: copia, monedas: monedas);
  }

  ConteoDenominaciones conMonedas(double valor) =>
      ConteoDenominaciones(billetes: billetes, monedas: valor);

  /// Se guarda como texto JSON en `Cajas.conteo_denominaciones`. Las llaves
  /// van como cadena porque JSON no tiene llaves numéricas.
  String aJson() => jsonEncode({
        'billetes': billetes.map((k, v) => MapEntry(k.toString(), v)),
        'monedas': monedas,
      });

  /// Reconstruye un conteo guardado. Devuelve `null` cuando no hay nada que
  /// leer o cuando el texto no es un conteo válido: una caja cerrada antes de
  /// esta versión no tiene desglose, y eso no es un error — solo significa
  /// que en ese cierre únicamente se capturó el total.
  static ConteoDenominaciones? desdeJson(String? texto) {
    if (texto == null || texto.trim().isEmpty) return null;
    try {
      final crudo = jsonDecode(texto);
      if (crudo is! Map) return null;

      final billetes = <int, int>{};
      final mapaBilletes = crudo['billetes'];
      if (mapaBilletes is Map) {
        for (final entrada in mapaBilletes.entries) {
          final denominacion = int.tryParse(entrada.key.toString());
          final cantidad = (entrada.value as num?)?.toInt();
          if (denominacion != null && cantidad != null && cantidad > 0) {
            billetes[denominacion] = cantidad;
          }
        }
      }

      return ConteoDenominaciones(
        billetes: billetes,
        monedas: (crudo['monedas'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Renglones listos para imprimir, del billete mayor al menor, omitiendo
  /// las denominaciones en cero. Vive aquí y no en el servicio de ticket
  /// para que el ticket de cierre y la pantalla de resultado no puedan
  /// diferir en qué muestran.
  List<({String etiqueta, double importe})> get renglones {
    final salida = <({String etiqueta, double importe})>[];
    for (final denominacion in denominaciones) {
      final cantidad = cantidadDe(denominacion);
      if (cantidad > 0) {
        salida.add((
          etiqueta: '$cantidad x \$$denominacion',
          importe: cantidad * denominacion.toDouble(),
        ));
      }
    }
    if (monedas != 0) {
      salida.add((etiqueta: 'Monedas', importe: monedas));
    }
    return salida;
  }
}
