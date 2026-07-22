import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../core/sync/auth_service.dart';
import '../core/sync/bitacoras/corte_caja_logger.dart';
import '../core/sync/outbox/sync_outbox_writer.dart';
import '../core/utils/money.dart';
import '../models/caja_model.dart';

/// Desglose de una caja calculado en vivo a partir de `Venta_Pagos`,
/// `Ventas` y `Devoluciones` filtrando por `id_caja`. Se usa tanto para la
/// vista previa antes de cerrar como, internamente, para congelar los
/// valores en [CajaController.cerrarCaja] — así el número que ve el cajero
/// antes de confirmar es exactamente el que queda guardado.
class ResumenCaja {
  final double fondoInicial;
  final double ventasEfectivo;
  final double ventasTarjeta;
  final double ventasTransferencia;
  final double cambioEntregado;
  final double devoluciones;
  final double efectivoEsperado;

  /// Dinero recibido en esta caja por anticipos/abonos de Apartados — se
  /// reporta aparte de `ventasXxx` (que son ventas cerradas) porque
  /// conceptualmente todavía no es una venta, aunque es efectivo/tarjeta/
  /// transferencia real que sí entró a este turno y sí debe cuadrar en el
  /// corte de caja.
  final double anticiposEfectivo;
  final double anticiposTarjeta;
  final double anticiposTransferencia;
  final double cambioAnticipos;

  /// Pagos a proveedores (Abonos) cobrados en efectivo desde esta caja —
  /// única salida de efectivo que existe hoy, aparte de cambio/devoluciones.
  /// Los abonos por tarjeta/transferencia se registran igual en
  /// `Abono_Pagos` pero no entran aquí ni restan de `efectivoEsperado`.
  final double pagosProveedoresEfectivo;

  const ResumenCaja({
    required this.fondoInicial,
    required this.ventasEfectivo,
    required this.ventasTarjeta,
    required this.ventasTransferencia,
    required this.cambioEntregado,
    required this.devoluciones,
    required this.efectivoEsperado,
    this.anticiposEfectivo = 0,
    this.anticiposTarjeta = 0,
    this.anticiposTransferencia = 0,
    this.cambioAnticipos = 0,
    this.pagosProveedoresEfectivo = 0,
  });

  double get totalVentas => ventasEfectivo + ventasTarjeta + ventasTransferencia;
  double get totalAnticipos => anticiposEfectivo + anticiposTarjeta + anticiposTransferencia;
}

/// Apertura, cierre e historial de sesiones de caja. Cada cajero trabaja
/// dentro de una caja abierta; vender y devolver exigen que exista una para
/// el usuario actual (ver `VentasController`/`DevolucionesController`).
class CajaController {
  final dbHelper = DatabaseHelper();
  final _corteCajaLogger = CorteCajaLogger();
  final _outboxWriter = SyncOutboxWriter(authService: AuthService.instancia);

  /// Abre una caja nueva para el usuario actual. Falla si ya tiene una
  /// `Abierta` (un usuario no puede tener dos cajas abiertas a la vez); la
  /// validación y el insert corren en la misma transacción para que no haya
  /// ventana entre "leer que no hay ninguna abierta" e "insertar".
  Future<int> abrirCaja({
    required double fondoInicial,
    String? observaciones,
  }) async {
    if (fondoInicial < 0) {
      throw Exception('El fondo inicial no puede ser negativo.');
    }

    final db = await dbHelper.database;
    final idUsuario = SessionManager.currentUserId ?? 1;

    return db.transaction((txn) async {
      final abiertas = await txn.query(
        'Cajas',
        where: 'id_usuario = ? AND estado = ?',
        whereArgs: [idUsuario, 'Abierta'],
        limit: 1,
      );
      if (abiertas.isNotEmpty) {
        throw Exception('Ya tienes una caja abierta. Ciérrala antes de abrir otra.');
      }

      final observacionesLimpias = observaciones?.trim();

      final idCaja = await _outboxWriter.crear(txn, entidad: 'CajaSesion', tabla: 'Cajas', values: {
        'id_usuario': idUsuario,
        'fecha_apertura': DateTime.now().toIso8601String(),
        'fondo_inicial': fondoInicial,
        'observaciones_apertura':
            (observacionesLimpias == null || observacionesLimpias.isEmpty) ? null : observacionesLimpias,
        'estado': 'Abierta',
      });

      await txn.insert('Auditorias', {
        'fecha_hora': DateTime.now().toIso8601String(),
        'usuario': SessionManager.currentUserName,
        'tabla': 'Cajas',
        'accion': 'APERTURA_CAJA',
        'id_registro': idCaja,
        'descripcion': 'Apertura de caja con fondo inicial de \$${fondoInicial.toStringAsFixed(2)}.',
        'id_usuario': idUsuario,
        'id_caja': idCaja,
      });

      return idCaja;
    });
  }

