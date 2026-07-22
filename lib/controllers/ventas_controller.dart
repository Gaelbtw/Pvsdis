import '../core/config/app_config.dart';
import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../core/sync/bitacoras/movimiento_caja_logger.dart';
import '../core/sync/bitacoras/movimiento_inventario_logger.dart';
import '../core/utils/descuento_utils.dart';
import '../core/utils/money.dart';
import '../core/utils/pagos_mixtos.dart';
import '../core/utils/promociones_engine.dart';
import '../models/ventas_model.dart';
import 'auditoria_controller.dart';
import 'promociones_controller.dart';

class VentasController {
  final dbHelper = DatabaseHelper();
  final _auditoriaController = AuditoriaController();
  final _promocionesController = PromocionesController();
  final _movimientoInventarioLogger = MovimientoInventarioLogger();
  final _movimientoCajaLogger = MovimientoCajaLogger();

  Future<int> insertar(Ventas venta) async {
    final db = await dbHelper.database;
    return await DatabaseHelper.insertarConGuidSync(db, 'Ventas', venta.toMap());
  }

  /// Registra la venta completa (líneas, descuentos, stock y auditoría) en
  /// una sola transacción. El total que se cobra y se persiste NO es el que
  /// traiga [carrito] armado por la UI: se recalcula aquí mismo con
  /// [calcularVenta], para que la fuente de verdad del monto final sea
  /// siempre este controlador y no una vista que podría desincronizarse.
  ///
  /// [carrito] son mapas con `id_producto`, `nombre`, `precio`, `cantidad`
  /// y, opcionalmente, `descuento_tipo`/`descuento_valor` por línea.
  Future<int> insertarVentaCompleta({
    required List<Map<String, dynamic>> carrito,
    required List<Map<String, dynamic>> pagos,
    int? idCliente,
    TipoDescuento? descuentoGlobalTipo,
    double descuentoGlobalValor = 0,
    String? descuentoMotivo,
    int? descuentoAutorizadoPor,
  }) async {
    final config = AppConfig.actual;

    // Igual que el total: las promociones no se toman de lo que la UI ya
    // haya precalculado, se vuelven a evaluar aquí con las promociones
    // activas en este instante, para que el cobro nunca dependa de un
    // resultado que la UI pudo haber calculado con datos desincronizados.
    final promocionesActivas = await _promocionesController.obtenerActivasVigentes();
    final resultadoPromociones = evaluarPromociones(
      carrito: carrito,
      promocionesActivas: promocionesActivas,
    );

    final calculo = calcularVenta(
      carrito: carrito,
      descuentosPromocionPorLinea: resultadoPromociones.descuentoPorLinea,
      descuentoGlobalTipo: descuentoGlobalTipo,
      descuentoGlobalValor: descuentoGlobalValor,
      descuentoMaximoPorcentaje: config.descuentoMaximoPorcentaje,
    );

    final esCajero = SessionManager.currentUserRole == 'Cajero';

    validarPermisoDescuento(
      calculo: calculo,
      esCajero: esCajero,
      cajeroPuedeAplicarDescuento: config.descuentoCajeroPuedeAplicar,
      cajeroRequiereAutorizacion: config.descuentoCajeroRequiereAutorizacion,
      descuentoMotivo: descuentoMotivo,
      descuentoAutorizadoPor: descuentoAutorizadoPor,
    );

    for (final pago in pagos) {
      final metodo = pago['metodo_pago']?.toString() ?? '';
      final esConocido = metodosPagoDisponibles.any(
        (m) => m.toLowerCase() == metodo.trim().toLowerCase(),
      );
      if (!esConocido) {
        throw Exception('Método de pago no reconocido: "$metodo".');
      }
    }

    final resultadoPagos = validarPagosMixtos(
      total: calculo.total,
      pagos: pagos
          .map((p) => PagoIngresado(
                metodoPago: p['metodo_pago'] as String,
                monto: (p['monto'] as num).toDouble(),
              ))
          .toList(),
    );

    if (!resultadoPagos.esValido) {
      throw Exception(resultadoPagos.mensajeError ?? 'Los pagos no cubren el total de la venta.');
    }

    final metodoPagoGuardado = pagos.length == 1 ? pagos.first['metodo_pago'] as String : 'Mixto';

    final db = await dbHelper.database;

    return db.transaction((txn) async {
      final idUsuario = SessionManager.currentUserId ?? 1;
      final cajaAbierta = await txn.query(
        'Cajas',
        where: 'id_usuario = ? AND estado = ?',
        whereArgs: [idUsuario, 'Abierta'],
        limit: 1,
      );
      if (cajaAbierta.isEmpty) {
        throw Exception('Debes abrir la caja antes de registrar ventas.');
      }
      final idCaja = cajaAbierta.first['id_caja'] as int;

      final idVenta = await DatabaseHelper.insertarConGuidSync(txn, 'Ventas', {
        "id_cliente": idCliente,
        "id_usuario": idUsuario,
        "id_caja": idCaja,
        "fecha": DateTime.now().toIso8601String(),
        "total": calculo.total,
        "subtotal": calculo.subtotal,
        "descuento_total": calculo.descuentoTotal,
        "descuento_global_tipo": calculo.descuentoGlobalTipo?.nombre,
        "descuento_global_valor": calculo.descuentoGlobalValor,
        "descuento_motivo": descuentoMotivo?.trim(),
        "descuento_autorizado_por": descuentoAutorizadoPor,
        "metodo_pago": metodoPagoGuardado,
        "cambio": resultadoPagos.cambio,
      });

      for (final pago in pagos) {
        final metodoPago = pago['metodo_pago'] as String;
        final monto = redondearMoneda((pago['monto'] as num).toDouble());

        await DatabaseHelper.insertarConGuidSync(txn, 'Venta_Pagos', {
          "id_venta": idVenta,
          "metodo_pago": metodoPago,
          "monto": monto,
        });

        await _movimientoCajaLogger.registrar(
          txn,
          idCaja: idCaja,
          tipoMovimiento: MovimientoCajaLogger.tipoMovimientoParaMetodoPago(metodoPago),
          monto: monto,
          concepto: 'Venta #$idVenta',
          idVentaReferencia: idVenta,
        );
      }

      // Se guarda el id de cada Detalle_Venta insertado, en el mismo orden
      // que las líneas del carrito, para poder enlazar el snapshot de
      // promociones (Venta_Promociones_Detalle) más abajo.
      final idsDetalleVenta = <int>[];

      for (var i = 0; i < calculo.lineas.length; i++) {
        final linea = calculo.lineas[i];
        final stock = await txn.rawQuery(
          'SELECT cantidad, cantidad_reservada FROM Inventario WHERE id_producto = ?',
          [linea.idProducto],
        );

        if (stock.isEmpty) {
          throw Exception("Producto sin inventario");
        }

        // Las unidades ya reservadas por un Apartado no están disponibles
        // para una venta normal, aunque físicamente sigan en la tienda.
        final disponible =
            (stock.first['cantidad'] as int) - (stock.first['cantidad_reservada'] as int? ?? 0);

        if (disponible < linea.cantidad) {
          throw Exception(
            "Stock insuficiente para \"${linea.nombre}\" (disponible: $disponible, solicitado: ${linea.cantidad})",
          );
        }

        final idDetalleVenta = await DatabaseHelper.insertarConGuidSync(txn, 'Detalle_Venta', {
          "id_venta": idVenta,
          "id_producto": linea.idProducto,
          "cantidad": linea.cantidad,
          "precio": linea.precioOriginal,
          "descuento_tipo": linea.descuentoTipo?.nombre,
          "descuento_valor": linea.descuentoValor,
          "descuento_monto": linea.descuentoMonto,
          "precio_neto": linea.precioNetoUnitario,
        });
        idsDetalleVenta.add(idDetalleVenta);

        await txn.rawUpdate('''
          UPDATE Inventario
          SET cantidad = cantidad - ?
          WHERE id_producto = ?
        ''', [
          linea.cantidad,
          linea.idProducto,
        ]);

        final cantidadAnterior = stock.first['cantidad'] as int;
        await _movimientoInventarioLogger.registrar(
          txn,
          idProducto: linea.idProducto,
          tipoMovimiento: 'SalidaVenta',
          cantidad: linea.cantidad,
          cantidadAnterior: cantidadAnterior,
          cantidadNueva: cantidadAnterior - linea.cantidad,
          motivo: 'Venta #$idVenta',
          referenciaTipo: 'Venta',
          referenciaId: idVenta,
        );
      }

      // Snapshot inmutable de las promociones aplicadas: se guarda el
      // nombre/tipo tal como eran en este momento (no una referencia viva a
      // `Promociones`), para que editar o borrar la promoción después no
      // altere esta venta ya cerrada.
      for (final aplicacion in resultadoPromociones.aplicaciones) {
        final idVentaPromocion = await DatabaseHelper.insertarConGuidSync(txn, 'Venta_Promociones', {
          "id_venta": idVenta,
          "id_promocion": aplicacion.idPromocion,
          "nombre_snapshot": aplicacion.nombre,
          "tipo_snapshot": aplicacion.tipo.nombreDb,
          "ahorro_total": aplicacion.ahorroTotal,
        });

        for (final linea in aplicacion.lineas) {
          await txn.insert('Venta_Promociones_Detalle', {
            "id_venta_promocion": idVentaPromocion,
            "id_detalleV": idsDetalleVenta[linea.indexLinea],
            "cantidad_afectada": linea.cantidadAfectada,
            "ahorro": linea.ahorro,
          });
        }
      }

      final desglosePagos = pagos
          .map((p) => '${p['metodo_pago']}: \$${(p['monto'] as num).toStringAsFixed(2)}')
          .join(', ');
      final cambioTexto = resultadoPagos.cambio > 0
          ? ' Cambio entregado: \$${resultadoPagos.cambio.toStringAsFixed(2)}.'
          : '';

      await txn.insert('Auditorias', {
        "fecha_hora": DateTime.now().toIso8601String(),
        "usuario": SessionManager.currentUserName,
        "tabla": "Ventas",
        "accion": "CREATE",
        "id_registro": idVenta,
        "descripcion":
            "Nueva venta por \$${calculo.total.toStringAsFixed(2)} ($desglosePagos).$cambioTexto",
        "id_usuario": idUsuario,
        "id_caja": idCaja,
      });

      if (calculo.requiereAutorizacion) {
        final porcentajeTexto = calculo.subtotal > 0
            ? '${(calculo.descuentoTotal / calculo.subtotal * 100).toStringAsFixed(1)}%'
            : 'N/D';

        await txn.insert('Auditorias', {
          "fecha_hora": DateTime.now().toIso8601String(),
          "usuario": SessionManager.currentUserName,
          "tabla": "Ventas",
          "accion": "DESCUENTO",
          "id_registro": idVenta,
          "descripcion": "Descuento de \$${calculo.descuentoTotal.toStringAsFixed(2)} "
              "($porcentajeTexto del subtotal) en venta #$idVenta. "
              "Motivo: ${descuentoMotivo?.trim().isNotEmpty == true ? descuentoMotivo!.trim() : 'N/D'}."
              "${descuentoAutorizadoPor != null ? ' Autorizado por usuario #$descuentoAutorizadoPor.' : ''}",
          "id_usuario": idUsuario,
          "id_caja": idCaja,
        });
      }

      if (resultadoPromociones.ahorroTotal > 0) {
        final nombres = resultadoPromociones.aplicaciones.map((a) => a.nombre).join(', ');

        await txn.insert('Auditorias', {
          "fecha_hora": DateTime.now().toIso8601String(),
          "usuario": SessionManager.currentUserName,
          "tabla": "Ventas",
          "accion": "PROMOCION",
          "id_registro": idVenta,
          "descripcion": "Promociones aplicadas en venta #$idVenta "
              "($nombres): ahorro de \$${resultadoPromociones.ahorroTotal.toStringAsFixed(2)}.",
          "id_usuario": idUsuario,
          "id_caja": idCaja,
        });
      }

      return idVenta;
    });
  }

  Future<List<Ventas>> obtenerTodos() async {
    final db = await dbHelper.database;

    final result = await db.query(
      'Ventas',
      orderBy: 'fecha DESC',
    );

    return result.map((e) => Ventas.fromMap(e)).toList();
  }

  Future<int> actualizar(Ventas venta) async {
    if (venta.idVenta == null) {
      throw Exception("La venta no tiene ID");
    }

    final db = await dbHelper.database;

    return await db.update(
      'Ventas',
      venta.toMap(),
      where: 'id_venta = ?',
      whereArgs: [venta.idVenta],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await dbHelper.database;

    final rows = await db.delete(
      'Ventas',
      where: 'id_venta = ?',
      whereArgs: [id],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Ventas',
        accion: 'DELETE',
        idRegistro: id,
        descripcion: 'Venta eliminada',
      );
    }

    return rows;
  }
}
