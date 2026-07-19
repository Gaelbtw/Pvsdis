import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../core/utils/money.dart';
import '../core/utils/pagos_mixtos.dart';

/// El `SELECT` base de una cuenta por pagar: el saldo, el estado y si está
/// vencida NUNCA se guardan — siempre se recalculan aquí a partir de
/// `Compras.total` y la suma de `Abonos`. Se envuelve en un subquery externo
/// para poder filtrar por las columnas calculadas (`estado`/`vencida`), que
/// SQLite no deja usar directamente en el `WHERE` del mismo `SELECT` que las
/// define.
const _selectCuentas = '''
  SELECT * FROM (
    SELECT
      c.id_compra,
      c.fecha,
      c.total,
      c.forma_pago,
      c.fecha_vencimiento,
      c.folio_factura,
      c.id_proveedor,
      p.nombre as proveedor,
      IFNULL(a.pagado, 0) as pagado,
      (c.total - IFNULL(a.pagado, 0)) as saldo,
      CASE
        WHEN (c.total - IFNULL(a.pagado, 0)) <= 0 THEN 'Pagada'
        WHEN IFNULL(a.pagado, 0) > 0 THEN 'Parcial'
        ELSE 'Pendiente'
      END as estado,
      CASE
        WHEN (c.total - IFNULL(a.pagado, 0)) > 0
         AND c.fecha_vencimiento IS NOT NULL
         AND c.fecha_vencimiento < date('now')
        THEN 1 ELSE 0
      END as vencida
    FROM Compras c
    LEFT JOIN Proveedores p ON p.id_proveedor = c.id_proveedor
    LEFT JOIN (
      SELECT id_compra, SUM(monto) as pagado FROM Abonos GROUP BY id_compra
    ) a ON a.id_compra = c.id_compra
  ) t
''';

/// Cuentas por pagar a proveedores: registrar abonos (parciales o de
/// liquidación) contra una compra y consultar deuda/vencimientos. El saldo
/// de cada compra se calcula siempre en vivo (`total` - suma de `Abonos`),
/// nunca se guarda como un número editable aparte. Los abonos son
/// historial inmutable: no existe `actualizar`/`eliminar` para ellos.
class CuentasPorPagarController {
  final dbHelper = DatabaseHelper();

