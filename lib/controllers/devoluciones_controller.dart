import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../core/sync/bitacoras/movimiento_caja_logger.dart';
import '../core/utils/money.dart';
import 'producto_controller.dart';

/// Detalle completo de una venta para la pantalla de devoluciones: sus
/// líneas (con lo vendido/devuelto/pendiente por producto) y el historial
/// de devoluciones ya aplicadas.
class VentaDetalle {
  final int idVenta;
  final String fecha;
  final String estado;
  final double total;
  final String metodoPago;
  final String? cliente;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> devoluciones;

  const VentaDetalle({
    required this.idVenta,
    required this.fecha,
    required this.estado,
    required this.total,
    required this.metodoPago,
    required this.cliente,
    required this.items,
    required this.devoluciones,
  });
}

/// Datos ya armados para imprimir el comprobante de una devolución.
class ComprobanteDevolucion {
  final int idDevolucion;
  final int idVenta;
  final String fechaHora;
  final String tipo;
  final String motivo;
  final String usuario;
  final double importe;
  final List<Map<String, dynamic>> items;

  const ComprobanteDevolucion({
    required this.idDevolucion,
    required this.idVenta,
    required this.fechaHora,
    required this.tipo,
    required this.motivo,
    required this.usuario,
    required this.importe,
    required this.items,
  });
}

/// Cancelaciones y devoluciones parciales de ventas ya registradas.
///
/// La venta original y `Detalle_Venta` nunca se modifican ni se borran: lo
/// vendido, lo devuelto y lo pendiente por devolver se calculan siempre a
/// partir de `Detalle_Venta` vs. `Detalle_Devolucion`, así que una
/// cancelación total es, internamente, una devolución que cubre todo lo que
/// aún esté pendiente de cada producto.
class DevolucionesController {
  final _productoController = ProductoController();
  final _movimientoCajaLogger = MovimientoCajaLogger();

  Future<VentaDetalle> obtenerDetalleVenta(int idVenta) async {
    final db = await DatabaseHelper().database;

    final ventaRows = await db.rawQuery('''
      SELECT Ventas.*, Clientes.nombre as cliente_nombre
      FROM Ventas
      LEFT JOIN Clientes ON Clientes.id_cliente = Ventas.id_cliente
      WHERE Ventas.id_venta = ?
    ''', [idVenta]);

    if (ventaRows.isEmpty) {
      throw Exception('La venta no existe.');
    }
    final venta = ventaRows.first;

    final vendidos = await db.rawQuery('''
      SELECT dv.id_producto, p.nombre, dv.precio, dv.precio_neto, SUM(dv.cantidad) as cantidad_vendida
      FROM Detalle_Venta dv
      INNER JOIN Producto p ON p.id_producto = dv.id_producto
      WHERE dv.id_venta = ?
      GROUP BY dv.id_producto, dv.precio, dv.precio_neto
    ''', [idVenta]);

    final devueltoPorProducto = await _devueltoPorProducto(db, idVenta);

    final items = vendidos.map((row) {
      final idProducto = row['id_producto'] as int;
      final vendida = (row['cantidad_vendida'] as num).toInt();
      final devuelta = devueltoPorProducto[idProducto] ?? 0;

      return {
        'id_producto': idProducto,
        'nombre': row['nombre'],
        'precio': row['precio'],
        'precio_neto': row['precio_neto'] ?? row['precio'],
        'cantidad_vendida': vendida,
        'cantidad_devuelta': devuelta,
        'cantidad_pendiente': vendida - devuelta,
      };
    }).toList();

    final devoluciones = await db.rawQuery('''
      SELECT d.id_devolucion, d.fecha_hora, d.tipo, d.motivo, d.importe,
             u.nombre as usuario_nombre
      FROM Devoluciones d
      LEFT JOIN Usuarios u ON u.id_usuario = d.id_usuario
      WHERE d.id_venta = ?
      ORDER BY d.fecha_hora DESC
    ''', [idVenta]);

    return VentaDetalle(
      idVenta: idVenta,
      fecha: venta['fecha']?.toString() ?? '',
      estado: venta['estado']?.toString() ?? 'Activa',
      total: (venta['total'] as num?)?.toDouble() ?? 0,
      metodoPago: venta['metodo_pago']?.toString() ?? 'efectivo',
      cliente: venta['cliente_nombre']?.toString(),
      items: items,
      devoluciones: devoluciones,
    );
  }

