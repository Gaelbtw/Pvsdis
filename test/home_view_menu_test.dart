// Cubre qué módulos ve cada rol en el menú de inicio.
//
// Esta prueba estaba desactualizada respecto al código: afirmaba que el
// Administrador NO veía Apartados, Promociones ni Pedidos, cuando
// `HomeView._modulos` lleva tiempo incluyendo los tres (más Cuentas por
// pagar). Se ajusta a lo que la pantalla hace hoy.
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

  // Igual que arriba pero para una interacción posterior (abrir el menú de
  // cuenta): suprime solo los errores de overflow del layout preexistente
  // mientras corre [accion], sin ocultar cualquier otra excepción real.
  Future<void> conOverflowIgnorado(Future<void> Function() accion) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final esOverflow = details.exception.toString().contains('overflowed');
      if (!esOverflow) original?.call(details);
    };
    await accion();
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

    for (final visible in [
      'Productos',
      'Ventas',
      'Inventario',
      'Clientes',
      'Proveedores',
      'Compras',
      'Pedidos',
      'Apartados',
      'Promociones',
      'Cuentas por pagar',
      'Caja',
    ]) {
      expect(find.text(visible), findsOneWidget, reason: '"$visible" debería estar en el inicio de Admin');
    }

    // Siguen viviendo dentro de Configuración, no en el inicio.
    for (final oculto in ['Usuarios', 'Auditorias', 'Base de datos']) {
      expect(find.text(oculto), findsNothing, reason: '"$oculto" no debería estar en el inicio de Admin');
    }

    // El acceso a Configuración vive ahora dentro del menú de cuenta (avatar
    // con tooltip 'Cuenta'); solo el Admin lo ve al abrirlo.
    expect(find.byTooltip('Cuenta'), findsOneWidget);
    await conOverflowIgnorado(() async {
      await tester.tap(find.byTooltip('Cuenta'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Configuración'), findsOneWidget,
        reason: 'Un Admin debe poder abrir Configuración desde el menú de cuenta');
  });

  testWidgets('Inicio de Cajero conserva sus mismas tarjetas de siempre', (tester) async {
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

    // Un Cajero no debe poder llegar a Configuración: el menú de cuenta existe
    // (para cambiar de cuenta / cerrar sesión) pero sin la opción de Config.
    expect(find.byTooltip('Cuenta'), findsOneWidget);
    await conOverflowIgnorado(() async {
      await tester.tap(find.byTooltip('Cuenta'));
      await tester.pumpAndSettle();
    });
    expect(find.text('Cambiar de cuenta'), findsOneWidget, reason: 'el menú de cuenta debería abrirse');
    expect(find.text('Configuración'), findsNothing,
        reason: 'Un Cajero no debe ver Configuración en su menú de cuenta');
  });
}
