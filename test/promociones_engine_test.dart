// Pruebas del motor de promociones automáticas (puro, sin base de datos ni
// Flutter): cada tipo de promoción, prioridades, combinabilidad,
// exclusividad a nivel de unidad, cantidades parciales y combos repetidos.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/core/utils/promociones_engine.dart';
import 'package:pvapp/models/promocion_model.dart';

void main() {
  Map<String, dynamic> item({
    required int id,
    required String nombre,
    required double precio,
    required int cantidad,
    int? categoria,
  }) {
    return {
      'id_producto': id,
      'nombre': nombre,
      'precio': precio,
      'cantidad': cantidad,
      'id_categoria': categoria,
    };
  }

  Promocion promo({
    int? id,
    String nombre = 'Promo',
    required TipoPromocion tipo,
    int prioridad = 0,
    bool combinable = false,
    double? valor,
    TipoDescuento? tipoValor,
    int? cantidadMinima,
    int? nxLleva,
    int? nxPaga,
    double? precioCombo,
    List<int> productos = const [],
    List<int> categorias = const [],
    List<ComboItem> comboItems = const [],
  }) {
    return Promocion(
      idPromocion: id,
      nombre: nombre,
      tipo: tipo,
      activo: true,
      prioridad: prioridad,
      combinable: combinable,
      valor: valor,
      tipoValor: tipoValor,
      cantidadMinima: cantidadMinima,
      nxLleva: nxLleva,
      nxPaga: nxPaga,
      precioCombo: precioCombo,
      productosIds: productos,
      categoriasIds: categorias,
      comboItems: comboItems,
    );
  }

  group('sin promociones o carrito vacío', () {
    test('carrito vacío no lanza y devuelve vacío', () {
      final r = evaluarPromociones(carrito: [], promocionesActivas: [
        promo(tipo: TipoPromocion.porcentajeProducto, valor: 10, productos: [1]),
      ]);
      expect(r.aplicaciones, isEmpty);
      expect(r.ahorroTotal, 0);
    });

    test('sin promociones activas no aplica nada', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 2)],
        promocionesActivas: [],
      );
      expect(r.descuentoPorLinea, [0.0]);
      expect(r.aplicaciones, isEmpty);
    });

    test('promoción sin productos/categorías que hagan match no aplica', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 2)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.porcentajeProducto, valor: 10, productos: [99]),
        ],
      );
      expect(r.descuentoPorLinea, [0.0]);
      expect(r.aplicaciones, isEmpty);
    });
  });

  group('PORCENTAJE_PRODUCTO', () {
    test('aplica el porcentaje a todas las unidades de la línea', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 3)],
        promocionesActivas: [
          promo(nombre: '10% en A', tipo: TipoPromocion.porcentajeProducto, valor: 10, productos: [1]),
        ],
      );
      // 10% de 100 = 10 por unidad x 3 = 30
      expect(r.descuentoPorLinea, [30.0]);
      expect(r.ahorroTotal, 30.0);
      expect(r.aplicaciones, hasLength(1));
      expect(r.aplicaciones.first.lineas.first.cantidadAfectada, 3);
    });

    test('matchea por categoría cuando no hay match directo de producto', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 50, cantidad: 2, categoria: 7)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.porcentajeProducto, valor: 20, categorias: [7]),
        ],
      );
      expect(r.descuentoPorLinea, [20.0]); // 20% de 50 = 10 x 2
    });
  });

  group('MONTO_FIJO_PRODUCTO', () {
    test('aplica el monto fijo por unidad, sin superar el precio', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 15, cantidad: 4)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.montoFijoProducto, valor: 5, productos: [1]),
        ],
      );
      expect(r.descuentoPorLinea, [20.0]); // 5 x 4
    });

    test('el descuento fijo nunca excede el precio unitario', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 8, cantidad: 1)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.montoFijoProducto, valor: 50, productos: [1]),
        ],
      );
      expect(r.descuentoPorLinea, [8.0]);
    });
  });

  group('NXY (Compra X y paga Y)', () {
    test('2x1 exacto: cada 2 unidades, 1 gratis', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 4)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.nxy, nxLleva: 2, nxPaga: 1, productos: [1]),
        ],
      );
      // 4 unidades -> 2 grupos completos -> 2 unidades gratis -> ahorro 20
      expect(r.descuentoPorLinea, [20.0]);
    });

    test('3x2 con sobrante: las unidades que no completan grupo no reciben descuento', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 5)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.nxy, nxLleva: 3, nxPaga: 2, productos: [1]),
        ],
      );
      // 5 unidades -> 1 grupo completo (3) -> 1 gratis; las 2 restantes no alcanzan grupo
      expect(r.descuentoPorLinea, [10.0]);
    });

    test('menos unidades que el mínimo del grupo no aplica descuento', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 1)],
        promocionesActivas: [
          promo(tipo: TipoPromocion.nxy, nxLleva: 2, nxPaga: 1, productos: [1]),
        ],
      );
      expect(r.descuentoPorLinea, [0.0]);
      expect(r.aplicaciones, isEmpty);
    });

    test('la cantidad se cuenta por producto individual, no sumando entre productos', () {
      final r = evaluarPromociones(
        carrito: [
          item(id: 1, nombre: 'A', precio: 10, cantidad: 1, categoria: 5),
          item(id: 2, nombre: 'B', precio: 10, cantidad: 1, categoria: 5),
        ],
        promocionesActivas: [
          promo(tipo: TipoPromocion.nxy, nxLleva: 2, nxPaga: 1, categorias: [5]),
        ],
      );
      // 1 unidad de A y 1 de B no se combinan: ninguna línea completa el grupo de 2.
      expect(r.descuentoPorLinea, [0.0, 0.0]);
    });
  });

  group('DESCUENTO_CANTIDAD (escalonado)', () {
    test('por debajo del mínimo no aplica descuento', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 3)],
        promocionesActivas: [
          promo(
            tipo: TipoPromocion.descuentoCantidad,
            cantidadMinima: 5,
            tipoValor: TipoDescuento.porcentaje,
            valor: 10,
            productos: [1],
          ),
        ],
      );
      expect(r.descuentoPorLinea, [0.0]);
    });

    test('solo el excedente sobre el mínimo recibe el descuento', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 6)],
        promocionesActivas: [
          promo(
            tipo: TipoPromocion.descuentoCantidad,
            cantidadMinima: 5,
            tipoValor: TipoDescuento.porcentaje,
            valor: 10,
            productos: [1],
          ),
        ],
      );
      // 6 unidades, mínimo 5 -> excedente 1 unidad; 10% de 10 = 1
      expect(r.descuentoPorLinea, [1.0]);
      expect(r.aplicaciones.first.lineas.first.cantidadAfectada, 1);
    });

    test('funciona también con descuento fijo por unidad', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 20, cantidad: 8)],
        promocionesActivas: [
          promo(
            tipo: TipoPromocion.descuentoCantidad,
            cantidadMinima: 5,
            tipoValor: TipoDescuento.fijo,
            valor: 3,
            productos: [1],
          ),
        ],
      );
      // excedente 3 unidades x $3 = 9
      expect(r.descuentoPorLinea, [9.0]);
    });
  });

  group('COMBO', () {
    test('forma un combo con productos de distinto precio y reparte el ahorro proporcionalmente', () {
      final r = evaluarPromociones(
        carrito: [
          item(id: 1, nombre: 'Burger', precio: 60, cantidad: 1),
          item(id: 2, nombre: 'Papas', precio: 30, cantidad: 1),
          item(id: 3, nombre: 'Refresco', precio: 10, cantidad: 1),
        ],
        promocionesActivas: [
          promo(
            nombre: 'Combo',
            tipo: TipoPromocion.combo,
            precioCombo: 80,
            comboItems: [
              const ComboItem(idProducto: 1, cantidad: 1),
              const ComboItem(idProducto: 2, cantidad: 1),
              const ComboItem(idProducto: 3, cantidad: 1),
            ],
          ),
        ],
      );
      // normal 100, combo 80 -> ahorro 20, repartido proporcional a 60/30/10
      expect(r.ahorroTotal, 20.0);
      expect(r.descuentoPorLinea[0], 12.0); // 60/100 * 20
      expect(r.descuentoPorLinea[1], 6.0); // 30/100 * 20
      expect(r.descuentoPorLinea[2], 2.0); // 10/100 * 20
    });

    test('combos repetidos: se forman tantas instancias como alcancen las unidades', () {
      final r = evaluarPromociones(
        carrito: [
          item(id: 1, nombre: 'Burger', precio: 60, cantidad: 2),
          item(id: 2, nombre: 'Refresco', precio: 10, cantidad: 3),
        ],
        promocionesActivas: [
          promo(
            tipo: TipoPromocion.combo,
            precioCombo: 60,
            comboItems: [
              const ComboItem(idProducto: 1, cantidad: 1),
              const ComboItem(idProducto: 2, cantidad: 1),
            ],
          ),
        ],
      );
      // min(2/1, 3/1) = 2 instancias formables; normal 2*(60+10)=140, combo 2*60=120 -> ahorro 20
      expect(r.ahorroTotal, 20.0);
      expect(r.aplicaciones.first.lineas.firstWhere((l) => l.idProducto == 1).cantidadAfectada, 2);
      expect(r.aplicaciones.first.lineas.firstWhere((l) => l.idProducto == 2).cantidadAfectada, 2);
    });

    test('si falta un producto del combo en el carrito, no se forma ninguna instancia', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'Burger', precio: 60, cantidad: 3)],
        promocionesActivas: [
          promo(
            tipo: TipoPromocion.combo,
            precioCombo: 60,
            comboItems: [
              const ComboItem(idProducto: 1, cantidad: 1),
              const ComboItem(idProducto: 2, cantidad: 1),
            ],
          ),
        ],
      );
      expect(r.descuentoPorLinea, [0.0]);
      expect(r.aplicaciones, isEmpty);
    });

    test('si el precio del combo no ahorra nada, no se aplica', () {
      final r = evaluarPromociones(
        carrito: [
          item(id: 1, nombre: 'A', precio: 10, cantidad: 1),
          item(id: 2, nombre: 'B', precio: 10, cantidad: 1),
        ],
        promocionesActivas: [
          promo(
            tipo: TipoPromocion.combo,
            precioCombo: 25, // más caro que comprar separado (20)
            comboItems: [
              const ComboItem(idProducto: 1, cantidad: 1),
              const ComboItem(idProducto: 2, cantidad: 1),
            ],
          ),
        ],
      );
      expect(r.aplicaciones, isEmpty);
    });
  });

  group('prioridad y exclusividad de unidades', () {
    test('a mayor prioridad, se procesa primero y reclama las unidades', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1)],
        promocionesActivas: [
          promo(nombre: 'Baja', tipo: TipoPromocion.porcentajeProducto, valor: 5, prioridad: 1, productos: [1]),
          promo(nombre: 'Alta', tipo: TipoPromocion.porcentajeProducto, valor: 50, prioridad: 10, productos: [1]),
        ],
      );
      // La de prioridad 10 reclama la única unidad; la de prioridad 1 no tiene nada disponible.
      expect(r.aplicaciones, hasLength(1));
      expect(r.aplicaciones.first.nombre, 'Alta');
      expect(r.descuentoPorLinea, [50.0]);
    });

    test('promociones no combinables no pueden compartir la misma unidad', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1)],
        promocionesActivas: [
          promo(nombre: 'P1', tipo: TipoPromocion.porcentajeProducto, valor: 10, prioridad: 5, productos: [1]),
          promo(nombre: 'P2', tipo: TipoPromocion.porcentajeProducto, valor: 20, prioridad: 1, productos: [1]),
        ],
      );
      // P1 (mayor prioridad) reclama la unidad de forma exclusiva; P2 no aplica.
      expect(r.aplicaciones, hasLength(1));
      expect(r.aplicaciones.first.nombre, 'P1');
      expect(r.descuentoPorLinea, [10.0]);
    });

    test('dos promociones combinables sí pueden aplicar sobre la misma unidad', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1)],
        promocionesActivas: [
          promo(
            nombre: 'P1',
            tipo: TipoPromocion.porcentajeProducto,
            valor: 10,
            prioridad: 5,
            combinable: true,
            productos: [1],
          ),
          promo(
            nombre: 'P2',
            tipo: TipoPromocion.porcentajeProducto,
            valor: 5,
            prioridad: 1,
            combinable: true,
            productos: [1],
          ),
        ],
      );
      expect(r.aplicaciones, hasLength(2));
      expect(r.descuentoPorLinea, [15.0]); // 10 + 5
    });

    test('una promoción combinable no puede reclamar una unidad ya bloqueada por una no combinable', () {
      final r = evaluarPromociones(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1)],
        promocionesActivas: [
          promo(
            nombre: 'Exclusiva',
            tipo: TipoPromocion.porcentajeProducto,
            valor: 10,
            prioridad: 5,
            combinable: false,
            productos: [1],
          ),
          promo(
            nombre: 'Combinable',
            tipo: TipoPromocion.porcentajeProducto,
            valor: 5,
            prioridad: 1,
            combinable: true,
            productos: [1],
          ),
        ],
      );
      expect(r.aplicaciones, hasLength(1));
      expect(r.aplicaciones.first.nombre, 'Exclusiva');
      expect(r.descuentoPorLinea, [10.0]);
    });
  });

  group('interacción con calcularVenta', () {
    test('el descuento de promoción reduce la base antes del descuento manual', () {
      final resultado = evaluarPromociones(
        carrito: [
          {
            'id_producto': 1,
            'nombre': 'A',
            'precio': 100.0,
            'cantidad': 1,
            'descuento_tipo': TipoDescuento.porcentaje,
            'descuento_valor': 10.0,
          },
        ],
        promocionesActivas: [
          promo(tipo: TipoPromocion.porcentajeProducto, valor: 20, productos: [1]),
        ],
      );

      final v = calcularVenta(
        carrito: [
          {
            'id_producto': 1,
            'nombre': 'A',
            'precio': 100.0,
            'cantidad': 1,
            'descuento_tipo': TipoDescuento.porcentaje,
            'descuento_valor': 10.0,
          },
        ],
        descuentosPromocionPorLinea: resultado.descuentoPorLinea,
        descuentoMaximoPorcentaje: 100,
      );

      // Promo 20% de 100 = 20 -> base 80; descuento manual 10% de 80 = 8 -> total 72
      expect(v.descuentoPromocionTotal, 20.0);
      expect(v.lineas.first.descuentoMonto, 8.0);
      expect(v.total, 72.0);
      // Las promociones no activan requiereAutorizacion.
      expect(v.requiereAutorizacion, isFalse);
    });
  });
}