  /// Datos ya armados para reimprimir el comprobante de una devolución.
  Future<ComprobanteDevolucion> obtenerComprobante(int idDevolucion) async {
    final db = await DatabaseHelper().database;

    final rows = await db.rawQuery('''
      SELECT d.*, u.nombre as usuario_nombre
      FROM Devoluciones d
      LEFT JOIN Usuarios u ON u.id_usuario = d.id_usuario
      WHERE d.id_devolucion = ?
    ''', [idDevolucion]);

    if (rows.isEmpty) {
      throw Exception('La devolución no existe.');
    }
    final devolucion = rows.first;

    final items = await db.rawQuery('''
      SELECT dd.cantidad, dd.precio, p.nombre
      FROM Detalle_Devolucion dd
      INNER JOIN Producto p ON p.id_producto = dd.id_producto
      WHERE dd.id_devolucion = ?
    ''', [idDevolucion]);

    return ComprobanteDevolucion(
      idDevolucion: idDevolucion,
      idVenta: devolucion['id_venta'] as int,
      fechaHora: devolucion['fecha_hora']?.toString() ?? '',
      tipo: devolucion['tipo']?.toString() ?? 'Parcial',
      motivo: devolucion['motivo']?.toString() ?? '',
      usuario: devolucion['usuario_nombre']?.toString() ?? 'N/D',
      importe: (devolucion['importe'] as num?)?.toDouble() ?? 0,
      items: items,
    );
  }

  Future<Map<int, int>> _devueltoPorProducto(dynamic db, int idVenta) async {
    final rows = await db.rawQuery('''
      SELECT dd.id_producto, SUM(dd.cantidad) as cantidad
      FROM Detalle_Devolucion dd
      INNER JOIN Devoluciones d ON d.id_devolucion = dd.id_devolucion
      WHERE d.id_venta = ?
      GROUP BY dd.id_producto
    ''', [idVenta]);

    return {
      for (final row in rows) row['id_producto'] as int: (row['cantidad'] as num).toInt(),
    };
  }

  /// Cancela toda la venta: devuelve automáticamente todo lo que quede
  /// pendiente de cada producto (si ya hubo una devolución parcial antes,
  /// solo cubre el resto).
  Future<int> cancelarVenta({
    required int idVenta,
    required String motivo,
  }) {
    return _procesarDevolucion(
      idVenta: idVenta,
      tipo: 'Cancelacion',
      motivo: motivo,
      itemsSolicitados: null,
    );
  }

  /// Devuelve cantidades específicas de uno o más productos de la venta.
  Future<int> devolverParcial({
    required int idVenta,
    required String motivo,
    required List<Map<String, dynamic>> items,
  }) {
    if (items.isEmpty) {
      throw Exception('Selecciona al menos un producto para devolver.');
    }

    return _procesarDevolucion(
      idVenta: idVenta,
      tipo: 'Parcial',
      motivo: motivo,
      itemsSolicitados: items,
    );
  }

