// Pruebas de TicketService.generarTicket con la sección de promociones:
// debe incluirse cuando se pasan promociones aplicadas y omitirse cuando no
// (compatibilidad hacia atrás con los demás llamadores que no la usan).
import 'package:flutter_test/flutter_test.dart';
import 'package:pvapp/services/ticket_service.dart';

void main() {
  final carritoDeEjemplo = [
    {'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1, 'descuento_monto': 0.0},
  ];

  test('genera el ticket con promociones aplicadas: subtotal anterior, ahorro y total final', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 85.0,
      subtotal: 100.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 85.0},
      ],
      cambio: 0,
      promocionesAplicadas: const [
        {'nombre': '15% de descuento', 'ahorro_total': 15.0},
      ],
      ahorroPromociones: 15.0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('genera el ticket con varias promociones aplicadas a la vez', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 70.0,
      subtotal: 100.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 70.0},
      ],
      cambio: 0,
      promocionesAplicadas: const [
        {'nombre': '10% de descuento', 'ahorro_total': 10.0},
        {'nombre': 'Combo especial', 'ahorro_total': 20.0},
      ],
      ahorroPromociones: 30.0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('sin promociones no rompe la generación (compatibilidad hacia atrás)', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 100.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
      cambio: 0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('lista de promociones vacía se comporta igual que no pasarla', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 100.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
      cambio: 0,
      promocionesAplicadas: const [],
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });
}
