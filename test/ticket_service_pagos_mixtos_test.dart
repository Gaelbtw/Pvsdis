// Pruebas de TicketService.generarTicket con pagos mixtos: no debe lanzar
// con uno o varios métodos, y debe producir un PDF con contenido tanto con
// cambio como sin él. No hay precedente de pruebas de PDF en el repo: se
// mantienen livianas, solo verificando que no lance y que el documento
// tenga bytes.
import 'package:flutter_test/flutter_test.dart';
import 'package:pvapp/services/ticket_service.dart';

void main() {
  final carritoDeEjemplo = [
    {'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 2, 'descuento_monto': 0.0},
  ];

  test('genera el ticket con un solo método de pago, sin cambio', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 20.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 20.0},
      ],
      cambio: 0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('genera el ticket con un solo método de pago y cambio', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 20.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
      ],
      cambio: 30,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('genera el ticket con varios métodos de pago', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 20.0,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 10.0},
        {'metodo_pago': 'Tarjeta', 'monto': 10.0},
      ],
      cambio: 0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });

  test('genera el ticket con descuento aplicado', () async {
    final pdf = await TicketService.generarTicket(
      carrito: carritoDeEjemplo,
      total: 18.0,
      subtotal: 20.0,
      descuento: 2.0,
      pagos: const [
        {'metodo_pago': 'Transferencia', 'monto': 18.0},
      ],
      cambio: 0,
    );

    final bytes = await pdf.save();
    expect(bytes, isNotEmpty);
  });
}