  /// Registra un pago a cuenta de [idCompra]. Si se pasa [txn] (por ejemplo,
  /// desde `ComprasController.insertarCompraCompleta` al capturar el pago
  /// inicial de la compra), se reutiliza esa transacción en vez de abrir una
  /// propia, para que compra + primer abono sean atómicos.
  Future<int> registrarAbono({
    required int idCompra,
    required double monto,
    required List<Map<String, dynamic>> pagos,
    String? referencia,
    String? observaciones,
    DatabaseExecutor? txn,
  }) async {
    if (monto <= 0) {
      throw Exception('El monto del abono debe ser mayor a cero.');
    }

    final sumaPagos = pagos.fold<double>(0, (s, p) => s + (p['monto'] as num).toDouble());
    if (redondearMoneda(sumaPagos) != redondearMoneda(monto)) {
      throw Exception('La suma de los métodos de pago no coincide con el monto del abono.');
    }

    for (final pago in pagos) {
      final metodo = pago['metodo_pago']?.toString() ?? '';
      final esConocido = metodosPagoDisponibles.any(
        (m) => m.toLowerCase() == metodo.trim().toLowerCase(),
      );
      if (!esConocido) {
        throw Exception('Método de pago no reconocido: "$metodo".');
      }
    }

    Future<int> operar(DatabaseExecutor executor) async {
      final compraRows = await executor.query(
        'Compras',
        columns: ['total'],
        where: 'id_compra = ?',
        whereArgs: [idCompra],
        limit: 1,
      );
      if (compraRows.isEmpty) {
        throw Exception('La compra no existe.');
      }
      final total = (compraRows.first['total'] as num).toDouble();

      final pagadoRows = await executor.rawQuery(
        'SELECT IFNULL(SUM(monto), 0) as pagado FROM Abonos WHERE id_compra = ?',
        [idCompra],
      );
      final pagado = (pagadoRows.first['pagado'] as num).toDouble();
      final saldoPendiente = redondearMoneda(total - pagado);

      if (saldoPendiente <= 0) {
        throw Exception('Esta compra ya está pagada por completo.');
      }
      if (redondearMoneda(monto) > saldoPendiente) {
        throw Exception(
          'El abono (\$${monto.toStringAsFixed(2)}) no puede ser mayor al saldo pendiente '
          '(\$${saldoPendiente.toStringAsFixed(2)}).',
        );
      }

      final tieneEfectivo = pagos.any(
        (p) => p['metodo_pago'].toString().toLowerCase() == 'efectivo',
      );

      int? idCaja;
      if (tieneEfectivo) {
        // Se consulta a través del mismo `executor` (nunca abriendo un
        // segundo handle vía CajaController) porque, cuando esto corre
        // dentro de una transacción en curso (p. ej. la de
        // ComprasController.insertarCompraCompleta), una consulta por
        // fuera de esa transacción se queda esperando a que termine — y la
        // transacción está esperando esta consulta: interbloqueo.
        final idUsuario = SessionManager.currentUserId ?? 1;
        final cajaRows = await executor.query(
          'Cajas',
          where: 'id_usuario = ? AND estado = ?',
          whereArgs: [idUsuario, 'Abierta'],
          limit: 1,
        );
        if (cajaRows.isEmpty) {
          throw Exception('Debes abrir la caja antes de registrar pagos en efectivo a proveedores.');
        }
        idCaja = cajaRows.first['id_caja'] as int;
      }

      final idAbono = await executor.insert('Abonos', {
        'id_compra': idCompra,
        'id_caja': idCaja,
        'id_usuario': SessionManager.currentUserId,
        'fecha': DateTime.now().toIso8601String(),
        'monto': redondearMoneda(monto),
        'referencia': referencia?.trim().isEmpty == true ? null : referencia?.trim(),
        'observaciones': observaciones?.trim().isEmpty == true ? null : observaciones?.trim(),
      });

      for (final pago in pagos) {
        await executor.insert('Abono_Pagos', {
          'id_abono': idAbono,
          'metodo_pago': pago['metodo_pago'],
          'monto': redondearMoneda((pago['monto'] as num).toDouble()),
        });
      }

      final rol = SessionManager.currentUserRole == 'Administrador'
          ? 'Admin'
          : SessionManager.currentUserRole;
      await executor.insert('Auditorias', {
        'fecha_hora': DateTime.now().toIso8601String(),
        'usuario': '$rol: ${SessionManager.currentUserName}',
        'tabla': 'Compras',
        'accion': 'ABONO_PROVEEDOR',
        'id_registro': idCompra,
        'descripcion': 'Abono de \$${monto.toStringAsFixed(2)} a la compra #$idCompra'
            '${saldoPendiente - monto <= 0 ? ' (liquidada)' : ''}.',
        'id_usuario': SessionManager.currentUserId,
        'id_caja': idCaja,
      });

      return idAbono;
    }

    if (txn != null) {
      return operar(txn);
    }

    final db = await dbHelper.database;
    return db.transaction((t) => operar(t));
  }

  /// Registra un abono exacto por el saldo pendiente restante de [idCompra].
  Future<int> liquidarCompra({
    required int idCompra,
    required List<Map<String, dynamic>> pagos,
    String? referencia,
    String? observaciones,
  }) async {
    final saldo = await saldoPendiente(idCompra);
    return registrarAbono(
      idCompra: idCompra,
      monto: saldo,
      pagos: pagos,
      referencia: referencia,
      observaciones: observaciones,
    );
  }

