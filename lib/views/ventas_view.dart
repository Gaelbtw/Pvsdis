import 'dart:async';

import 'package:flutter/material.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/session/ventas_en_espera_store.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/descuento_utils.dart';
import '../core/utils/escaneo_utils.dart';
import '../core/utils/pagos_mixtos.dart';
import '../core/utils/promociones_engine.dart';
import '../controllers/caja_controller.dart';
import '../controllers/ventas_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/promociones_controller.dart';
import '../models/caja_model.dart';
import '../models/carrito_venta.dart';
import '../models/producto_model.dart';
import '../models/promocion_model.dart';
import '../models/venta_en_espera.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/toast.dart';
import '../widgets/ventas/autorizacion_descuento_dialog.dart';
import '../widgets/ventas/descuento_dialog.dart';
import '../widgets/ventas/pagos_mixtos_section.dart';
import '../widgets/ventas/promociones_aplicadas_section.dart';
import '../widgets/ventas/venta_exitosa_dialog.dart';
import '../widgets/ventas/ventas_atajos.dart' as atajos;
import '../models/cliente_model.dart';
import '../widgets/nav_bar.dart';
import 'caja_view.dart';

import '../services/ticket_service.dart';
import '../services/impresion_service.dart';
import '../services/reimpresion_venta_service.dart';
import '../services/cajon_service.dart';

class VentasView extends StatefulWidget {
  final Cliente? cliente;

  const VentasView({
    super.key,
    this.cliente,
  });

  @override
  State<VentasView> createState() => _VentasViewState();
}

class _VentasViewState extends State<VentasView> {
  final ventasController = VentasController();
  final productoController = ProductoController();
  final cajaController = CajaController();
  final promocionesController = PromocionesController();

  Cliente? clienteSeleccionado;

  List<Producto> productos = [];

  /// Copia del catálogo con el texto de búsqueda ya en minúsculas, calculado
  /// una sola vez al cargar (ver [_ProductoBuscable] y [_recalcularFiltro]).
  List<_ProductoBuscable> _indiceBusqueda = const [];

  Map<int, int> stockProductos = {};
  final _carrito = CarritoVenta();
  List<Map<String, dynamic>> get carrito => _carrito.items;

  final Map<int, TextEditingController> controllers = {};

  final busquedaCtrl = TextEditingController();
  final busquedaFocus = FocusNode();

  String busqueda = "";

  /// Temporizador del debounce del buscador (ver [_onBusquedaChanged]).
  Timer? _debounceBusqueda;

  List<Map<String, dynamic>> pagos = [];
  ResultadoValidacionPagos resultadoPagos = validarPagosMixtos(total: 0, pagos: const []);
  int ventaCounter = 0;

  /// Id de la última venta registrada en esta sesión de la pantalla, para
  /// poder reimprimir su ticket sin ir a Reportes. `null` hasta la primera
  /// venta.
  int? _ultimaVentaId;

  bool cargando = true;

  Caja? _cajaAbierta;

  List<Promocion> _promocionesActivas = [];

  // Selección de línea del carrito para navegar con flechas y eliminar con
  // Delete (ver atajos de teclado más abajo). Puramente de UI: no cambia
  // ninguna regla de venta.
  int? _lineaSeleccionada;

  /// La política de descuentos del cajero es configurable aparte de la
  /// matriz de permisos (`descuentoCajeroPuedeAplicar` /
  /// `descuentoCajeroRequiereAutorizacion` en Configuración), así que aquí
  /// sí se pregunta por el rol -- pero con [SessionManager.isCajero], no
  /// comparando el string a mano.
  bool get esCajero => SessionManager.isCajero;

  bool get puedeAplicarDescuentos =>
      !esCajero || AppConfig.actual.descuentoCajeroPuedeAplicar;

  /// Qué promociones automáticas aplican al carrito actual y cuánto
  /// descuentan, línea por línea. Función pura (`evaluarPromociones`) sobre
  /// el carrito y las promociones ya cargadas: se recalcula en cada build,
  /// igual que [calculo], así que agregar/quitar/cambiar cantidades la
  /// actualiza automáticamente sin lógica adicional.
  ResultadoPromociones get resultadoPromociones => evaluarPromociones(
        carrito: carrito,
        promocionesActivas: _promocionesActivas,
      );

  /// Única fuente de verdad del desglose financiero de la venta en curso
  /// (subtotal, descuentos, total). Se recalcula en cada build a partir del
  /// carrito, las promociones vigentes y el descuento global — nunca se
  /// guarda un total aparte que se pueda desincronizar.
  VentaCalculada get calculo => calcularVenta(
        carrito: carrito,
        descuentosPromocionPorLinea: resultadoPromociones.descuentoPorLinea,
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
        descuentoMaximoPorcentaje: AppConfig.actual.descuentoMaximoPorcentaje,
      );

  @override
  void initState() {
    super.initState();

    clienteSeleccionado = widget.cliente;

    cargarProductos();
    cargarCaja();
    cargarPromociones();
  }