  /// La caja `Abierta` de [idUsuario], o `null` si no tiene ninguna.
  Future<Caja?> obtenerCajaAbierta(int idUsuario) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'Cajas',
      where: 'id_usuario = ? AND estado = ?',
      whereArgs: [idUsuario, 'Abierta'],
      limit: 1,
    );
    return rows.isEmpty ? null : Caja.fromMap(rows.first);
  }

  Future<Caja> _obtenerCajaOrThrow(DatabaseExecutor executor, int idCaja) async {
    final rows = await executor.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja], limit: 1);
    if (rows.isEmpty) {
      throw Exception('La caja no existe.');
    }
    return Caja.fromMap(rows.first);
  }

  /// Sin "salidas": simplificación deliberada del cierre por caja (a
  /// diferencia del antiguo corte de caja por día, que sí las restaba).
  Future<ResumenCaja> _computarResumen(DatabaseExecutor executor, Caja caja) async {
    final idCaja = caja.idCaja!;

    final porMetodoRows = await executor.rawQuery('''
      SELECT Venta_Pagos.metodo_pago as metodo, IFNULL(SUM(Venta_Pagos.monto), 0) as total
      FROM Venta_Pagos
      INNER JOIN Ventas ON Ventas.id_venta = Venta_Pagos.id_venta
      WHERE Ventas.id_caja = ?
      GROUP BY Venta_Pagos.metodo_pago
    ''', [idCaja]);

    double montoDe(String metodo) {
      for (final row in porMetodoRows) {
        if (row['metodo'].toString().toLowerCase() == metodo.toLowerCase()) {
          return (row['total'] as num).toDouble();
        }
      }
      return 0;
    }

    // Anticipos/abonos de Apartados cobrados en esta caja. Aparte de
    // Venta_Pagos a propósito: al liquidar un apartado, la Venta resultante
    // NO copia estas filas a Venta_Pagos (ver `ApartadosController._liquidar`)
    // precisamente para que este dinero se cuente UNA sola vez, en el turno
    // real en que se cobró, y no otra vez en el turno donde se liquidó.
    final porMetodoAnticiposRows = await executor.rawQuery('''
      SELECT Apartado_Abono_Pagos.metodo_pago as metodo, IFNULL(SUM(Apartado_Abono_Pagos.monto), 0) as total
      FROM Apartado_Abono_Pagos
      INNER JOIN Apartado_Abonos ON Apartado_Abonos.id_abono = Apartado_Abono_Pagos.id_abono
      WHERE Apartado_Abonos.id_caja = ?
      GROUP BY Apartado_Abono_Pagos.metodo_pago
    ''', [idCaja]);

    double montoAnticipoDe(String metodo) {
      for (final row in porMetodoAnticiposRows) {
        if (row['metodo'].toString().toLowerCase() == metodo.toLowerCase()) {
          return (row['total'] as num).toDouble();
        }
      }
      return 0;
    }

    final cambioRes = await executor.rawQuery(
      'SELECT IFNULL(SUM(cambio), 0) as total FROM Ventas WHERE id_caja = ?',
      [idCaja],
    );
    final cambioAnticiposRes = await executor.rawQuery(
      'SELECT IFNULL(SUM(cambio), 0) as total FROM Apartado_Abonos WHERE id_caja = ?',
      [idCaja],
    );
    final devolucionesRes = await executor.rawQuery(
      'SELECT IFNULL(SUM(importe), 0) as total FROM Devoluciones WHERE id_caja = ?',
      [idCaja],
    );

    // Pagos a proveedores en efectivo (Abonos): la única salida de efectivo
    // fuera de cambio/devoluciones. Los de tarjeta/transferencia se registran
    // igual en Abono_Pagos pero se ignoran aquí a propósito.
    final pagosProveedoresRes = await executor.rawQuery('''
      SELECT IFNULL(SUM(Abono_Pagos.monto), 0) as total
      FROM Abono_Pagos
      INNER JOIN Abonos ON Abonos.id_abono = Abono_Pagos.id_abono
      WHERE Abonos.id_caja = ? AND Abono_Pagos.metodo_pago = 'Efectivo'
    ''', [idCaja]);

    final ventasEfectivo = montoDe('Efectivo');
    final anticiposEfectivo = montoAnticipoDe('Efectivo');
    final cambioEntregado = (cambioRes.first['total'] as num).toDouble();
    final cambioAnticipos = (cambioAnticiposRes.first['total'] as num).toDouble();
    final devoluciones = (devolucionesRes.first['total'] as num).toDouble();
    final pagosProveedoresEfectivo = (pagosProveedoresRes.first['total'] as num).toDouble();

    final efectivoEsperado = redondearMoneda(
      caja.fondoInicial +
          ventasEfectivo +
          anticiposEfectivo -
          cambioEntregado -
          cambioAnticipos -
          devoluciones -
          pagosProveedoresEfectivo,
    );

    return ResumenCaja(
      fondoInicial: caja.fondoInicial,
      ventasEfectivo: ventasEfectivo,
      ventasTarjeta: montoDe('Tarjeta'),
      ventasTransferencia: montoDe('Transferencia'),
      cambioEntregado: cambioEntregado,
      devoluciones: devoluciones,
      efectivoEsperado: efectivoEsperado,
      anticiposEfectivo: anticiposEfectivo,
      anticiposTarjeta: montoAnticipoDe('Tarjeta'),
      anticiposTransferencia: montoAnticipoDe('Transferencia'),
      cambioAnticipos: cambioAnticipos,
      pagosProveedoresEfectivo: pagosProveedoresEfectivo,
    );
  }

  /// Resumen en vivo de [idCaja] (abierta o ya cerrada), para la vista
  /// previa antes de confirmar el cierre.
  Future<ResumenCaja> calcularResumenCaja(int idCaja) async {
    final db = await dbHelper.database;
    final caja = await _obtenerCajaOrThrow(db, idCaja);
    return _computarResumen(db, caja);
  }

  /// Congela el resumen actual de [idCaja] y la marca `Cerrada`. Falla si
  /// ya estaba cerrada (no se puede cerrar dos veces) o si no existe. No
  /// existe ningún método para editar una caja ya cerrada: "no modificar
  /// cierres históricos" se cumple por omisión de la API, no por un chequeo
  /// adicional.
  Future<int> cerrarCaja({
    required int idCaja,
    required double efectivoContado,
    String? observaciones,
  }) async {
    if (efectivoContado < 0) {
      throw Exception('El efectivo contado no puede ser negativo.');
    }

    final db = await dbHelper.database;

    return db.transaction((txn) async {
      final caja = await _obtenerCajaOrThrow(txn, idCaja);
      if (!caja.estaAbierta) {
        throw Exception('Esta caja ya fue cerrada.');
      }

      final resumen = await _computarResumen(txn, caja);
      final diferencia = redondearMoneda(efectivoContado - resumen.efectivoEsperado);
      final observacionesLimpias = observaciones?.trim();

      await txn.update(
        'Cajas',
        {
          'fecha_cierre': DateTime.now().toIso8601String(),
          'ventas_efectivo': resumen.ventasEfectivo,
          'ventas_tarjeta': resumen.ventasTarjeta,
          'ventas_transferencia': resumen.ventasTransferencia,
          'anticipos_efectivo': resumen.anticiposEfectivo,
          'anticipos_tarjeta': resumen.anticiposTarjeta,
          'anticipos_transferencia': resumen.anticiposTransferencia,
          'pagos_proveedores_efectivo': resumen.pagosProveedoresEfectivo,
          'cambio_entregado': resumen.cambioEntregado,
          'devoluciones': resumen.devoluciones,
          'efectivo_esperado': resumen.efectivoEsperado,
          'efectivo_contado': efectivoContado,
          'diferencia': diferencia,
          'observaciones_cierre':
              (observacionesLimpias == null || observacionesLimpias.isEmpty) ? null : observacionesLimpias,
          'estado': 'Cerrada',
        },
        where: 'id_caja = ?',
        whereArgs: [idCaja],
      );

      await _outboxWriter.actualizar(txn, entidad: 'CajaSesion', tabla: 'Cajas', idLocal: idCaja);

      await txn.insert('Auditorias', {
        'fecha_hora': DateTime.now().toIso8601String(),
        'usuario': SessionManager.currentUserName,
        'tabla': 'Cajas',
        'accion': 'CIERRE_CAJA',
        'id_registro': idCaja,
        'descripcion': 'Cierre de caja. Esperado: \$${resumen.efectivoEsperado.toStringAsFixed(2)}, '
            'Contado: \$${efectivoContado.toStringAsFixed(2)}, '
            'Diferencia: \$${diferencia.toStringAsFixed(2)}.',
        'id_usuario': caja.idUsuario,
        'id_caja': idCaja,
      });

      await _corteCajaLogger.registrar(
        txn,
        idCaja: idCaja,
        totalEfectivoSistema: resumen.efectivoEsperado,
        totalTarjetaSistema: resumen.ventasTarjeta,
        totalTransferenciaSistema: resumen.ventasTransferencia,
        totalEfectivoContado: efectivoContado,
        diferencia: diferencia,
      );

      return idCaja;
    });
  }

  /// Historial completo (abiertas y cerradas), más reciente primero. Sin
  /// filtro, trae todas las cajas de todos los usuarios — el filtrado por
  /// rol (Admin ve todas, Cajero solo las suyas) se decide en la vista.
  Future<List<Caja>> obtenerHistorial({int? idUsuario}) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'Cajas',
      where: idUsuario != null ? 'id_usuario = ?' : null,
      whereArgs: idUsuario != null ? [idUsuario] : null,
      orderBy: 'fecha_apertura DESC',
    );
    return rows.map(Caja.fromMap).toList();
  }
}
