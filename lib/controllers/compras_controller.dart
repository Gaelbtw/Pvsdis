import '../core/database/database_helper.dart';
import '../core/database/db_exceptions.dart';
import '../core/session/session_manager.dart';
import '../core/sync/bitacoras/movimiento_inventario_logger.dart';
import 'cuentas_por_pagar_controller.dart';

class ComprasController {
  final _cuentasPorPagarController = CuentasPorPagarController();
  final _movimientoInventarioLogger = MovimientoInventarioLogger();

  // INSERTAR COMPRA COMPLETA
  //
  // "De contado" no es un caso especial: es simplemente [montoInicialPagado]
  // == [total]. Si es menor (parcial) o 0 (crédito puro), el resto queda
  // como saldo pendiente, consultable en CuentasPorPagarController. El pago
  // inicial se registra como un Abono más, en la MISMA transacción que crea
  // la compra: si ese pago falla (p. ej. efectivo sin caja abierta), la
  // compra tampoco se guarda.
  Future<int> insertarCompraCompleta(
    List<Map<String, dynamic>> carrito,
    double total,
    int idProveedor, {
    String formaPago = 'Contado',
    DateTime? fechaVencimiento,
    String? folioFactura,
    double montoInicialPagado = 0,
    List<Map<String, dynamic>>? pagosIniciales,
  }) async {
    final db = await DatabaseHelper().database;

    return db.transaction((txn) async {
      // 1. INSERTAR COMPRA (CABECERA)
      final idCompra = await txn.insert('Compras', {
        "fecha": DateTime.now().toIso8601String(),
        "total": total,
        "id_proveedor": idProveedor,
        "id_usuario": SessionManager.requiredUserId,
        "forma_pago": formaPago,
        "fecha_vencimiento": fechaVencimiento?.toIso8601String(),
        "folio_factura": (folioFactura == null || folioFactura.trim().isEmpty) ? null : folioFactura.trim(),
      });

      final rol = SessionManager.currentUserRoleCanonico;
      await txn.insert('Auditorias', {
        "fecha_hora": DateTime.now().toIso8601String(),
        "usuario": '$rol: ${SessionManager.currentUserName}',
        "tabla": "Compras",
        "accion": "CREATE",
        "id_registro": idCompra,
        "descripcion": "Nueva compra por \$${total.toStringAsFixed(2)}",
        "id_usuario": SessionManager.currentUserId,
      });

      // INSERTAR DETALLE + ACTUALIZAR INVENTARIO
      for (var item in carrito) {
        // detalle compra
        await txn.insert('Detalle_Compra', {
          "id_compra": idCompra,
          "id_producto": item['id_producto'],
          "cantidad": item['cantidad'],
          "precio": item['precio_compra'] ?? 0,
        });

        // actualizar inventario (SUMA STOCK)
        final stockAntes = await txn.rawQuery(
          'SELECT cantidad FROM Inventario WHERE id_producto = ?',
          [item['id_producto']],
        );
        final cantidadAnterior = stockAntes.isEmpty ? 0 : (stockAntes.first['cantidad'] as int? ?? 0);
        final cantidadRecibida = item['cantidad'] as int;

        await txn.rawUpdate(
          '''
          UPDATE Inventario
          SET cantidad = cantidad + ?
          WHERE id_producto = ?
          ''',
          [
            item['cantidad'],
            item['id_producto'],
          ],
        );

        await _movimientoInventarioLogger.registrar(
          txn,
          idProducto: item['id_producto'] as int,
          tipoMovimiento: 'EntradaCompra',
          cantidad: cantidadRecibida,
          cantidadAnterior: cantidadAnterior,
          cantidadNueva: cantidadAnterior + cantidadRecibida,
          motivo: 'Compra #$idCompra',
          referenciaTipo: 'Compra',
        );

        // ACTUALIZAR EL COSTO DEL PRODUCTO
        //
        // Hasta aqui esto no se hacia, y era un hueco grande: `precio_compra`
        // solo se escribia al dar de alta o editar el producto a mano. Un
        // producto dado de alta a $12 hace un año seguia diciendo $12 aunque
        // llevara seis compras a $18, y el reporte de utilidad mostraba un
        // margen que no existe -- sin marcarlo como dudoso, porque la linea
        // SI tenia costo.
        //
        // Se guarda el ULTIMO costo, no un promedio ponderado. El promedio es
        // mas correcto contablemente, pero aqui gana poder responder la
        // pregunta que de verdad hace el dueño ("¿a como me costo?") con el
        // numero de su ultima factura. El historial completo no se pierde:
        // cada compra deja su precio en `Detalle_Compra`, que es el registro
        // permanente de a como se compro cada vez.
        //
        // Solo si la linea trae un costo real: una compra capturada sin precio
        // no debe borrar el costo que ya se conocia.
        final costoDeEstaCompra = (item['precio_compra'] as num?)?.toDouble() ?? 0;
        if (costoDeEstaCompra > 0) {
          await txn.update(
            'Producto',
            {'precio_compra': costoDeEstaCompra},
            where: 'id_producto = ?',
            whereArgs: [item['id_producto']],
          );
        }
      }

      // 2. PAGO INICIAL (si lo hay), atómico con la compra recién creada.
      if (montoInicialPagado > 0) {
        await _cuentasPorPagarController.registrarAbono(
          idCompra: idCompra,
          monto: montoInicialPagado,
          pagos: pagosIniciales!,
          txn: txn,
        );
      }

      return idCompra;
    });
  }

