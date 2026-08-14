// Pruebas de las piezas en que se partió la pantalla de ventas.
//
// Antes todo esto vivía dentro del `build` de `ventas_view.dart`, anidado
// una decena de niveles y atado a la base de datos, así que no había forma de
// probarlo sin levantar la app entera. Extraído en widgets sin estado, cada
// pieza se puede montar sola: es la red que sustituye a la revisión visual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/core/utils/promociones_engine.dart';
import 'package:pvapp/models/cliente_model.dart';
import 'package:pvapp/models/producto_model.dart';
import 'package:pvapp/widgets/ventas/catalogo_productos.dart';
import 'package:pvapp/widgets/ventas/linea_carrito.dart';
import 'package:pvapp/widgets/ventas/panel_carrito.dart';
import 'package:pvapp/widgets/ventas/panel_cobro.dart';

/// Monta [hijo] en un lienzo del tamaño que realmente ocupa en la app.
///
/// El lienzo por defecto de las pruebas es de 800x600, y esta pantalla está
/// hecha para una ventana de escritorio: sin agrandarlo, los paneles se
/// desbordan y el fallo sería del tamaño de la prueba, no del widget.
Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  double ancho = 760,
  double alto = 620,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: ancho, height: alto, child: hijo),
        ),
      ),
    ),
  );
}

const _refresco = Producto(
  idProducto: 1,
  nombre: 'Refresco',
  descripcion: '',
  precio: 18.5,
  estado: 'Activo',
  stockMinimo: 3,
);

const _agotado = Producto(
  idProducto: 2,
  nombre: 'Galletas',
  descripcion: '',
  precio: 12,
  estado: 'Activo',
);

const _inactivo = Producto(
  idProducto: 3,
  nombre: 'Descontinuado',
  descripcion: '',
  precio: 30,
  estado: 'Inactivo',
);

LineaVentaCalculada _linea({
  int cantidad = 2,
  double precio = 18.5,
  double descuento = 0,
}) {
  final subtotal = precio * cantidad;
  return LineaVentaCalculada(
    idProducto: 1,
    nombre: 'Refresco',
    precioOriginal: precio,
    cantidad: cantidad,
    descuentoTipo: descuento > 0 ? TipoDescuento.fijo : null,
    descuentoValor: descuento,
    descuentoMonto: descuento,
    subtotalLinea: subtotal,
    montoNeto: subtotal - descuento,
    precioNetoUnitario: (subtotal - descuento) / cantidad,
  );
}

