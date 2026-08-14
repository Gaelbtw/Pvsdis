# Historial de cambios — Pv Control

Qué cambió en cada versión, escrito para quien usa el punto de venta, no para
quien lo programa.

Formato: `MAYOR.MENOR.PARCHE`.

- **PARCHE** (1.0.**1**) — correcciones. Nada nuevo que aprender.
- **MENOR** (1.**1**.0) — funciones nuevas. **También cualquier cambio en la
  base de datos**, aunque sea chico: el número debe delatar que la base va a
  cambiar al actualizar.
- **MAYOR** (**2**.0.0) — cambios grandes que modifican cómo se trabaja.

> **Antes de actualizar en el negocio:** caja cerrada y sin ventas en curso.
> Nunca a media venta.

---

## 1.1.0 — sin publicar

### Licencia (apagada de fábrica)

- Sistema de licencias con verificación **sin internet**: la app comprueba la
  firma del archivo y no consulta ningún servidor.
- Pantalla **Configuración → Licencia**: muestra el código de instalación de la
  computadora, con botón para copiarlo, e importa el archivo de licencia.
- La licencia tolera cambios de la computadora: cambiar el disco duro o
  renombrar el equipo **no** obliga a reactivar. Reinstalar Windows o cambiar la
  tarjeta madre, sí.
- Al vencer, el sistema avisa 15 días antes y da 30 días de gracia. Después se
  limitan reportes, exportación, alta de productos y configuración.
  **Vender, cobrar, imprimir tickets y cerrar caja nunca se bloquean.**

> Mientras no se emita ninguna licencia, el sistema funciona sin restricción
> alguna. Actualizar a esta versión no cambia nada para quien ya lo usa.

### Instalación

- El instalador puede firmarse digitalmente (opcional). Sin firma, se genera
  igual que antes.
- Al generar el instalador se muestra su código SHA256, para entregarlo junto
  al archivo y que se pueda verificar que llegó completo.

---

## 1.0.0 — 14 de agosto de 2026

Primera versión de Pv Control lista para instalar en un negocio.

### Ventas y cobro

- Cobro con efectivo, tarjeta, transferencia y **pagos mixtos** (varios métodos
  en una misma venta).
- Descuentos por línea y sobre el total, con límite configurable y
  **autorización de un administrador** cuando se pasa del umbral.
- **Promociones automáticas**: 2x1, combos, porcentaje por categoría y por
  producto. Se aplican solas al cobrar.
- **Ventas en espera**: dejar una venta pausada y atender a otro cliente sin
  perder el carrito.
- Búsqueda por código de barras, por SKU y por nombre.
- Reimpresión de ticket de cualquier venta anterior.
- Atajos de teclado para cobrar sin soltar el lector.

### Caja

- Apertura con fondo, movimientos de entrada y salida, y cierre con arqueo.
- **El cajero cuenta a ciegas**: no ve el efectivo esperado ni la diferencia
  hasta que confirma su conteo. El resultado se revela después, cuando ya no se
  puede ajustar.
- **Corte X** (parcial, sin cerrar) y corte de caja con ticket impreso.
- Historial de cajas por turno.
- Corte obligatorio al salir del sistema.

### Inventario y catálogo

- Productos con categorías, código de barras, **SKU** e **IVA por producto**
  (cuando un producto tiene tasa propia, sustituye a la general).
- Control de existencias con mínimo por producto y alertas de stock bajo.
- Ajustes de inventario **con motivo obligatorio** (merma, robo, corrección,
  caducidad) para que después se sepa por qué bajó.
- Captura de margen: se teclea el margen deseado y calcula el precio de venta.
- Importación y exportación de catálogo en CSV.

### Clientes, apartados y pedidos

- Directorio de clientes.
- **Apartados** con abonos parciales, saldo, vencimiento y ticket de abono.
- Pedidos con seguimiento de estado.

### Compras y proveedores

- Registro de compras a proveedores, con actualización automática del costo.
- **Cuentas por pagar** con abonos y saldo por proveedor.

### Devoluciones

- Devolución total o parcial, con reembolso al método de pago original.
- **Merma**: se puede devolver mercancía dañada sin regresarla al inventario.
- Recalcula el descuento y las promociones proporcionalmente.

### Reportes

- Ventas por día, por producto, por categoría, por usuario y por método de pago.
- **Reporte de utilidad** con el costo real congelado al momento de la venta,
  no el de hoy.
- Movimientos de inventario, promociones aplicadas y devoluciones.
- Exportación a CSV.

### Usuarios y seguridad

- Roles Administrador, Supervisor y Cajero con matriz de permisos por módulo.
- Entrada con contraseña o con **PIN** de acceso rápido.
- **Sin usuario de fábrica**: el primer arranque obliga a crear la cuenta de
  administrador. Nadie puede entrar con una contraseña por defecto.
- **Bloqueo por intentos fallidos**, con espera creciente. El contador
  sobrevive a cerrar y reabrir el programa.
- **Bitácora de actividad**: quién hizo qué y cuándo, con el detalle del cambio.

### Respaldos

- Respaldo manual desde la app y copia a memoria USB o disco externo.
- **Respaldo automático diario** programado en Windows, con retención de las
  últimas 30 copias. Si la computadora estaba apagada a la hora programada, el
  respaldo corre en cuanto se prende.
- Aviso en pantalla cuando el respaldo externo lleva **más de 3 días** sin
  correr.
- Respaldo automático de la base **antes de cada actualización** que cambie su
  estructura.

### Impresión

- Tickets en papel de 58 mm y 80 mm.
- Impresión directa sin diálogo de Windows (opcional).
- **Apertura del cajón de dinero** al cobrar en efectivo y al cerrar caja, por
  puerto serie o por la impresora.
- Logo, datos y mensaje del negocio en el ticket. IVA desglosado opcional.

### Sincronización (opcional)

- Sincronización con servidor para varias sucursales. **Apagada de fábrica**:
  el sistema funciona completo sin internet.
- Los cambios hechos sin conexión se encolan y suben solos al reconectar.
- Pantalla de diagnóstico para los cambios que el servidor rechazó.

### Instalación y soporte

- Instalador de Windows que **conserva la información del negocio** al
  reinstalar o actualizar.
- Paquete de instalación en USB, sin necesidad de internet en la computadora
  del negocio.
- **Protección contra instalar una versión anterior**: el sistema detecta que la
  información fue creada por una versión más reciente y avisa con un mensaje
  claro en vez de dañar la base de datos.
- **Reporte de soporte** desde Configuración: genera un archivo de texto con el
  diagnóstico del sistema para mandarlo por WhatsApp. No incluye datos de
  clientes ni de ventas.
- La versión del sistema es visible en la pantalla de entrada y en
  Configuración.
