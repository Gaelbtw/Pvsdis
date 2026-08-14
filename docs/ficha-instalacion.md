# Instalación en sitio — checklist, capacitación y control

Documento operativo para el día de la instalación. No es para el cliente
(eso es `windows/installer/usb/LEEME.txt`): es para ti.

Tres partes:

1. **Checklist** — antes de ir, en el sitio, antes de irte.
2. **Guion de capacitación** — 30 minutos, en orden.
3. **Ficha del cliente y registro de instalaciones** — para saber a los ocho
   clientes quién tiene qué.

---

## 1. Checklist de instalación

### Antes de salir

- [ ] USB preparada con `windows\installer\preparar_usb.ps1` (instalador,
      VC_redist, scripts de respaldo, LEEME con versión y SHA256).
- [ ] Versión del instalador anotada: `[__.__.__]`
- [ ] **Segunda USB o disco externo** para el respaldo, si el cliente no la
      tiene. Llévala de repuesto: es el paso que más se salta y el más caro de
      saltarse.
- [ ] Catálogo del cliente ya en CSV, revisado y con precios cuadrados.
- [ ] Contrato de servicio impreso por duplicado, con el Anexo B lleno.
- [ ] Aviso de privacidad (modelo integral + corto) impreso.
- [ ] Confirmado por teléfono: **¿la computadora tiene contraseña de
      administrador de Windows y alguien la sabe?** Sin eso no se instala nada,
      y descubrirlo allá es un viaje perdido.

### Al llegar: revisar el equipo

- [ ] Windows 10 o superior, 64 bits.
- [ ] Espacio libre en `C:` mínimo `[2 GB]`.
- [ ] La impresora térmica enciende, tiene papel y **imprime la página de
      prueba desde Windows**. Si no imprime desde Windows, no va a imprimir
      desde Pv Control: primero resuelve eso.
- [ ] El cajón de dinero abre con la impresora, o hay puerto COM identificado.
- [ ] El lector de código de barras teclea al Bloc de notas.
- [ ] Preguntar a qué hora cierra el negocio, para programar el respaldo
      **una hora antes** — si la PC se apaga al cerrar, el respaldo nunca corre
      a las 23:00.

### Instalación

- [ ] `1-VC_redist.x64.exe`
- [ ] `2-PvControl-Setup-X.Y.Z.exe` como administrador. Avisar de la pantalla
      azul de SmartScreen **antes** de que salga, para que no se asusten.
- [ ] Primer arranque: crear la cuenta de administrador.
      **La contraseña la teclea el dueño, no tú.** Que la anote él, delante de
      ti, en un papel que se lleve.
- [ ] Verificar el pie de la pantalla de entrada: dice la versión correcta.

### Configuración

- [ ] Negocio: nombre, logo, domicilio, teléfono, RFC.
- [ ] Moneda y tasa de IVA. Preguntar si quiere el IVA desglosado en el ticket.
- [ ] Mensaje del ticket.
- [ ] Impresión: ancho de papel (58/80 mm), impresora, impresión directa.
- [ ] Cajón de dinero: activar, elegir puerto y **probar que abre**.
- [ ] Turnos, fondo de caja, inventario mínimo.
- [ ] Descuentos: límite máximo y si el cajero puede aplicarlos solo.
- [ ] Catálogo importado desde CSV. **Verificar 5 productos al azar** contra la
      lista original: nombre, precio, costo y existencia.
- [ ] Usuarios del personal con su rol y su PIN. Cada quien teclea el suyo.

### Respaldo (no saltarse)

