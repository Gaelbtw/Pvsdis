// Pruebas de la lógica de decisión de escaneo (sin base de datos ni
// Flutter): dado un código, la lista de productos en memoria, el stock
// disponible y cuánto hay ya en el carrito, decide qué debe pasar.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/escaneo_utils.dart';
import 'package:pvapp/models/producto_model.dart';

void main() {
  const activo = Producto(
    idProducto: 1,
    nombre: 'Refresco',
    descripcion: '',
    precio: 18.5,
    estado: 'Activo',
    codigoBarras: '7501234567890',
  );

  const inactivo = Producto(
    idProducto: 2,
    nombre: 'Descontinuado',
    descripcion: '',
    precio: 10,
    estado: 'Inactivo',
    codigoBarras: '111',
  );

  final productos = [activo, inactivo];

  test('código encontrado, activo y con stock: se agrega', () {
    final resultado = resolverEscaneo(
      codigo: '7501234567890',
      productos: productos,
      stockDisponible: {1: 5, 2: 5},
      cantidadEnCarrito: (_) => 0,
    );

    expect(resultado.tipo, TipoResultadoEscaneo.agregado);
    expect(resultado.producto, activo);
  });

  test('código no encontrado', () {
    final resultado = resolverEscaneo(
      codigo: 'no-existe',
      productos: productos,
      stockDisponible: {1: 5, 2: 5},
      cantidadEnCarrito: (_) => 0,
    );

    expect(resultado.tipo, TipoResultadoEscaneo.noEncontrado);
    expect(resultado.mensaje, contains('no encontrado'));
  });

  test('código vacío se trata como no encontrado', () {
    final resultado = resolverEscaneo(
      codigo: '   ',
      productos: productos,
      stockDisponible: {1: 5},
      cantidadEnCarrito: (_) => 0,
    );

    expect(resultado.tipo, TipoResultadoEscaneo.noEncontrado);
  });

  test('producto inactivo no se puede vender', () {
    final resultado = resolverEscaneo(
      codigo: '111',
      productos: productos,
      stockDisponible: {2: 5},
      cantidadEnCarrito: (_) => 0,
    );

    expect(resultado.tipo, TipoResultadoEscaneo.inactivo);
    expect(resultado.mensaje, contains('inactivo'));
  });

  test('sin stock suficiente para una unidad más', () {
    final resultado = resolverEscaneo(
      codigo: '7501234567890',
      productos: productos,
      stockDisponible: {1: 1},
      cantidadEnCarrito: (_) => 1, // ya hay 1 en el carrito, stock es 1
    );

    expect(resultado.tipo, TipoResultadoEscaneo.stockInsuficiente);
    expect(resultado.mensaje, contains('Inventario insuficiente'));
  });

  test('ya está en el carrito pero todavía hay stock: se agrega otra unidad', () {
    final resultado = resolverEscaneo(
      codigo: '7501234567890',
      productos: productos,
      stockDisponible: {1: 5},
      cantidadEnCarrito: (_) => 2,
    );

    expect(resultado.tipo, TipoResultadoEscaneo.agregado);
  });

  group('búsqueda por clave interna (SKU)', () {
    const aGranel = Producto(
      idProducto: 3,
      nombre: 'Frijol a granel',
      descripcion: '',
      precio: 32,
      estado: 'Activo',
      sku: 'GRA-010',
    );

    // Un producto cuyo SKU coincide con el código de barras de otro: sirve
    // para fijar cuál gana.
    const conflictivo = Producto(
      idProducto: 4,
      nombre: 'Producto con clave prestada',
      descripcion: '',
      precio: 5,
      estado: 'Activo',
      sku: '7501234567890',
    );

    test('un producto sin código de barras se encuentra por su SKU', () {
      final resultado = resolverEscaneo(
        codigo: 'GRA-010',
        productos: [activo, aGranel],
        stockDisponible: {1: 5, 3: 5},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.tipo, TipoResultadoEscaneo.agregado);
      expect(resultado.producto, aGranel);
    });

    test('el SKU también respeta el espacio sobrante del lector', () {
      final resultado = resolverEscaneo(
        codigo: '  GRA-010 ',
        productos: [aGranel],
        stockDisponible: {3: 5},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.tipo, TipoResultadoEscaneo.agregado);
    });

    test('el código de barras gana sobre un SKU que valga lo mismo', () {
      final resultado = resolverEscaneo(
        codigo: '7501234567890',
        productos: [conflictivo, activo],
        stockDisponible: {1: 5, 4: 5},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.producto, activo);
    });

    test('un SKU inexistente sigue siendo código no encontrado', () {
      final resultado = resolverEscaneo(
        codigo: 'GRA-999',
        productos: [activo, aGranel],
        stockDisponible: {1: 5, 3: 5},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.tipo, TipoResultadoEscaneo.noEncontrado);
    });
  });

  group('multiplicador de cantidad', () {
    test('separa cantidad y código con los distintos separadores', () {
      for (final texto in ['12*750123', '12x750123', '12X750123', '12 × 750123']) {
        final entrada = interpretarEntradaEscaneo(texto);
        expect(entrada.tieneMultiplicador, isTrue, reason: texto);
        expect(entrada.cantidad, 12, reason: texto);
        expect(entrada.codigo, '750123', reason: texto);
      }
    });

    test('un texto normal no lleva multiplicador', () {
      final entrada = interpretarEntradaEscaneo('7501234567890');

      expect(entrada.tieneMultiplicador, isFalse);
      expect(entrada.cantidad, 1);
      expect(entrada.codigo, '7501234567890');
    });

    test('cero piezas no es una cantidad: se trata como texto normal', () {
      final entrada = interpretarEntradaEscaneo('0*750123');

      expect(entrada.tieneMultiplicador, isFalse);
      expect(entrada.cantidad, 1);
    });

    test('escanear con multiplicador agrega esa cantidad de golpe', () {
      final resultado = resolverEscaneo(
        codigo: '12*7501234567890',
        productos: productos,
        stockDisponible: {1: 50},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.tipo, TipoResultadoEscaneo.agregado);
      expect(resultado.producto, activo);
      expect(resultado.cantidad, 12);
    });

    test('el multiplicador respeta la existencia disponible', () {
      final resultado = resolverEscaneo(
        codigo: '12*7501234567890',
        productos: productos,
        stockDisponible: {1: 5},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.tipo, TipoResultadoEscaneo.stockInsuficiente);
      expect(resultado.mensaje, contains('solo quedan 5'));
    });

    test('cuenta lo que ya está en el carrito', () {
      final resultado = resolverEscaneo(
        codigo: '3*7501234567890',
        productos: productos,
        stockDisponible: {1: 5},
        cantidadEnCarrito: (_) => 3, // 3 + 3 = 6 > 5
      );

      expect(resultado.tipo, TipoResultadoEscaneo.stockInsuficiente);
    });

    test('una clave que se parece a un multiplicador gana como código', () {
      // Un SKU '3X4' debe encontrar SU producto, no leerse como "3 piezas del 4".
      const conClaveAmbigua = Producto(
        idProducto: 5,
        nombre: 'Tornillo 3X4',
        descripcion: '',
        precio: 2,
        estado: 'Activo',
        sku: '3X4',
      );
      const producto4 = Producto(
        idProducto: 6,
        nombre: 'Otro',
        descripcion: '',
        precio: 9,
        estado: 'Activo',
        sku: '4',
      );

      final resultado = resolverEscaneo(
        codigo: '3X4',
        productos: [conClaveAmbigua, producto4],
        stockDisponible: {5: 10, 6: 10},
        cantidadEnCarrito: (_) => 0,
      );

      expect(resultado.producto, conClaveAmbigua);
      expect(resultado.cantidad, 1);
    });
  });
}