  /// Núcleo compartido de cancelación/devolución parcial. Todo corre en una
  /// sola transacción: si cualquier validación falla, SQLite revierte todo
  /// (nada de stock reintegrado a medias ni registros huérfanos).
  ///
  /// [itemsSolicitados] en `null` significa "cancelación total": se calcula
  /// automáticamente todo lo pendiente de cada producto dentro de la propia
  /// transacción, para no depender de una lectura previa que pudiera quedar
  /// desactualizada.
  Future<int> _procesarDevolucion({
    required int idVenta,
    required String tipo,
    required String motivo,
    required List<Map<String, dynamic>>? itemsSolicitados,
  }) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) {
      throw Exception('El motivo es obligatorio.');
    }

    final db = await DatabaseHelper().database;

    return db.transaction((txn) async {
      final ventaRows = await txn.query(
        'Ventas',
        where: 'id_venta = ?',
        whereArgs: [idVenta],
        limit: 1,
      );

      if (ventaRows.isEmpty) {
        throw Exception('La venta no existe.');
      }

      final estadoActual = ventaRows.first['estado']?.toString() ?? 'Activa';
      if (estadoActual == 'Cancelada') {
        throw Exception('Esta venta ya está cancelada; no se pueden hacer más devoluciones.');
      }

      // El reembolso siempre sale en efectivo (ver `_procesarDevolucion` más
      // abajo), así que necesita quedar ligado a la caja actualmente abierta
      // de quien procesa la devolución (no la de la venta original): de lo
      // contrario ese efectivo saliente no se restaría de ningún cierre y
      // generaría un faltante silencioso.
      final idUsuarioActual = SessionManager.currentUserId ?? 1;
      final cajaAbierta = await txn.query(
        'Cajas',
        where: 'id_usuario = ? AND estado = ?',
        whereArgs: [idUsuarioActual, 'Abierta'],
        limit: 1,
      );
      if (cajaAbierta.isEmpty) {
        throw Exception('Debes abrir la caja antes de procesar devoluciones.');
      }
      final idCaja = cajaAbierta.first['id_caja'] as int;

      final vendidos = await txn.rawQuery('''
        SELECT dv.id_producto, p.nombre, dv.precio, dv.precio_neto, SUM(dv.cantidad) as cantidad_vendida
        FROM Detalle_Venta dv
        INNER JOIN Producto p ON p.id_producto = dv.id_producto
        WHERE dv.id_venta = ?
        GROUP BY dv.id_producto, dv.precio, dv.precio_neto
      ''', [idVenta]);

      if (vendidos.isEmpty) {
        throw Exception('La venta no tiene productos registrados.');
      }

      final vendidoPorProducto = <int, Map<String, dynamic>>{
        for (final row in vendidos) row['id_producto'] as int: row,
      };

      final devueltoPrevio = await _devueltoPorProducto(txn, idVenta);

      int pendiente(int idProducto) {
        final vendida = (vendidoPorProducto[idProducto]?['cantidad_vendida'] as num?)?.toInt() ?? 0;
        final devuelta = devueltoPrevio[idProducto] ?? 0;
        return vendida - devuelta;
      }

      final List<Map<String, dynamic>> itemsAProcesar;

      if (itemsSolicitados == null) {
        itemsAProcesar = vendidoPorProducto.keys
            .map((idProducto) => {'id_producto': idProducto, 'cantidad': pendiente(idProducto)})
            .where((item) => (item['cantidad'] as int) > 0)
            .toList();

        if (itemsAProcesar.isEmpty) {
          throw Exception('Esta venta ya no tiene productos pendientes por devolver.');
        }
      } else {
        final combinados = <int, int>{};
        for (final item in itemsSolicitados) {
          final idProducto = item['id_producto'] as int;
          final cantidad = item['cantidad'] as int;
          combinados[idProducto] = (combinados[idProducto] ?? 0) + cantidad;
        }

        if (combinados.isEmpty) {
          throw Exception('Selecciona al menos un producto para devolver.');
        }

        for (final entry in combinados.entries) {
          final idProducto = entry.key;
          final cantidad = entry.value;

          if (!vendidoPorProducto.containsKey(idProducto)) {
            throw Exception('El producto no pertenece a esta venta.');
          }
          if (cantidad <= 0) {
            throw Exception('La cantidad a devolver debe ser mayor a cero.');
          }

          final disponible = pendiente(idProducto);
          if (cantidad > disponible) {
            final nombre = vendidoPorProducto[idProducto]?['nombre'];
            throw Exception(
              'No puedes devolver $cantidad de "$nombre": solo quedan $disponible pendiente(s) por devolver.',
            );
          }
        }

        itemsAProcesar = combinados.entries
            .map((e) => {'id_producto': e.key, 'cantidad': e.value})
            .toList();
      }

      // El importe devuelto se calcula sobre precio_neto (lo realmente
      // pagado por unidad, ya con descuentos aplicados), no sobre el
      // precio original de lista.
      double precioPagadoDe(int idProducto) {
        final fila = vendidoPorProducto[idProducto]!;
        final neto = fila['precio_neto'] as num?;
        return (neto ?? fila['precio'] as num).toDouble();
      }

      double importeTotal = 0;
      for (final item in itemsAProcesar) {
        final idProducto = item['id_producto'] as int;
        final cantidad = item['cantidad'] as int;
        importeTotal = redondearMoneda(importeTotal + precioPagadoDe(idProducto) * cantidad);
      }

      final idDevolucion = await txn.insert('Devoluciones', {
        'id_venta': idVenta,
        'id_usuario': SessionManager.currentUserId,
        'id_caja': idCaja,
        'fecha_hora': DateTime.now().toIso8601String(),
        'tipo': tipo,
        'motivo': motivoLimpio,
        'importe': importeTotal,
      });

      // El reembolso sale del efectivo de la caja actual (ver el comentario
      // más abajo sobre por qué siempre es en efectivo) -- se registra en
      // negativo, mismo criterio que AbonoCuentaPagar del backend para
      // salidas de dinero (ver EsqPos.Domain.Enums.TipoMovimientoCaja).
      await _movimientoCajaLogger.registrar(
        txn,
        idCaja: idCaja,
        tipoMovimiento: 'DevolucionEfectivo',
        monto: -importeTotal,
        concepto: 'Devolución de venta #$idVenta',
        idVentaReferencia: idVenta,
      );

      for (final item in itemsAProcesar) {
        final idProducto = item['id_producto'] as int;
        final cantidad = item['cantidad'] as int;
        final precio = precioPagadoDe(idProducto);

        await txn.insert('Detalle_Devolucion', {
          'id_devolucion': idDevolucion,
          'id_producto': idProducto,
          'cantidad': cantidad,
          'precio': precio,
        });

        // Reutiliza el helper de reintegro de stock ya usado al cancelar
        // pedidos entregados: el mecanismo (sumar cantidad a Inventario
        // dentro de la misma transacción) es idéntico.
        await _productoController.restaurarStockPedido(
          idProducto,
          cantidad,
          executor: txn,
          tipoMovimiento: 'DevolucionVenta',
          referenciaTipo: 'Venta',
          referenciaId: idVenta,
          motivo: 'Devolución de venta #$idVenta',
        );
      }

      final pendienteTotalRestante = vendidoPorProducto.keys.fold<int>(0, (acc, idProducto) {
        final vendida = (vendidoPorProducto[idProducto]!['cantidad_vendida'] as num).toInt();
        final devueltaPrevia = devueltoPrevio[idProducto] ?? 0;
        final devueltaAhora = itemsAProcesar
            .where((i) => i['id_producto'] == idProducto)
            .fold<int>(0, (s, i) => s + (i['cantidad'] as int));
        return acc + (vendida - devueltaPrevia - devueltaAhora);
      });

      final nuevoEstado = pendienteTotalRestante == 0 ? 'Cancelada' : 'Parcialmente devuelta';

      await txn.update(
        'Ventas',
        {'estado': nuevoEstado},
        where: 'id_venta = ?',
        whereArgs: [idVenta],
      );

      // El reembolso siempre se entrega en efectivo, sin importar con qué
      // método(s) se pagó la venta original: así lo decidió el negocio para
      // no depender de terminales de tarjeta al momento de la devolución.
      // El corte de caja lo resta directamente del bucket de efectivo.
      final descripcion = tipo == 'Cancelacion'
          ? 'Venta #$idVenta cancelada. Motivo: $motivoLimpio. Importe devuelto: \$${importeTotal.toStringAsFixed(2)} (reembolsado en efectivo).'
          : 'Devolución parcial en venta #$idVenta (${itemsAProcesar.length} producto(s)). '
              'Motivo: $motivoLimpio. Importe devuelto: \$${importeTotal.toStringAsFixed(2)} (reembolsado en efectivo).';

      await txn.insert('Auditorias', {
        'fecha_hora': DateTime.now().toIso8601String(),
        'usuario': '${SessionManager.currentUserRole}: ${SessionManager.currentUserName}',
        'tabla': 'Ventas',
        'accion': tipo == 'Cancelacion' ? 'CANCEL' : 'DEVOLUCION',
        'id_registro': idVenta,
        'descripcion': descripcion,
        'id_usuario': idUsuarioActual,
        'id_caja': idCaja,
      });

      return idDevolucion;
    });
  }
}
