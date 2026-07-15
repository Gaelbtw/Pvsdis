import '../core/config/app_config.dart';
import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../core/utils/descuento_utils.dart';
import '../models/ventas_model.dart';
import 'auditoria_controller.dart';

class VentasController {
  final dbHelper = DatabaseHelper();
  final _auditoriaController = AuditoriaController();

  Future<int> insertar(Ventas venta) async {
    final db = await dbHelper.database;
    return await db.insert('Ventas', venta.toMap());
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
    required String metodoPago,
    int? idCliente,
    TipoDescuento? descuentoGlobalTipo,
    double descuentoGlobalValor = 0,
    String? descuentoMotivo,
    int? descuentoAutorizadoPor,
  }) async {
    final config = AppConfig.actual;

    final calculo = calcularVenta(
      carrito: carrito,
      descuentoGlobalTipo: descuentoGlobalTipo,
      descuentoGlobalValor: descuentoGlobalValor,
      descuentoMaximoPorcentaje: config.descuentoMaximoPorcentaje,
    );

    final esCajero = SessionManager.currentUserRole == 'Cajero';

    // Red de seguridad a nivel de negocio: aunque la UI ya debería impedir
    // llegar hasta aquí en estos casos, la lógica financiera/autorización
    // no puede depender solo de que la UI se haya comportado bien.
    if (calculo.descuentoTotal > 0 && esCajero && !config.descuentoCajeroPuedeAplicar) {
      throw Exception('No tienes permiso para aplicar descuentos.');
    }

    if (calculo.requiereAutorizacion) {
      final motivoLimpio = descuentoMotivo?.trim() ?? '';
      if (motivoLimpio.isEmpty) {
        throw Exception('El motivo es obligatorio para este descuento.');
      }
      if (esCajero && config.descuentoCajeroRequiereAutorizacion && descuentoAutorizadoPor == null) {
        throw Exception('Este descuento requiere autorización de un administrador.');
      }
    }

    final db = await dbHelper.database;

    return db.transaction((txn) async {
      final idVenta = await txn.insert('Ventas', {
        "id_cliente": idCliente,
        "id_usuario": SessionManager.currentUserId ?? 1,
        "fecha": DateTime.now().toIso8601String(),
        "total": calculo.total,
        "subtotal": calculo.subtotal,
        "descuento_total": calculo.descuentoTotal,
        "descuento_global_tipo": calculo.descuentoGlobalTipo?.nombre,
        "descuento_global_valor": calculo.descuentoGlobalValor,
        "descuento_motivo": descuentoMotivo?.trim(),
        "descuento_autorizado_por": descuentoAutorizadoPor,
        "metodo_pago": metodoPago,
      });

      for (final linea in calculo.lineas) {
        final stock = await txn.rawQuery(
          'SELECT cantidad FROM Inventario WHERE id_producto = ?',
          [linea.idProducto],
        );

        if (stock.isEmpty) {
          throw Exception("Producto sin inventario");
        }

        final disponible = stock.first['cantidad'] as int;

        if (disponible < linea.cantidad) {
          throw Exception(
            "Stock insuficiente para \"${linea.nombre}\" (disponible: $disponible, solicitado: ${linea.cantidad})",
          );
        }

        await txn.insert('Detalle_Venta', {
          "id_venta": idVenta,
          "id_producto": linea.idProducto,
          "cantidad": linea.cantidad,
          "precio": linea.precioOriginal,
          "descuento_tipo": linea.descuentoTipo?.nombre,
          "descuento_valor": linea.descuentoValor,
          "descuento_monto": linea.descuentoMonto,
          "precio_neto": linea.precioNetoUnitario,
        });

        await txn.rawUpdate('''
          UPDATE Inventario
          SET cantidad = cantidad - ?
          WHERE id_producto = ?
        ''', [
          linea.cantidad,
          linea.idProducto,
        ]);
      }

      await txn.insert('Auditorias', {
        "fecha_hora": DateTime.now().toIso8601String(),
        "usuario": SessionManager.currentUserName,
        "tabla": "Ventas",
        "accion": "CREATE",
        "id_registro": idVenta,
        "descripcion": "Nueva venta por \$${calculo.total.toStringAsFixed(2)}",
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