  Future<void> cargarPromociones() async {
    final promociones = await promocionesController.obtenerActivasVigentes();
    if (!mounted) return;
    setState(() => _promocionesActivas = promociones);
  }

  // 🔐 CAJA
  Future<void> cargarCaja() async {
    // Sin sesión no hay caja que buscar (ver el mismo criterio en CajaView).
    final idUsuario = SessionManager.currentUserId;
    final caja =
        idUsuario == null ? null : await cajaController.obtenerCajaAbierta(idUsuario);

    if (!mounted) return;
    setState(() => _cajaAbierta = caja);
  }

  Future<void> irAAbrirCaja() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CajaView()),
    );
    await cargarCaja();
  }

  // 🔥 CARGAR PRODUCTOS
  Future<void> cargarProductos() async {
    final data = await productoController.obtenerConStock();

    if (!mounted) return;

    final Map<int, int> stock = {};
    final List<Producto> lista = [];
    final List<_ProductoBuscable> indice = [];

    for (final row in data) {
      final p = Producto.fromMap(row);
      lista.add(p);
      indice.add(_ProductoBuscable(p));
      if (p.idProducto != null) {
        // "disponible" (física - reservada por Apartados), no la existencia
        // física a secas: una unidad ya apartada no debe ofrecerse aquí.
        stock[p.idProducto!] = (row['disponible'] as int?) ?? 0;
      }
    }

    setState(() {
      productos = lista;
      _indiceBusqueda = indice;
      stockProductos = stock;
      cargando = false;
      _recalcularFiltro();
    });
  }

  // 🔍 FILTRO
  //
  // Antes esto era un getter que recorría el catálogo entero (con un
  // `toLowerCase()` por producto, que asigna un String nuevo cada vez). Se
  // consumía desde `itemCount` Y desde el `itemBuilder` de la grilla, así que
  // se ejecutaba completo una vez por CELDA dibujada: ~35 pasadas sobre todo
  // el catálogo en cada frame. Con 1.000 productos eran ~72.000 asignaciones
  // de String por rebuild, y como el buscador hace `setState` por tecla, un
  // código de barras de 13 dígitos disparaba 13 rebuilds seguidos. En una PC
  // de punto de venta de gama baja eso es GC constante y scroll a tirones.
  //
  // Ahora el resultado se calcula UNA vez -- solo cuando cambia el texto o se
  // recarga el catálogo -- y las celdas leen una lista ya lista.
  List<Producto> _productosFiltrados = const [];

  /// Amortigua el tecleo en el buscador: sin esto, cada carácter reconstruía
  /// toda la pantalla de ventas.
  ///
  /// Es seguro para el lector de código de barras: el escáner termina con
  /// Enter, que entra por `onSubmitted: procesarEscaneo` -- un camino
  /// distinto, que no pasa por aquí y sigue siendo instantáneo. Lo único que
  /// se amortigua es la búsqueda escrita a mano.
  void _onBusquedaChanged(String valor) {
    _debounceBusqueda?.cancel();
    _debounceBusqueda = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        busqueda = valor;
        _recalcularFiltro();
      });
    });
  }

  void _recalcularFiltro() {
    final consulta = busqueda.trim().toLowerCase();

    if (consulta.isEmpty) {
      // Sin filtro no hace falta copiar nada: se reusa la misma lista.
      _productosFiltrados = productos;
      return;
    }

    _productosFiltrados = [
      for (final entrada in _indiceBusqueda)
        if (entrada.coincide(consulta)) entrada.producto,
    ];
  }

  // 🛒 AGREGAR PRODUCTO
  void agregarProducto(Producto p) {
    final yaExistia = _carrito.contieneProducto(p.idProducto);

    setState(() {
      _carrito.agregar(p);

      if (!yaExistia) {
        controllers[p.idProducto!] = TextEditingController(text: "1");
      }
    });
  }

  // 🔫 ESCANEO DE CÓDIGO DE BARRAS
  // Los lectores USB emulan un teclado: "escriben" el código y envían
  // Enter, por lo que basta con onSubmitted de un TextField normal (sin
  // listeners de teclado en bruto) para capturar el evento.
  void procesarEscaneo(String codigo) {
    if (codigo.trim().isEmpty) return;

    final resultado = resolverEscaneo(
      codigo: codigo,
      productos: productos,
      stockDisponible: stockProductos,
      cantidadEnCarrito: _carrito.cantidadEnCarrito,
    );

    switch (resultado.tipo) {
      case TipoResultadoEscaneo.agregado:
        agregarProducto(resultado.producto!);
        break;
      case TipoResultadoEscaneo.noEncontrado:
      case TipoResultadoEscaneo.inactivo:
      case TipoResultadoEscaneo.stockInsuficiente:
        showDialog(
          context: context,
          builder: (_) => CustomAlert(
            titulo: 'Escaneo',
            mensaje: resultado.mensaje,
            icono: Icons.error_outline,
          ),
        );
        break;
    }

    _limpiarBusqueda();
    busquedaFocus.requestFocus();
  }

  /// Vacía el buscador y recalcula el filtro.
  ///
  /// Cancela el debounce pendiente antes de nada: si el usuario escribió y el
  /// temporizador todavía no disparó, sin este `cancel` el callback se
  /// ejecutaría 120 ms después y volvería a poner el texto viejo en
  /// [busqueda], deshaciendo el borrado.
  void _limpiarBusqueda() {
    _debounceBusqueda?.cancel();
    busquedaCtrl.clear();
    setState(() {
      busqueda = "";
      _recalcularFiltro();
    });
  }

  // ➕➖ CAMBIAR CANTIDAD
  void cambiarCantidad(int index, int delta) {
    final id = carrito[index]['id_producto'];

    setState(() {
      final eliminado = _carrito.cambiarCantidad(index, delta);

      if (eliminado) {
        controllers[id]?.dispose();
        controllers.remove(id);
      } else if (controllers.containsKey(id)) {
        controllers[id]!.text = carrito[index]['cantidad'].toString();
      }
    });
  }

  // 💰 TOTAL (ya con descuentos aplicados)
  double get total => calculo.total;

  // 💳 PAGOS
  void actualizarPagos(List<Map<String, dynamic>> nuevosPagos, ResultadoValidacionPagos resultado) {
    setState(() {
      pagos = nuevosPagos;
      resultadoPagos = resultado;
    });
  }

  // 🏷 DESCUENTO POR PRODUCTO
  void editarDescuentoLinea(int index) {
    final item = carrito[index];
    final base = (item['precio'] as num) * (item['cantidad'] as int);
    final tipoActual = item['descuento_tipo'] as TipoDescuento?;
    final valorActual = (item['descuento_valor'] as num?)?.toDouble() ?? 0;

    mostrarDescuentoDialog(
      context,
      titulo: 'Descuento a "${item['nombre']}"',
      base: base.toDouble(),
      tipoActual: tipoActual,
      valorActual: valorActual,
      onAplicar: (tipo, valor) {
        setState(() => _carrito.aplicarDescuentoLinea(index, tipo, valor));
      },
      onQuitar: tipoActual != null
          ? () => setState(() => _carrito.quitarDescuentoLinea(index))
          : null,
    );
  }

  // 🏷 DESCUENTO GLOBAL
  void editarDescuentoGlobal() {
    if (carrito.isEmpty) return;

    // Base real del descuento global: el subtotal ya después de las
    // promociones automáticas y de los descuentos de línea (sin el propio
    // descuento global todavía).
    final baseGlobal = calcularVenta(
      carrito: carrito,
      descuentosPromocionPorLinea: resultadoPromociones.descuentoPorLinea,
      descuentoMaximoPorcentaje: AppConfig.actual.descuentoMaximoPorcentaje,
    ).total;

    mostrarDescuentoDialog(
      context,
      titulo: 'Descuento global de la venta',
      base: baseGlobal,
      tipoActual: _carrito.descuentoGlobalTipo,
      valorActual: _carrito.descuentoGlobalValor,
      onAplicar: (tipo, valor) {
        setState(() => _carrito.aplicarDescuentoGlobal(tipo, valor));
      },
      onQuitar: _carrito.descuentoGlobalTipo != null
          ? () => setState(() => _carrito.quitarDescuentoGlobal())
          : null,
    );
  }

  // ⌨️ ATAJOS DE TECLADO
  //
  // El widget compartido `VentasAtajos` (widgets/ventas/ventas_atajos.dart)
  // ya se encarga de no disparar F4/flechas/Delete mientras se escribe en
  // un campo de texto; aquí solo vive la lógica de negocio de cada atajo.
  void _atajoEnfocarBusqueda() {
    busquedaFocus.requestFocus();
    busquedaCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: busquedaCtrl.text.length,
    );
  }

  void _atajoConfirmarVenta() {
    final puedeConfirmar = atajos.puedeConfirmarVenta(
      carritoVacio: carrito.isEmpty,
      pagosValidos: resultadoPagos.esValido,
      cajaAbierta: _cajaAbierta != null,
    );
    if (puedeConfirmar) {
      iniciarConfirmacionVenta();
    }
  }

  void _atajoEscape() {
    FocusScope.of(context).unfocus();
    _limpiarBusqueda();
    setState(() => _lineaSeleccionada = null);
  }

  void _moverSeleccionCarrito(int delta) {
    setState(() {
      _lineaSeleccionada = atajos.moverSeleccionCarrito(
        actual: _lineaSeleccionada,
        delta: delta,
        totalLineas: carrito.length,
      );
    });
  }

  Future<void> _atajoEliminarLineaSeleccionada() async {
    final index = _lineaSeleccionada;
    if (index == null || index < 0 || index >= carrito.length) return;

    final item = carrito[index];
    final nombre = item['nombre']?.toString() ?? 'este producto';
    final cantidadActual = item['cantidad'] as int;

    await confirmarAccion(
      context: context,
      tituloConfirmar: 'Quitar del carrito',
      mensajeConfirmar: '¿Quitar "$nombre" del carrito?',
      iconoConfirmar: Icons.delete_outline,
      textoConfirmar: 'Quitar',
      accion: () async {
        cambiarCantidad(index, -cantidadActual);
        if (mounted) setState(() => _lineaSeleccionada = null);
      },
      tituloExito: 'Producto quitado',
      mensajeExito: '"$nombre" se quitó del carrito.',
    );
  }

  // 🗑 VACIAR CARRITO (cancela la venta en curso y limpia la pantalla)
  Future<void> _vaciarCarrito() async {
    if (carrito.isEmpty) return;

    await confirmarAccion(
      context: context,
      tituloConfirmar: 'Vaciar carrito',
      mensajeConfirmar:
          '¿Quitar todos los productos y cancelar esta venta en curso?',
      iconoConfirmar: Icons.remove_shopping_cart_outlined,
      textoConfirmar: 'Vaciar',
      accion: () async {
        setState(() {
          _carrito.limpiar();
          pagos = [];
          ventaCounter++;
          _lineaSeleccionada = null;

          for (final c in controllers.values) {
            c.dispose();
          }
          controllers.clear();
        });
      },
      mensajeExito: 'Carrito vaciado.',
    );
  }

  // 🖨 REIMPRIMIR EL ÚLTIMO TICKET (reconstruye el PDF desde la venta guardada)
  Future<void> _reimprimirUltimoTicket() async {
    final idVenta = _ultimaVentaId;
    if (idVenta == null) return;

    try {
      final pdf = await ReimpresionVentaService.generar(idVenta);
      await ImpresionService.imprimir(pdf);
      if (!mounted) return;
      Toast.exito(context, 'Reimprimiendo el ticket de la venta #$idVenta.');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo reimprimir el ticket.');
    }
  }

  // ⏸ PONER LA VENTA EN CURSO EN ESPERA (y dejar la pantalla lista para otra)
  void _pausarVenta() {
    if (carrito.isEmpty) return;

    final venta = VentasEnEsperaStore.instancia.guardar(
      items: _carrito.copiaItems(),
      cliente: clienteSeleccionado,
      descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
      descuentoGlobalValor: _carrito.descuentoGlobalValor,
    );

    setState(() {
      _carrito.limpiar();
      pagos = [];
      ventaCounter++;
      _lineaSeleccionada = null;

      for (final c in controllers.values) {
        c.dispose();
      }
      controllers.clear();
    });

    Toast.exito(context, 'Venta puesta en espera (#${venta.folio}).');
  }

  // ▶️ RETOMAR una venta en espera, cargándola en el carrito actual. Si ya hay
  // una venta en curso, se pone en espera primero para no perderla.
  void _retomarVenta(VentaEnEspera venta) {
    final habiaVentaEnCurso = carrito.isNotEmpty;

    if (habiaVentaEnCurso) {
      VentasEnEsperaStore.instancia.guardar(
        items: _carrito.copiaItems(),
        cliente: clienteSeleccionado,
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
      );
    }

    setState(() {
      _carrito.reemplazar(
        nuevosItems: venta.items,
        descuentoGlobalTipo: venta.descuentoGlobalTipo,
        descuentoGlobalValor: venta.descuentoGlobalValor,
      );
      clienteSeleccionado = venta.cliente;

      for (final c in controllers.values) {
        c.dispose();
      }
      controllers.clear();
      for (final item in carrito) {
        final id = item['id_producto'] as int;
        controllers[id] =
            TextEditingController(text: item['cantidad'].toString());
      }

      pagos = [];
      ventaCounter++;
      _lineaSeleccionada = null;
    });

    VentasEnEsperaStore.instancia.eliminar(venta);

    if (!mounted) return;
    Toast.exito(
      context,
      habiaVentaEnCurso
          ? 'Se retomó la venta #${venta.folio}. La anterior quedó en espera.'
          : 'Se retomó la venta #${venta.folio}.',
    );
  }

  // 📋 LISTA DE VENTAS EN ESPERA (retomar o descartar cada una)
  void _mostrarVentasEnEspera() {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final ventas = VentasEnEsperaStore.instancia.ventas;

          return AlertDialog(
            title: const Text('Ventas en espera'),
            content: SizedBox(
              width: 420,
              child: ventas.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No hay ventas en espera.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: ventas.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final v = ventas[i];
                        final cliente = v.cliente?.nombre ?? 'Consumidor final';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryLighter,
                            child: Text('#${v.folio}',
                                style: TextStyle(
                                    fontSize: AppText.caption,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark)),
                          ),
                          title: Text(cliente,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${v.totalUnidades} artículo(s) · ${AppConfig.formatoMoneda(v.subtotalAproximado)} · ${_horaCorta(v.creadaEn)}',
                            style: const TextStyle(fontSize: AppText.caption),
                          ),
                          trailing: IconButton(
                            tooltip: 'Descartar',
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.error),
                            onPressed: () {
                              VentasEnEsperaStore.instancia.eliminar(v);
                              setDialogState(() {});
                              setState(() {});
                            },
                          ),
                          onTap: () {
                            Navigator.pop(dialogContext);
                            _retomarVenta(v);
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _horaCorta(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'p.m.' : 'a.m.'}';
  }

  // 🧾 INICIAR CONFIRMACIÓN (pide motivo/autorización si el descuento lo amerita)
  void iniciarConfirmacionVenta() {
    if (carrito.isEmpty) return;

    if (calculo.descuentoTotal > 0 && !puedeAplicarDescuentos) {
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Descuento no permitido',
          mensaje: 'No tienes permiso para aplicar descuentos. Contacta a un administrador.',
          icono: Icons.block,
        ),
      );
      return;
    }

    if (calculo.requiereAutorizacion) {
      mostrarAutorizacionDescuentoDialog(
        context,
        requiereCredencialesAdmin: esCajero && AppConfig.actual.descuentoCajeroRequiereAutorizacion,
        onConfirmar: (motivo, autorizadoPor) {
          confirmarVenta(descuentoMotivo: motivo, descuentoAutorizadoPor: autorizadoPor);
        },
      );
      return;
    }

    confirmarVenta();
  }

  void confirmarVenta({String? descuentoMotivo, int? descuentoAutorizadoPor}) {
    // Ya no mostramos un diálogo genérico de "¿confirmar venta?": el botón
    // "Confirmar Venta" cobra de inmediato y el resultado (con opción de
    // imprimir) se muestra en la pantalla de éxito ([VentaExitosaDialog]).
    vender(descuentoMotivo: descuentoMotivo, descuentoAutorizadoPor: descuentoAutorizadoPor);
  }

  // 🧾 VENDER
  Future<void> vender({String? descuentoMotivo, int? descuentoAutorizadoPor}) async {
    if (carrito.isEmpty) return;

    if (!resultadoPagos.esValido) {
      Toast.error(context, resultadoPagos.mensajeError ?? 'Revisa los pagos capturados.');
      return;
    }

    try {
      final ventaCalculada = calculo;
      final promocionesVenta = resultadoPromociones;
      final pagosVenta = pagos;
      final cambioVenta = resultadoPagos.cambio;

      final idVenta = await ventasController.insertarVentaCompleta(
        carrito: carrito,
        pagos: pagosVenta,
        idCliente: clienteSeleccionado?.idCliente,
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
        descuentoMotivo: descuentoMotivo,
        descuentoAutorizadoPor: descuentoAutorizadoPor,
      );

      // Abre el cajón si se cobró algo en efectivo (y la config lo permite).
      if (pagosVenta.any((p) => esMetodoEfectivo(p['metodo_pago'] as String))) {
        await CajonService.abrirSiCorresponde();
      }

      // Guarda tras `await CajonService.abrirSiCorresponde()`: la apertura del
      // cajón habla con el spooler de Windows y puede tardar, tiempo de sobra
      // para que el usuario salga de la pantalla.
      if (!mounted) return;

      // La venta ya se cobró: vaciamos el carrito y guardamos el último id
      // para poder reimprimir con F9. El ticket ya NO se imprime solo; el
      // cajero decide en la pantalla de éxito.
      setState(() {
        // Se descuenta el stock vendido del mapa en memoria.
        //
        // Antes esto NO se hacía en el camino de éxito (solo se recargaba
        // todo el catálogo en el `catch`), así que tras vender las últimas
        // unidades la pantalla seguía mostrándolas como disponibles y el
        // escáner las dejaba agregar de nuevo. La venta no llegaba a
        // duplicarse —la transacción valida el stock real y la rechaza—,
        // pero el cajero se topaba con "inventario insuficiente" al cobrar
        // en vez de al escanear, que es cuando aún puede reaccionar.
        //
        // Se ajustan solo las líneas vendidas en vez de volver a consultar
        // el catálogo completo: `obtenerConStock()` escanea tres tablas y
        // reconstruye N objetos, y aquí es justo cuando el cajero quiere
        // empezar la siguiente venta.
        for (final linea in ventaCalculada.lineas) {
          final actual = stockProductos[linea.idProducto];
          if (actual != null) {
            stockProductos[linea.idProducto] = actual - linea.cantidad;
          }
        }

        _carrito.limpiar();

        _ultimaVentaId = idVenta;
        pagos = [];
        ventaCounter++;

        for (var c in controllers.values) {
          c.dispose();
        }

        controllers.clear();
      });

      if (!mounted) return;

      await VentaExitosaDialog.mostrar(
        context,
        idVenta: idVenta,
        total: ventaCalculada.total,
        cambio: cambioVenta,
        onImprimir: () => imprimirTicket(
          ventaCalculada,
          promocionesVenta,
          pagosVenta,
          cambioVenta,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo completar la venta. $mensaje');
      await cargarProductos();
    }
  }

  // 🖨 IMPRIMIR
  Future<void> imprimirTicket(
    VentaCalculada ventaCalculada,
    ResultadoPromociones promocionesVenta,
    List<Map<String, dynamic>> pagosVenta,
    double cambioVenta,
  ) async {
    final carritoParaTicket = ventaCalculada.lineas
        .map((l) => {
              'nombre': l.nombre,
              'precio': l.precioOriginal,
              'cantidad': l.cantidad,
              'descuento_monto': l.descuentoMonto,
            })
        .toList();

    final promocionesParaTicket = promocionesVenta.aplicaciones
        .map((a) => {'nombre': a.nombre, 'ahorro_total': a.ahorroTotal})
        .toList();

    final pdf = await TicketService.generarTicket(
      carrito: carritoParaTicket,
      total: ventaCalculada.total,
      subtotal: ventaCalculada.subtotal,
      descuento: ventaCalculada.descuentoTotal,
      pagos: pagosVenta,
      cambio: cambioVenta,
      promocionesAplicadas: promocionesParaTicket,
      ahorroPromociones: promocionesVenta.ahorroTotal,
    );

    await ImpresionService.imprimir(pdf);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),

      appBar: CustomHeader(
        titulo: clienteSeleccionado != null
            ? "Venta - ${clienteSeleccionado!.nombre}"
            : "Punto de Venta",
        mostrarVolver: true,
      ),

      body: cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : atajos.VentasAtajos(
              onEnfocarBusqueda: _atajoEnfocarBusqueda,
              onConfirmarVenta: _atajoConfirmarVenta,
              onEscape: _atajoEscape,
              onMoverSeleccion: _moverSeleccionCarrito,
              onEliminarSeleccionada: _atajoEliminarLineaSeleccionada,
              onPausar: _pausarVenta,
              onVerEnEspera: _mostrarVentasEnEspera,
              onReimprimir: _reimprimirUltimoTicket,
              onVaciar: _vaciarCarrito,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(
                24,
                20,
                24,
                24,
              ),
              child: Column(
                children: [
                  if (_cajaAbierta == null) _bannerSinCaja(),
                  Expanded(
                    child: Row(
                      children: [

                  // 🔥 CATÁLOGO DE PRODUCTOS
                  Expanded(
                    flex: 62,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: Column(
                        children: [

                          // 🔍 BUSCADOR / ESCÁNER
                          TextField(
                            controller: busquedaCtrl,
                            focusNode: busquedaFocus,
                            autofocus: true,
                            onChanged: _onBusquedaChanged,
                            onSubmitted: procesarEscaneo,
                            decoration: InputDecoration(
                              hintText: "Buscar o escanear código...",
                              prefixIcon: const Icon(
                                Icons.search,
                              ),
                              filled: true,
                              fillColor:
                                  AppColors.surface,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 📦 GRID
                          Expanded(
                            child: GridView.builder(
                              itemCount:
                                  _productosFiltrados.length,
                              // Nota: aquí se probó reducir la caché de scroll
                              // para que la grilla no construya dos filas de
                              // más fuera de pantalla. Se quitó porque
                              // `cacheExtent` quedó obsoleto en Flutter 3.41 y
                              // su reemplazo (`scrollCacheExtent`) ya no acepta
                              // un número de píxeles sino un `ScrollCacheExtent`.
                              // La ganancia era marginal frente al riesgo de
                              // usar mal una API que no se pudo verificar; el
                              // cuello de botella real de esta grilla era el
                              // filtro, que ya está resuelto.
                              // Grilla adaptativa: la cantidad de columnas se
                              // ajusta al ancho de la ventana (≈5 a 1280px, menos
                              // al achicar) y cada tarjeta tiene alto fijo, así no
                              // se desborda en la ventana mínima.
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 132,
                              ),
                              itemBuilder: (_, i) {
                                final p =
                                    _productosFiltrados[i];

                                return InkWell(
                                  borderRadius:
                                      BorderRadius.circular(
                                    18,
                                  ),
                                  onTap: () =>
                                      agregarProducto(p),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.all(
                                      16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFDFDFD,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(
                                        18,
                                      ),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [

                                        // 🏷 NOMBRE
                                        Text(
                                          p.nombre,
                                          maxLines: 2,
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                          style:
                                              const TextStyle(
                                            fontSize: AppText.body,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                          ),
                                        ),

                                        const SizedBox(height: 4),

                                        // 📦 INVENTARIO
                                        Builder(builder: (_) {
                                          final s = stockProductos[p.idProducto] ?? 0;
                                          return Text(
                                            "Inventario: $s",
                                            style: TextStyle(
                                              fontSize: AppText.caption,
                                              color: s == 0
                                                  ? AppColors.error
                                                  : s <= p.stockMinimo
                                                      ? AppColors.warning
                                                      : AppColors.success,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        }),

                                        const Spacer(),

                                        // 💰 PRECIO + AGREGAR (toda la tarjeta
                                        // agrega al tocar; el chip solo lo señala)
                                        Row(
                                          children: [
                                            Expanded(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  AppConfig.formatoMoneda(p.precio),
                                                  style: const TextStyle(
                                                    fontSize: AppText.subtitle,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              width: 26,
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius: BorderRadius.circular(9),
                                              ),
                                              child: Icon(
                                                Icons.add,
                                                size: 18,
                                                color: AppColors.onPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // 🛒 TICKET
                  Expanded(
                    flex: 38,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: Column(
                        children: [

                          // 🧾 HEADER
                          Row(
                            children: [
                              const Icon(
                                Icons.shopping_cart,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  "Detalle de Venta",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppText.title,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (VentasEnEsperaStore.instancia.hayVentas)
                                Badge.count(
                                  count:
                                      VentasEnEsperaStore.instancia.cantidad,
                                  child: IconButton(
                                    tooltip: 'Ventas en espera (F8)',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _mostrarVentasEnEspera,
                                    icon: const Icon(Icons.pending_actions),
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              if (_ultimaVentaId != null)
                                IconButton(
                                  tooltip:
                                      'Reimprimir último ticket #$_ultimaVentaId (F9)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _reimprimirUltimoTicket,
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  color: AppColors.textSecondary,
                                ),
                              if (carrito.isNotEmpty) ...[
                                IconButton(
                                  tooltip: 'Poner en espera (F7)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _pausarVenta,
                                  icon: const Icon(Icons.pause_circle_outline),
                                  color: AppColors.textSecondary,
                                ),
                                IconButton(
                                  tooltip: 'Vaciar carrito (Shift+Supr)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _vaciarCarrito,
                                  icon: const Icon(
                                      Icons.remove_shopping_cart_outlined),
                                  color: AppColors.error,
                                ),
                              ],
                            ],
                          ),

                          if (clienteSeleccionado !=
                              null) ...[
                            const SizedBox(height: 10),

                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF8F6F2,
                                ),
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      clienteSeleccionado!
                                          .nombre,
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // 🛒 ITEMS
                          Expanded(
                            child: carrito.isEmpty
                                ? const Center(
                                    child: Text(
                                      "No hay productos",
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount:
                                        carrito.length,
                                    separatorBuilder:
                                        (_, _) =>
                                            const SizedBox(
                                      height: 10,
                                    ),
                                    itemBuilder: (_, i) {
                                      final item =
                                          carrito[i];

                                      final id = item[
                                          'id_producto'];

                                      controllers[id]!
                                              .text =
                                          item['cantidad']
                                              .toString();

                                      final seleccionada =
                                          i == _lineaSeleccionada;

                                      return GestureDetector(
                                      onTap: () => setState(
                                          () => _lineaSeleccionada = i),
                                      child: Container(
                                        padding:
                                            const EdgeInsets
                                                .all(12),
                                        decoration:
                                            BoxDecoration(
                                          color: AppColors
                                              .surface,
                                          borderRadius:
                                              BorderRadius
                                                  .circular(
                                            16,
                                          ),
                                          border: seleccionada
                                              ? Border.all(
                                                  color: AppColors
                                                      .primary,
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [

                                            // 🏷 NOMBRE + DESCUENTO
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item['nombre'],
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (puedeAplicarDescuentos)
                                                  InkWell(
                                                    onTap: () => editarDescuentoLinea(i),
                                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(4),
                                                      child: Icon(
                                                        Icons.sell_outlined,
                                                        size: 18,
                                                        color: item['descuento_tipo'] != null
                                                            ? AppColors.primaryDark
                                                            : AppColors.disabled,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),

                                            const SizedBox(
                                                height: 6),

                                            Builder(builder: (_) {
                                              final precio = (item['precio'] as num).toDouble();
                                              final tieneDesc = item['descuento_tipo'] != null;
                                              final lc = calculo.lineas[i];
                                              final unit = tieneDesc && lc.cantidad > 0
                                                  ? (lc.subtotalLinea - lc.descuentoMonto) / lc.cantidad
                                                  : precio;
                                              return Text(
                                                tieneDesc
                                                    ? "${AppConfig.formatoMoneda(unit)} c/u  ·  lista ${AppConfig.formatoMoneda(precio)}"
                                                    : "${AppConfig.formatoMoneda(precio)} c/u",
                                                style: TextStyle(
                                                  fontSize: AppText.caption,
                                                  fontWeight: tieneDesc ? FontWeight.w600 : FontWeight.w400,
                                                  color: tieneDesc
                                                      ? AppColors.primaryDark
                                                      : AppColors.textSecondary,
                                                ),
                                              );
                                            }),

                                            const SizedBox(
                                                height: 10),

                                            Row(
                                              children: [

                                                // ➖
                                                IconButton(
                                                  onPressed:
                                                      () =>
                                                          cambiarCantidad(
                                                    i,
                                                    -1,
                                                  ),
                                                  icon:
                                                      const Icon(
                                                    Icons
                                                        .remove_circle_outline,
                                                  ),
                                                ),

                                                // 🔢 INPUT
                                                SizedBox(
                                                  width: 60,
                                                  child:
                                                      TextField(
                                                    controller:
                                                        controllers[
                                                            id],
                                                    keyboardType:
                                                        TextInputType.number,
                                                    textAlign:
                                                        TextAlign.center,
                                                    decoration:
                                                        InputDecoration(
                                                      isDense:
                                                          true,
                                                      filled:
                                                          true,
                                                      fillColor:
                                                          Colors.white,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                        vertical:
                                                            10,
                                                      ),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                          10,
                                                        ),
                                                      ),
                                                    ),
                                                    onChanged:
                                                        (
                                                      value,
                                                    ) {
                                                      final nuevaCantidad =
                                                          int.tryParse(
                                                        value,
                                                      );

                                                      if (nuevaCantidad !=
                                                              null &&
                                                          nuevaCantidad >
                                                              0) {
                                                        setState(
                                                          () {
                                                            item['cantidad'] =
                                                                nuevaCantidad;
                                                          },
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),

                                                // ➕
                                                IconButton(
                                                  onPressed:
                                                      () =>
                                                          cambiarCantidad(
                                                    i,
                                                    1,
                                                  ),
                                                  icon:
                                                      const Icon(
                                                    Icons
                                                        .add_circle_outline,
                                                  ),
                                                ),

                                                const Spacer(),

                                                // 💰 SUBTOTAL (con su descuento de línea, sin el global)
                                                Builder(builder: (_) {
                                                  final lineaCalculada = calculo.lineas[i];
                                                  final montoLinea = lineaCalculada.subtotalLinea -
                                                      lineaCalculada.descuentoMonto;
                                                  return Text(
                                                    AppConfig.formatoMoneda(montoLinea),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      );
                                    },
                                  ),
                          ),

                          const Divider(height: 30),

                          // 🏷️ PROMOCIONES AUTOMÁTICAS
                          Builder(builder: (_) {
                            final rp = resultadoPromociones;
                            return PromocionesAplicadasSection(
                              aplicaciones: rp.aplicaciones,
                              ahorroTotal: rp.ahorroTotal,
                            );
                          }),

                          // 🏷 DESCUENTO GLOBAL
                          if (puedeAplicarDescuentos)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: carrito.isEmpty ? null : editarDescuentoGlobal,
                                  icon: const Icon(Icons.sell_outlined, size: 18),
                                  label: Text(
                                    _carrito.descuentoGlobalTipo != null
                                        ? "Editar descuento global"
                                        : "Aplicar descuento global",
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryDark,
                                    side: BorderSide(color: AppColors.primaryDark),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 💰 ZONA DE COBRO (total dominante + pagos + botón)
                          _panelCheckout(),
                        ],
                      ),
                    ),
                  ),
                ],
                    ),
                  ),
                ],
              ),
            ),
            ),
    );
  }

  /// Zona de cobro delimitada: subtotal/descuento discretos, el TOTAL como el
  /// elemento dominante de la pantalla (lo leen cajero y cliente), los pagos y
  /// el botón de confirmar, todo dentro de un panel para que el ojo aterrice
  /// aquí de inmediato. Antes vivía suelto tras el listado del carrito, con el
  /// total en 22px (apenas mayor que el texto normal) y colores hardcodeados.
  Widget _panelCheckout() {
    final c = calculo;
    final habilitado = carrito.isNotEmpty && resultadoPagos.esValido && _cajaAbierta != null;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (c.descuentoTotal > 0) ...[
            _lineaResumen("Subtotal", AppConfig.formatoMoneda(c.subtotal)),
            const SizedBox(height: 6),
            _lineaResumen("Descuento", "-${AppConfig.formatoMoneda(c.descuentoTotal)}", color: AppColors.error),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  "TOTAL",
                  style: TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    AppConfig.formatoMoneda(c.total),
                    style: const TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PagosMixtosSection(
            key: ValueKey(ventaCounter),
            total: total,
            onCambio: actualizarPagos,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: habilitado ? iniciarConfirmacionVenta : null,
              icon: const Icon(Icons.check_circle),
              label: const Text(
                "Confirmar venta  ·  F4",
                style: TextStyle(fontSize: AppText.bodyLg, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaResumen(String etiqueta, String valor, {Color? color}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: const TextStyle(color: AppColors.textSecondary)),
          Text(valor, style: TextStyle(color: color ?? AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ],
      );

  // 🔐 BANNER SIN CAJA
  Widget _bannerSinCaja() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.error),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Debes abrir tu caja antes de vender.",
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: irAAbrirCaja,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: const Text("Abrir Caja"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceBusqueda?.cancel();
    busquedaCtrl.dispose();
    busquedaFocus.dispose();

    for (var c in controllers.values) {
      c.dispose();
    }

    super.dispose();
  }
}

/// Un [Producto] junto con su nombre y código de barras ya pasados a
/// minúsculas.
///
/// Existe para que `toLowerCase()` se pague UNA vez por producto al cargar el
/// catálogo, y no una vez por producto por cada tecla y por cada celda
/// dibujada (ver el comentario de `_recalcularFiltro`). No se pusieron estos
/// campos en el propio [Producto] porque su constructor es `const` y Dart no
/// admite `late final` con inicializador en una clase con constructor
/// constante -- hacerlo obligaría a quitar el `const`, que se usa en varios
/// tests.
class _ProductoBuscable {
  _ProductoBuscable(this.producto)
      : nombre = producto.nombre.toLowerCase(),
        codigoBarras = producto.codigoBarras?.toLowerCase() ?? '';

  final Producto producto;
  final String nombre;
  final String codigoBarras;

  bool coincide(String consultaEnMinusculas) =>
      nombre.contains(consultaEnMinusculas) ||
      codigoBarras.contains(consultaEnMinusculas);
}
