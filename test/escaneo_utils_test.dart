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
    expect(resultado.mensaje, contains('Stock insuficiente'));
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
}