- [ ] Conectar la unidad externa. **Distinta de la USB de instalación.**
- [ ] Correr `3-instalar-respaldo-automatico.ps1`.
- [ ] Hora: una hora antes del cierre del negocio.
- [ ] Verificar que el respaldo de prueba dijo **LISTO**.
- [ ] Abrir la carpeta `PvControl-Respaldos\` y **enseñársela al dueño**.
- [ ] Configuración → Sistema y soporte: verificar que dice *Respaldado hoy* en
      verde.
- [ ] Explicar qué pasa si desconectan la USB, y enseñarles dónde aparece el
      aviso rojo.

### Prueba de fuego (antes de capacitar)

Con el dueño mirando:

- [ ] Abrir caja con fondo.
- [ ] Vender un producto en efectivo. Se imprime el ticket y abre el cajón.
- [ ] Vender con pago mixto (efectivo + tarjeta).
- [ ] Aplicar un descuento y ver que pide autorización si pasa del límite.
- [ ] Hacer una devolución.
- [ ] Corte X.
- [ ] Cerrar caja con arqueo.
- [ ] Revisar que el reporte del día cuadra con lo que acaban de hacer.
- [ ] Borrar esas ventas de prueba `[o dejarlas y explicar que son de prueba]`.

### Antes de irte

- [ ] Capacitación dada (parte 2) y firmada en el Anexo A.
- [ ] Contrato firmado por duplicado. Te llevas uno.
- [ ] Aviso de privacidad entregado y el corto pegado en el mostrador.
- [ ] Ficha del cliente llenada (parte 3).
- [ ] El dueño tiene guardado tu WhatsApp de soporte y sabe el horario.
- [ ] El dueño sabe generar el reporte de soporte. **Que lo haga él una vez,
      delante de ti.**
- [ ] Dejar la USB de instalación con el cliente, o llevártela — pero decidirlo
      y decirlo. Si se queda, avisar que **nunca** debe instalarse encima de una
      versión más nueva.

---

## 2. Guion de capacitación (30 minutos)

En este orden. No empieces por Configuración: al cajero no le sirve y se
aburre antes de llegar a lo suyo.

**Minuto 0-5 — Entrar y abrir caja.**
Cada quien entra con su PIN. Por qué cada quien con el suyo: los reportes y la
bitácora dicen quién hizo qué, y eso los protege a ellos también.

**Minuto 5-15 — Vender.** Lo que van a hacer 200 veces al día:

- Escanear, o buscar por nombre.
- Cambiar cantidad, quitar una línea.
- Cobrar en efectivo (que vean el cambio), con tarjeta y mixto.
- **Venta en espera**: cuando el cliente se regresa por algo, no se pierde el
  carrito.
- Reimprimir un ticket.

**Minuto 15-22 — Lo que sale mal.**

- Un producto no tiene código: cómo buscarlo.
- Se equivocaron de producto: quitarlo antes de cobrar.
- Ya cobraron mal: devolución.
- Descuento: hasta dónde puede el cajero y a quién le habla si necesita más.

**Minuto 22-30 — Cerrar (solo con el encargado).**

- Corte X para ver cómo va, sin cerrar.
- Cierre de caja: **el sistema no le dice cuánto debería haber hasta que él
  cuente y confirme.** Explicar que es a propósito, y que es una protección
  para el cajero honesto: nadie puede decir después que ajustó el conteo.
- Dónde ver el reporte del día.

**Lo que NO se enseña el primer día:** promociones, apartados, compras, cuentas
por pagar, auditoría. Se satura la cabeza y no se retiene nada. Diles que existe
y que se lo enseñas cuando ya dominen la venta — es además una buena excusa
para una segunda visita cobrada.

---

## 3. Ficha del cliente

> Copia este bloque por cada cliente. Cuando lleves ocho, ya no te vas a
> acordar de quién tiene qué versión ni a dónde respalda.

```
CLIENTE Nº: ____        Fecha de instalación: __/__/____

Negocio        : ______________________________________
Giro           : ______________________________________
Domicilio      : ______________________________________
Contacto       : ______________________  Tel: __________
WhatsApp       : ______________________
Quién manda    : ______________________________________
  (la persona que decide y a la que le hablas si hay bronca)

--- SISTEMA ---
Versión instalada : ____________  Esquema: v____
Fecha de última actualización: __/__/____
Usuarios creados  : ____   Productos cargados: ______
Sincronización    : [ ] No   [ ] Sí -> servidor: ____________

--- EQUIPO ---
PC (marca/modelo) : ______________________  Windows: ______
Impresora         : ______________________  Papel: 58 / 80 mm
Cajón             : [ ] No  [ ] Impresora  [ ] COM___
Lector de códigos : ______________________

--- RESPALDO ---
Unidad destino    : ____ (____________________________)
Hora programada   : ______   Hora de cierre del negocio: ______
Respaldo en nube  : [ ] No  [ ] Sí
Última verificación del respaldo: __/__/____

--- COMERCIAL ---
Contrato firmado  : [ ] Sí, fecha __/__/____
Implementación    : $__________  Pagada: [ ] Sí [ ] Parcial
Mensualidad       : $__________  Día de pago: ____
Último pago       : __/__/____
Aviso de privacidad entregado: [ ] Sí

--- NOTAS ---
(qué le pesa, qué pidió, qué le prometiste)
______________________________________________________
______________________________________________________
```

---

## 4. Registro de instalaciones

Una línea por cliente. Actualízala **cada vez que mandes una actualización**,
o dejará de servir en dos meses.

| Nº | Negocio | Instalado | Versión | Última act. | Respaldo a | Mensualidad | Estado |
|---|---|---|---|---|---|---|---|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |

**Estado:** activo / atrasado en pago / suspendido / dado de baja.

> **Por qué la columna "Versión" es la que más importa.** El día que alguien
> reporte un error, lo primero es saber qué versión tiene. Si no lo sabes, la
> incidencia empieza con media hora de ida y vuelta. Si además le mandas por
> error un instalador anterior al suyo, desde la v1.0.0 la app se defiende y no
> abre — pero el negocio se queda sin cobrar hasta que llegue el correcto.

### Al publicar una versión nueva

1. Actualizar `CHANGELOG.md` en español de negocio.
2. Correr `build_installer.ps1` y anotar el SHA256.
3. Mandar por WhatsApp a cada cliente: instalador + qué cambió + **"instálalo
   con la caja cerrada"**.
4. Marcar la fecha en la columna "Última act." **cuando confirmen que ya lo
   corrieron**, no cuando lo mandaste.