  // OBTENER TODAS LAS COMPRAS
  Future<List<Map<String, dynamic>>> obtenerCompras() async {
    final db = await DatabaseHelper().database;

    return await db.rawQuery('''
      SELECT c.*, p.nombre as proveedor
      FROM Compras c
      LEFT JOIN Proveedores p ON c.id_proveedor = p.id_proveedor
      ORDER BY c.fecha DESC
    ''');
  }

  // DETALLE DE UNA COMPRA
  Future<List<Map<String, dynamic>>> detalleCompra(int idCompra) async {
    final db = await DatabaseHelper().database;

    return await db.rawQuery('''
      SELECT d.*, pr.nombre
      FROM Detalle_Compra d
      INNER JOIN Producto pr ON d.id_producto = pr.id_producto
      WHERE d.id_compra = ?
    ''', [idCompra]);
  }

  // ELIMINAR COMPRA (opcional avanzado)
  Future<void> eliminarCompra(int idCompra) async {
    final db = await DatabaseHelper().database;

    await ejecutarConMensajeDeIntegridad(
      () => db.transaction((txn) async {
        // obtener detalles
        final detalles = await txn.query(
          'Detalle_Compra',
          where: 'id_compra = ?',
          whereArgs: [idCompra],
        );

        // revertir inventario
        for (var item in detalles) {
          final stockAntes = await txn.rawQuery(
            'SELECT cantidad FROM Inventario WHERE id_producto = ?',
            [item['id_producto']],
          );
          final cantidadAnterior = stockAntes.isEmpty ? 0 : (stockAntes.first['cantidad'] as int? ?? 0);
          final cantidadRevertida = (item['cantidad'] as int?) ?? 0;

          await txn.rawUpdate(
            '''
            UPDATE Inventario
            SET cantidad = cantidad - ?
            WHERE id_producto = ?
            ''',
            [
              item['cantidad'] ?? 0,
              item['id_producto'],
            ],
          );

          await _movimientoInventarioLogger.registrar(
            txn,
            idProducto: item['id_producto'] as int,
            tipoMovimiento: 'AjusteNegativo',
            cantidad: cantidadRevertida,
            cantidadAnterior: cantidadAnterior,
            cantidadNueva: cantidadAnterior - cantidadRevertida,
            motivo: 'Compra #$idCompra eliminada',
            referenciaTipo: 'Compra',
          );
        }

        // borrar detalle
        await txn.delete(
          'Detalle_Compra',
          where: 'id_compra = ?',
          whereArgs: [idCompra],
        );

        // borrar compra (RESTRICT en Abonos.id_compra rechaza esto si ya
        // tiene pagos registrados; ejecutarConMensajeDeIntegridad convierte
        // esa violación en un mensaje claro)
        await txn.delete(
          'Compras',
          where: 'id_compra = ?',
          whereArgs: [idCompra],
        );

        final rol = SessionManager.currentUserRoleCanonico;
        await txn.insert('Auditorias', {
          "fecha_hora": DateTime.now().toIso8601String(),
          "usuario": '$rol: ${SessionManager.currentUserName}',
          "tabla": "Compras",
          "accion": "DELETE",
          "id_registro": idCompra,
          "descripcion": "Compra #$idCompra eliminada",
          "id_usuario": SessionManager.currentUserId,
        });
      }),
      'No se puede eliminar: la compra tiene abonos registrados.',
    );
  }
}
