// Pruebas de TicketApartadoService.generarReciboAbono: no debe lanzar tanto
// para un abono parcial (saldo pendiente > 0) como para la liquidación
// (saldo pendiente 0).
import 'package:flutter_test/flutter_test.dart';
import 'package:pvapp/services/ticket_apartado_service.dart';

void main() {
  final itemsDeEjemplo = [
    {'nombre': 'Producto de prueba', 'cantidad': 1, 'precio_neto': 100.0},
  ];

  test('genera el recibo de un abono parcial con saldo pendiente', () async {
    final pdf = await TicketApartadoService.generarReciboAbono(
      idApartado: 1,
      clienteNombre: 'Cliente de prueba',
      items: itemsDeEjemplo,
      tipoAbono: 'abono',
      montoAbono: 40.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 40.0},
      ],
      cambio: 0,
      totalApartado: 100.0,
      abonadoAFecha: 40.0,
      saldoPendiente: 60.0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('genera el recibo de la liquidación (saldo pendiente 0) sin lanzar', () async {
    final pdf = await TicketApartadoService.generarReciboAbono(
      idApartado: 1,
      clienteNombre: 'Cliente de prueba',
      items: itemsDeEjemplo,
      tipoAbono: 'liquidación',
      montoAbono: 60.0,
      pagos: const [
        {'metodo_pago': 'Tarjeta', 'monto': 60.0},
      ],
      cambio: 0,
      totalApartado: 100.0,
      abonadoAFecha: 100.0,
      saldoPendiente: 0.0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('genera el recibo con cambio (pago en efectivo con excedente)', () async {
    final pdf = await TicketApartadoService.generarReciboAbono(
      idApartado: 1,
      clienteNombre: 'Cliente de prueba',
      items: itemsDeEjemplo,
      tipoAbono: 'anticipo',
      montoAbono: 40.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
      ],
      cambio: 10.0,
      totalApartado: 100.0,
      abonadoAFecha: 40.0,
      saldoPendiente: 60.0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });
}
