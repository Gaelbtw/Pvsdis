// Cubre la reorganización del menú de inicio: el Administrador ve
// únicamente Productos/Ventas/Inventario/Clientes/Proveedores/Compras/Caja
// (Usuarios, Reportes, Auditorías, Base de datos, Apartados, Promociones y
// Pedidos se movieron a Configuración), y el inicio de Cajero no cambia
// respecto al comportamiento previo a esta tarea.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/views/home_view.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // El grid de tarjetas (MenuCard) está pensado para pantallas de
  // escritorio; con el tamaño de superficie por defecto de flutter test
  // (800x600) desborda. Se agranda la superficie de prueba para que quepa,
  // como en una ventana real. El recuadro de usuario de CustomHeader
  // (nav_bar.dart) además desborda verticalmente sin importar el ancho —es
  // un problema de layout preexistente, ajeno a esta tarea (no se tocó su
  // estructura, solo sus colores)—, así que esos errores puntuales se
  // ignoran mientras se pumpea, para no hacer fallar esta prueba por algo
  // que no es lo que se está probando aquí.
  Future<void> pumpIgnorandoOverflow(WidgetTester tester, Widget widget) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final esOverflow = details.exception.toString().contains('overflowed');
      if (!esOverflow) original?.call(details);
    };
    await tester.pumpWidget(widget);
    await tester.pump();
    FlutterError.onError = original;
  }

  tearDown(() {
    SessionManager.clear();
  });

  testWidgets('Inicio de Administrador muestra únicamente los 7 módulos permitidos', (tester) async {
    await binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => binding.setSurfaceSize(null));
    SessionManager.setUser(id: 1, nombre: 'Admin', rol: 'Admin');

    await pumpIgnorandoOverflow(tester, const MaterialApp(home: HomeView()));

    for (final visible in ['Productos', 'Ventas', 'Inventario', 'Clientes', 'Proveedores', 'Compras', 'Caja']) {
      expect(find.text(visible), findsOneWidget, reason: '"$visible" debería estar en el inicio de Admin');
    }

    for (final oculto in ['Usuarios', 'Reportes', 'Auditorias', 'Base de datos', 'Apartados', 'Promociones', 'Pedidos']) {
      expect(find.text(oculto), findsNothing, reason: '"$oculto" no debería estar en el inicio de Admin');
    }

    // El engrane de Configuración solo aparece para Admin.
    expect(find.byTooltip('Configuracion'), findsOneWidget);
  });

  testWidgets('Inicio de Cajero conserva sus mismas 8 tarjetas de siempre', (tester) async {
    await binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => binding.setSurfaceSize(null));
    SessionManager.setUser(id: 2, nombre: 'Cajero Uno', rol: 'Cajero');

    await pumpIgnorandoOverflow(tester, const MaterialApp(home: HomeView()));

    for (final visible in [
      'Ventas',
      'Apartados',
      'Clientes',
      'Inventario',
      'Reportes',
      'Compras',
      'Pedidos',
      'Caja',
    ]) {
      expect(find.text(visible), findsOneWidget, reason: '"$visible" debería seguir en el inicio de Cajero');
    }

    for (final oculto in ['Productos', 'Proveedores', 'Usuarios', 'Promociones', 'Auditorias', 'Base de datos']) {
      expect(find.text(oculto), findsNothing, reason: '"$oculto" no debe aparecer para Cajero');
    }

    // Un Cajero no debe poder llegar a Configuración desde el inicio.
    expect(find.byTooltip('Configuracion'), findsNothing);
  });
}
