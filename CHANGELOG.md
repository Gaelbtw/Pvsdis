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

## 1.4.0 — sin publicar

> **Esta versión modifica la información guardada.** Respalda antes de
> actualizar y hazlo con la caja cerrada. El sistema hace su propio respaldo
> automático antes de tocar nada, pero el tuyo es el que no depende de que
> todo salga bien.

### Licenciamiento encendido

El sistema de licencias existía desde la 1.1.0 pero venía **apagado de
fábrica**. Esta versión trae la clave pública compilada, así que a partir de
aquí Pv Control verifica licencias.

- **No cambia nada para quien ya lo usa.** Sin archivo de licencia el estado
  es "sin licencia registrada" y **todo funciona sin restricción**, igual que
  antes. La verificación es local: la app no consulta ningún servidor.
- Cuando sí hay licencia y vence, el sistema avisa 15 días antes y da 30 días
  de gracia. Solo después se limitan reportes, exportación, alta de productos
  y configuración. **Vender, cobrar, imprimir tickets y cerrar caja nunca se
  bloquean**, en ninguna circunstancia.
- El código de instalación del equipo está en Configuración → Licencia.

### Ícono propio

El ejecutable y el instalador dejaron de usar el ícono por omisión de Flutter.

### El corte de caja, rediseñado

Cerrar caja eran demasiados clics y el resultado era un número suelto que no
explicaba nada. Ahora el cajero **cuenta como cuenta en la vida real**:
billetes por denominación y las monedas al bulto.

- **Contador de billetes**: un renglón por denominación (1000, 500, 200, 100,
  50, 20) y un solo campo para todas las monedas. El total se suma solo. Nadie
  vuelve a sumar aparte y capturar el resultado.
- **El desglose queda guardado.** Antes solo se conservaba el total contado. El
  día que alguien discuta un faltante, ahora se puede ver si el error estuvo en
  el conteo, en la suma o en la captura.
- **El conteo sigue siendo a ciegas**: mientras el cajero cuenta no ve el
  efectivo esperado ni la diferencia. Eso no cambió, y está protegido por una
  prueba automática que revisa que ningún número que forme parte del esperado
  se asome antes de cerrar.
- **El reporte de cierre se lee de corrido**: qué entró, qué salió, qué debería
  haber, qué hay y la diferencia — en ese orden, sin ir y venir entre
  pantallas.

### Colores y legibilidad

- **Negro y blanco entraron a la paleta de marca.** Antes no se podían elegir.
- **Se acabó el texto negro sobre botones oscuros.** El color del texto ya no
  está escrito a mano: se calcula del color del botón, así que cualquier color
  de marca que elijas queda legible. Verde, naranja y turquesa se oscurecieron
  un poco porque en su tono anterior ningún color de texto alcanzaba el
  contraste mínimo.
- Los botones de color claro llevan borde, para que no se pierdan contra el
  fondo blanco.

### Devoluciones: se devuelve exactamente lo cobrado

- **Una venta con promoción se devolvía al precio de lista.** Un producto de
  $100 vendido en $80 por un 2x1 se reembolsaba en $100. El sistema ahora
  guarda el importe exacto de cada línea y devuelve ese, no el de la etiqueta.
- **Las devoluciones parciales ya no dejan centavos sueltos.** Tres piezas de
  $10 con $1 de descuento se cobraron en $29.00 y se devolvían en $29.01,
  cada vez.
- **El método de pago original se busca donde de verdad está** (pagos de la
  venta, abonos del apartado, y al final la venta) en vez de asumirlo.
- Si el sistema no puede confirmar quién autorizó un reembolso en efectivo,
  **no lo autoriza**. Antes, ante un error, seguía adelante.

### Reportes

- **El reporte de un cajero ya no carga las devoluciones de toda la tienda.**
  Uno con $800 vendidos podía salir en ceros por una cancelación de $2,000 que
  hizo otro en la caja de al lado.
- **El desglose por método de pago ya no se aplasta a cero.** Si salieron $100
  del cajón y no entró efectivo ese día, dice −$100. Ponerlo en cero borraba
  del reporte una salida de dinero real.
- El costo de compra del producto se actualiza con la última compra, así la
  utilidad se mide contra lo que costó de verdad.

### Impresión

Una impresora apagada hacía que el sistema dijera que falló una operación que
**sí se había guardado**. Tres casos, los tres corregidos:

- En **compras**, el carrito no se limpiaba: se volvía a capturar la misma
  compra y el inventario y la deuda al proveedor quedaban al doble.
- En **apartados**, el abono quedaba registrado pero la pantalla decía "no se
  pudo procesar el pago". El cliente podía terminar pagando dos veces.
- En el **ticket de venta**, la falla no se veía por ningún lado: no pasaba
  absolutamente nada al presionar imprimir.

### En todas las pantallas

- **Cargando, error y "reintentar"** en 16 pantallas. Antes, si algo fallaba al
  abrir, la pantalla se quedaba vacía sin decir por qué y sin forma de
  reintentar más que cerrar el sistema.
- **Botones que decían que borraban y no borraban**: cinco pantallas confirmaban
  la eliminación aunque la base la hubiera rechazado.
- El ajuste manual de existencias trabaja sobre la diferencia, no sobre el
  número que el usuario tenía en pantalla: si alguien vendió mientras la
  ventana estaba abierta, ya no se pisa esa venta. Tampoco deja bajar el stock
  por debajo de lo apartado.

---

## 1.3.0 — sin publicar

### La pantalla de venta, rediseñada

El sistema se usa con lector de códigos, pero estaba dibujado como si se
usara tocando la pantalla: el catálogo se llevaba el 62% del ancho y el
ticket apenas el 38%. Se invirtió.

- **El escaneo tiene su propia barra**, cruzando toda la pantalla. Antes era
  un campo más dentro del catálogo, del mismo tamaño que cualquier otro. El
  borde se enciende cuando está lista para recibir el lector, que responde a
  una pregunta real: *¿está escuchando?*
- **El ticket es ahora la mitad ancha.** Es lo que el cajero mira.
- **El catálogo pasó a una pestaña** junto al cobro, para cuando el producto
  no tiene código: granel, etiqueta despegada, el cliente que pregunta.
- **La última línea escaneada se resalta.** Uno pasa el producto mirando al
  cliente, no a la pantalla: hace falta poder confirmar de reojo que entró, y
  cuál. Si esa línea se quita del ticket, el resaltado se apaga solo.
- El fondo de la pantalla de venta era de un gris distinto al del resto del
  sistema. Ahora es el mismo.

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

### Rendimiento

- Los reportes por rango de fechas de **devoluciones, apartados y movimientos
  de inventario** ya no recorren toda la tabla. En una instalación con historia
  la diferencia se nota al abrir cada reporte.
- La **bitácora de actividad se recorta sola** a los últimos 24 meses
  (configurable). Antes crecía sin límite y hacía que el respaldo diario a la
  USB tardara más cada mes.
- El sistema **abre más rápido**: lo que no depende entre sí ahora se carga a la
  vez en vez de en fila.

### Avisos

- **Aviso de versión nueva** dentro del sistema: una franja discreta —nunca una
  ventana que interrumpa— cuando hay una actualización publicada. Descarga el
  instalador y comprueba que llegó completo, pero **no lo instala**: eso lo
  decide el negocio, con la caja cerrada.
- Si la actualización va a modificar la información guardada, el aviso lo dice
  y recomienda respaldar antes.
- Aviso de licencia visible en todas las pantallas cuando está vencida o hay
  algo que resolver, y un aviso al abrir cuando está por vencer.

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
