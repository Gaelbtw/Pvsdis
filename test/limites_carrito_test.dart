// Pruebas de la regla de "cuánto puedo vender de esto".
//
// Vive aparte de la pantalla justamente para poder probarse así: antes esta
// decisión existía SOLO dentro del escáner, y los otros tres caminos para
// agregar al carrito (tocar la tarjeta, el botón +, teclear la cantidad) no la
// aplicaban.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/limites_carrito.dart';
import 'package:pvapp/models/producto_model.dart';

void main() {
  const activo = Producto(
    idProducto: 1,
    nombre: 'Refresco',
    descripcion: '',
    precio: 18.5,
    estado: 'Activo',
  );

  const inactivo = Producto(
    idProducto: 2,
    nombre: 'Descontinuado',
    descripcion: '',
    precio: 10,
    estado: 'Inactivo',
  );

  test('deja agregar mientras alcance la existencia', () {
    final limite = validarCantidadEnCarrito(
      producto: activo,
      cantidadDeseada: 3,
      disponible: 5,
    );

    expect(limite.permitido, isTrue);
    expect(limite.maximo, 5);
    expect(limite.mensaje, isEmpty);
  });

  test('permite llevarse hasta la última pieza', () {
    final limite = validarCantidadEnCarrito(
      producto: activo,
      cantidadDeseada: 5,
      disponible: 5,
    );

    expect(limite.permitido, isTrue);
  });

  test('rechaza una pieza más de las que hay, y dice cuántas quedan', () {
    final limite = validarCantidadEnCarrito(
      producto: activo,
      cantidadDeseada: 6,
      disponible: 5,
    );

    expect(limite.permitido, isFalse);
    expect(limite.motivo, MotivoRechazoLinea.existenciaInsuficiente);
    expect(limite.maximo, 5, reason: 'la vista recorta la cantidad tecleada a esto');
    expect(limite.mensaje, contains('Inventario insuficiente'));
    expect(limite.mensaje, contains('5'));
  });

  test('sin existencia se distingue de "no alcanza"', () {
    final limite = validarCantidadEnCarrito(
      producto: activo,
      cantidadDeseada: 1,
      disponible: 0,
    );

    expect(limite.permitido, isFalse);
    expect(limite.motivo, MotivoRechazoLinea.sinExistencia);
    expect(limite.maximo, 0);
    expect(limite.mensaje, contains('No queda inventario'));
  });

  test('un producto inactivo no se vende aunque queden piezas', () {
    final limite = validarCantidadEnCarrito(
      producto: inactivo,
      cantidadDeseada: 1,
      disponible: 100,
    );

    expect(limite.permitido, isFalse);
    expect(limite.motivo, MotivoRechazoLinea.inactivo);
    expect(limite.maximo, 0);
    expect(limite.mensaje, contains('inactivo'));
  });

  test('una existencia negativa (dato inconsistente) se trata como cero', () {
    final limite = validarCantidadEnCarrito(
      producto: activo,
      cantidadDeseada: 1,
      disponible: -3,
    );

    expect(limite.permitido, isFalse);
    expect(limite.motivo, MotivoRechazoLinea.sinExistencia);
    expect(limite.maximo, 0);
  });

  test('el mensaje nombra al producto para que el cajero sepa cuál es', () {
    final limite = validarCantidadEnCarrito(
      producto: activo,
      cantidadDeseada: 9,
      disponible: 2,
    );

    expect(limite.mensaje, contains('Refresco'));
  });
}