void main() {
  group('CatalogoProductos', () {
    Widget catalogo({
      required List<Producto> productos,
      required Map<int, int> existencias,
      void Function(Producto)? onAgregar,
      List<({int id, String nombre})> categorias = const [],
      int? categoriaFiltro,
      void Function(int?)? onFiltrar,
    }) {
      return CatalogoProductos(
          busquedaCtrl: TextEditingController(),
          busquedaFocus: FocusNode(),
          onBuscar: (_) {},
          onEscanear: (_) {},
          categorias: categorias,
          categoriaFiltro: categoriaFiltro,
          onFiltrarCategoria: onFiltrar ?? (_) {},
          productos: productos,
          existencias: existencias,
          onAgregar: onAgregar ?? (_) {},
      );
    }

    testWidgets('muestra la existencia de un producto disponible', (tester) async {
      await _montar(tester, catalogo(
        productos: [_refresco],
        existencias: {1: 12},
      ));

      expect(find.text('Refresco'), findsOneWidget);
      expect(find.text('Inventario: 12'), findsOneWidget);
    });

    testWidgets('un producto sin existencia se marca como agotado', (tester) async {
      await _montar(tester, catalogo(
        productos: [_agotado],
        existencias: {2: 0},
      ));

      expect(find.text('Agotado'), findsOneWidget);
      expect(find.text('Inventario: 0'), findsNothing);
    });

    testWidgets('un producto inactivo se marca como tal', (tester) async {
      await _montar(tester, catalogo(
        productos: [_inactivo],
        existencias: {3: 50},
      ));

      expect(find.text('Inactivo'), findsOneWidget);
    });

    testWidgets('tocar la tarjeta avisa a la vista, que es quien decide', (tester) async {
      Producto? agregado;

      // Se ofrece un producto agotado a propósito: el catálogo NO bloquea, solo
      // avisa; la regla de existencias vive en la vista (ver
      // validarCantidadEnCarrito), y así el cajero recibe el motivo en vez de
      // un botón muerto que no explica nada.
      await _montar(tester, catalogo(
        productos: [_agotado],
        existencias: {2: 0},
        onAgregar: (p) => agregado = p,
      ));

      await tester.tap(find.text('Galletas'));
      expect(agregado, _agotado);
    });

    testWidgets('sin categorías no se dibuja la fila de filtros', (tester) async {
      await _montar(tester, catalogo(
        productos: [_refresco],
        existencias: {1: 5},
      ));

      expect(find.text('Todos'), findsNothing);
    });

    testWidgets('con categorías se puede filtrar y quitar el filtro', (tester) async {
      final seleccionadas = <int?>[];

      await _montar(tester, catalogo(
        productos: [_refresco],
        existencias: {1: 5},
        categorias: [(id: 7, nombre: 'Bebidas')],
        categoriaFiltro: 7,
        onFiltrar: seleccionadas.add,
      ));

      expect(find.text('Bebidas'), findsOneWidget);

      await tester.tap(find.text('Todos'));
      expect(seleccionadas, [null]);
    });
  });

  group('LineaCarrito', () {
    Widget linea({
      Map<String, dynamic>? item,
      LineaVentaCalculada? calculada,
      TextEditingController? controlador,
      void Function(int)? onCambiarCantidad,
      void Function(int)? onCantidadTecleada,
      VoidCallback? onQuitar,
      bool puedeAplicarDescuentos = true,
    }) {
      return LineaCarrito(
          item: item ??
              {
                'id_producto': 1,
                'nombre': 'Refresco',
                'precio': 18.5,
                'cantidad': 2,
                'descuento_tipo': null,
                'descuento_valor': 0.0,
              },
          calculada: calculada ?? _linea(),
          cantidadCtrl: controlador ?? TextEditingController(text: '2'),
          seleccionada: false,
          puedeAplicarDescuentos: puedeAplicarDescuentos,
          onSeleccionar: () {},
          onEditarDescuento: () {},
          onCambiarCantidad: onCambiarCantidad ?? (_) {},
          onCantidadTecleada: onCantidadTecleada ?? (_) {},
          onQuitar: onQuitar ?? () {},
      );
    }

    testWidgets('muestra precio unitario e importe de la línea', (tester) async {
      await _montar(tester, linea());

      expect(find.text('\$18.50 c/u'), findsOneWidget);
      expect(find.text('\$37.00'), findsOneWidget);
    });

    testWidgets('con descuento muestra el unitario real y el de lista', (tester) async {
      await _montar(tester, linea(
        item: {
          'id_producto': 1,
          'nombre': 'Refresco',
          'precio': 18.5,
          'cantidad': 2,
          'descuento_tipo': TipoDescuento.fijo,
          'descuento_valor': 7.0,
        },
        calculada: _linea(descuento: 7),
      ));

      expect(find.textContaining('lista \$18.50'), findsOneWidget);
      expect(find.text('\$30.00'), findsOneWidget);
    });

    testWidgets('los botones + y - avisan el cambio', (tester) async {
      final deltas = <int>[];
      await _montar(tester, linea(onCambiarCantidad: deltas.add));

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.tap(find.byIcon(Icons.remove_circle_outline));

      expect(deltas, [1, -1]);
    });

    testWidgets('teclear una cantidad la reporta a la vista', (tester) async {
      final tecleadas = <int>[];
      await _montar(tester, linea(onCantidadTecleada: tecleadas.add));

      await tester.enterText(find.byType(TextField), '5');
      expect(tecleadas, [5]);
    });

    testWidgets('una cantidad inválida no se reporta', (tester) async {
      final tecleadas = <int>[];
      await _montar(tester, linea(onCantidadTecleada: tecleadas.add));

      await tester.enterText(find.byType(TextField), '0');
      await tester.enterText(find.byType(TextField), 'x');

      expect(tecleadas, isEmpty);
    });

    testWidgets('sin permiso de descuentos no aparece la etiqueta', (tester) async {
      await _montar(tester, linea(puedeAplicarDescuentos: false));
      expect(find.byIcon(Icons.sell_outlined), findsNothing);
    });

    testWidgets('quitar la línea es un botón visible, no solo un atajo', (tester) async {
      var quitadas = 0;
      await _montar(tester, linea(onQuitar: () => quitadas++));

      await tester.tap(find.byIcon(Icons.close));
      expect(quitadas, 1);
    });
  });

  group('PanelCobro', () {
    Widget cobro({required VentaCalculada venta, bool habilitado = true, VoidCallback? onConfirmar}) {
      return SingleChildScrollView(
        child: PanelCobro(
              venta: venta,
              habilitado: habilitado,
              ventaCounter: 0,
              onCambioPagos: (_, _) {},
          onConfirmar: onConfirmar ?? () {},
        ),
      );
    }

    VentaCalculada venta({double subtotal = 100, double descuento = 0}) => VentaCalculada(
          lineas: const [],
          subtotal: subtotal,
          descuentoGlobalTipo: null,
          descuentoGlobalValor: 0,
          descuentoGlobalMonto: 0,
          descuentoTotal: descuento,
          total: subtotal - descuento,
          requiereAutorizacion: false,
        );

    testWidgets('el total es el número dominante', (tester) async {
      await _montar(tester, cobro(venta: venta()));
      await tester.pump();

      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('\$100.00'), findsWidgets);
    });

    testWidgets('sin descuento no se dibuja el desglose', (tester) async {
      await _montar(tester, cobro(venta: venta()));
      await tester.pump();

      expect(find.text('Subtotal'), findsNothing);
      expect(find.text('Descuento'), findsNothing);
    });

    testWidgets('con descuento se muestran subtotal y rebaja', (tester) async {
      await _montar(tester, cobro(venta: venta(subtotal: 100, descuento: 15)));
      await tester.pump();

      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('-\$15.00'), findsOneWidget);
      expect(find.text('\$85.00'), findsWidgets);
    });

    testWidgets('el botón de cobrar se bloquea cuando no se puede vender', (tester) async {
      var confirmadas = 0;
      await _montar(tester, cobro(
        venta: venta(),
        habilitado: false,
        onConfirmar: () => confirmadas++,
      ));
      await tester.pump();

      final boton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.textContaining('Confirmar venta'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(boton.onPressed, isNull);
      expect(confirmadas, 0);
    });
  });

  group('PanelCarrito', () {
    Widget panel({
      required List<Map<String, dynamic>> items,
      VentaCalculada? venta,
      Cliente? cliente,
      VoidCallback? onElegirCliente,
      VoidCallback? onQuitarCliente,
    }) {
      return PanelCarrito(
            items: items,
            venta: venta ??
                VentaCalculada(
                  lineas: [for (var i = 0; i < items.length; i++) _linea()],
                  subtotal: 37,
                  descuentoGlobalTipo: null,
                  descuentoGlobalValor: 0,
                  descuentoGlobalMonto: 0,
                  descuentoTotal: 0,
                  total: 37,
                  requiereAutorizacion: false,
                ),
            promociones: ResultadoPromociones.vacio,
            controladoresCantidad: {},
            lineaSeleccionada: null,
            onSeleccionarLinea: (_) {},
            cliente: cliente,
            ventasEnEspera: 0,
            ultimaVentaId: null,
            puedeAplicarDescuentos: true,
            tieneDescuentoGlobal: false,
            onVerEnEspera: () {},
            onReimprimir: () {},
            onPausar: () {},
            onVaciar: () {},
            onEditarDescuentoGlobal: () {},
            onElegirCliente: onElegirCliente ?? () {},
            onQuitarCliente: onQuitarCliente ?? () {},
            onAyuda: () {},
            onEditarDescuentoLinea: (_) {},
            onCambiarCantidad: (_, _) {},
            onCantidadTecleada: (_, _) {},
            onQuitarLinea: (_) {},
        cobro: const SizedBox.shrink(),
      );
    }

    testWidgets('sin productos avisa que el carrito está vacío', (tester) async {
      await _montar(tester, panel(items: []));

      expect(find.text('No hay productos'), findsOneWidget);
      // Sin venta en curso no se ofrecen pausar ni vaciar.
      expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
      expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsNothing);
    });

    testWidgets('con productos aparecen pausar y vaciar', (tester) async {
      await _montar(tester, panel(items: [
        {
          'id_producto': 1,
          'nombre': 'Refresco',
          'precio': 18.5,
          'cantidad': 2,
          'descuento_tipo': null,
          'descuento_valor': 0.0,
        },
      ]));

      expect(find.text('Refresco'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsOneWidget);
    });

    testWidgets('sin cliente ofrece asignarlo desde la propia venta', (tester) async {
      var abiertos = 0;
      await _montar(
        tester,
        panel(items: [], onElegirCliente: () => abiertos++),
        ancho: 480,
        alto: 820,
      );

      expect(find.textContaining('Asignar cliente'), findsOneWidget);

      await tester.tap(find.textContaining('Asignar cliente'));
      expect(abiertos, 1);
    });

    testWidgets('con cliente lo muestra y permite quitarlo', (tester) async {
      var quitados = 0;
      await _montar(
        tester,
        panel(
          items: [],
          cliente: Cliente(
            idCliente: 3,
            nombre: 'Panadería La Central',
            direccion: null,
            telefono: null,
            correo: null,
            fechaRegistro: '2026-01-01',
          ),
          onQuitarCliente: () => quitados++,
        ),
        ancho: 480,
        alto: 820,
      );

      expect(find.text('Panadería La Central'), findsOneWidget);
      expect(find.textContaining('Asignar cliente'), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      expect(quitados, 1);
    });

    testWidgets('crea el controlador de una línea que no lo traía', (tester) async {
      // Cubre el caso que antes reventaba la pantalla completa con un `!`.
      await _montar(tester, panel(items: [
        {
          'id_producto': 9,
          'nombre': 'Sin controlador',
          'precio': 5.0,
          'cantidad': 3,
          'descuento_tipo': null,
          'descuento_valor': 0.0,
        },
      ]));

      expect(find.text('Sin controlador'), findsOneWidget);
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
    });
  });
}