  Future<double> saldoPendiente(int idCompra) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        c.total - IFNULL((SELECT SUM(monto) FROM Abonos WHERE id_compra = c.id_compra), 0) as saldo
      FROM Compras c
      WHERE c.id_compra = ?
    ''', [idCompra]);

    if (rows.isEmpty) {
      throw Exception('La compra no existe.');
    }
    return redondearMoneda((rows.first['saldo'] as num).toDouble());
  }

  /// Lista de cuentas (una fila por compra) con su saldo/estado calculados
  /// en vivo, filtrable por proveedor/estado/rango de fechas/solo vencidas.
  Future<List<Map<String, dynamic>>> obtenerCuentas({
    int? idProveedor,
    String? estado,
    DateTime? desde,
    DateTime? hasta,
    bool soloVencidas = false,
  }) async {
    final db = await dbHelper.database;

    final condiciones = <String>[];
    final argumentos = <Object?>[];

    if (idProveedor != null) {
      condiciones.add('id_proveedor = ?');
      argumentos.add(idProveedor);
    }
    if (estado != null && estado.isNotEmpty) {
      condiciones.add('estado = ?');
      argumentos.add(estado);
    }
    if (soloVencidas) {
      condiciones.add('vencida = 1');
    }
    if (desde != null) {
      condiciones.add('fecha >= ?');
      argumentos.add(desde.toIso8601String());
    }
    if (hasta != null) {
      condiciones.add('fecha <= ?');
      argumentos.add(hasta.toIso8601String());
    }

    final where = condiciones.isEmpty ? '' : 'WHERE ${condiciones.join(' AND ')}';

    return db.rawQuery('$_selectCuentas $where ORDER BY fecha DESC', argumentos);
  }

  /// Todas las cuentas con saldo pendiente (`Pendiente`/`Parcial`), sin
  /// importar si ya vencieron o no.
  Future<List<Map<String, dynamic>>> obtenerCuentasPendientes() async {
    final db = await dbHelper.database;
    return db.rawQuery("$_selectCuentas WHERE estado != 'Pagada' ORDER BY fecha DESC");
  }

  Future<List<Map<String, dynamic>>> obtenerCuentasVencidas() async {
    final db = await dbHelper.database;
    return db.rawQuery('$_selectCuentas WHERE vencida = 1 ORDER BY fecha_vencimiento ASC');
  }

  /// Cuentas `Pendiente`/`Parcial` cuyo vencimiento cae dentro de los
  /// próximos [dias] (sin incluir las que ya vencieron).
  Future<List<Map<String, dynamic>>> obtenerProximosVencimientos({int dias = 7}) async {
    final db = await dbHelper.database;
    final limite = DateTime.now().add(Duration(days: dias)).toIso8601String();

    return db.rawQuery('''
      $_selectCuentas
      WHERE estado != 'Pagada'
        AND fecha_vencimiento IS NOT NULL
        AND fecha_vencimiento >= date('now')
        AND fecha_vencimiento <= ?
      ORDER BY fecha_vencimiento ASC
    ''', [limite]);
  }

  Future<List<Map<String, dynamic>>> obtenerHistorialPagos(int idCompra) async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT
        ab.id_abono, ab.fecha, ab.monto, ab.referencia, ab.observaciones,
        ab.id_caja, ab.id_usuario, u.nombre as usuario,
        GROUP_CONCAT(
          CASE WHEN ap.metodo_pago = '$metodoPagoHistorico' THEN '$labelMetodoPagoHistorico' ELSE ap.metodo_pago END
          || ': \$' || ap.monto,
          ', '
        ) as metodos
      FROM Abonos ab
      LEFT JOIN Usuarios u ON u.id_usuario = ab.id_usuario
      LEFT JOIN Abono_Pagos ap ON ap.id_abono = ab.id_abono
      WHERE ab.id_compra = ?
      GROUP BY ab.id_abono
      ORDER BY ab.fecha DESC
    ''', [idCompra]);
  }

  /// Resumen para la ficha del proveedor: total comprado, total pagado,
  /// saldo pendiente y cuántas de sus compras están vencidas.
  Future<Map<String, dynamic>> resumenProveedor(int idProveedor) async {
    final db = await dbHelper.database;

    final totales = await db.rawQuery('''
      SELECT
        IFNULL(SUM(c.total), 0) as total_comprado,
        IFNULL(SUM(IFNULL(a.pagado, 0)), 0) as total_pagado
      FROM Compras c
      LEFT JOIN (
        SELECT id_compra, SUM(monto) as pagado FROM Abonos GROUP BY id_compra
      ) a ON a.id_compra = c.id_compra
      WHERE c.id_proveedor = ?
    ''', [idProveedor]);

    final vencidas = await db.rawQuery(
      "$_selectCuentas WHERE id_proveedor = ? AND vencida = 1",
      [idProveedor],
    );

    final totalComprado = (totales.first['total_comprado'] as num).toDouble();
    final totalPagado = (totales.first['total_pagado'] as num).toDouble();

    return {
      'total_comprado': totalComprado,
      'total_pagado': totalPagado,
      'saldo_pendiente': redondearMoneda(totalComprado - totalPagado),
      'compras_vencidas': vencidas.length,
    };
  }

  /// Suma del saldo pendiente de todas las compras no pagadas.
  Future<double> deudaTotal() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery("$_selectCuentas WHERE estado != 'Pagada'");
    final total = rows.fold<double>(0, (s, r) => s + (r['saldo'] as num).toDouble());
    return redondearMoneda(total);
  }

  /// Deuda agrupada por proveedor (solo los que tienen saldo pendiente).
  Future<List<Map<String, dynamic>>> deudaPorProveedor() async {
    final db = await dbHelper.database;
    return db.rawQuery('''
      SELECT id_proveedor, proveedor, SUM(saldo) as saldo, COUNT(*) as compras
      FROM ($_selectCuentas) c
      WHERE estado != 'Pagada'
      GROUP BY id_proveedor
      ORDER BY saldo DESC
    ''');
  }
}
