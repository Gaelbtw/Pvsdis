# Requisitos de sistema — Pv Control

Para cotizar, para el Anexo A del contrato y para no descubrir en la
instalación que el equipo no sirve.

---

## Mínimos

| | |
|---|---|
| **Sistema** | Windows 10 de 64 bits, versión 1809 o superior |
| **Arquitectura** | x64 únicamente |
| **Procesador** | Doble núcleo |
| **Memoria** | 4 GB de RAM |
| **Disco** | 500 MB libres |
| **Pantalla** | 1024 × 768 |
| **Componente** | Visual C++ Redistributable 2015-2022 x64 |
| **Internet** | No hace falta |

## Recomendados

| | |
|---|---|
| **Sistema** | Windows 11 o Windows 10 22H2 |
| **Memoria** | 8 GB de RAM |
| **Disco** | SSD, 2 GB libres |
| **Pantalla** | 1366 × 768 o más |

---

## De dónde salen estos números

**Windows 10 64 bits no es negociable.** Flutter no soporta Windows 8.1 ni 7, y
`windows/runner/runner.exe.manifest` declara el GUID de compatibilidad de
Windows 10/11. El instalador además tiene `ArchitecturesAllowed=x64compatible`:
en un Windows de 32 bits no arranca siquiera el asistente.

**4 GB de RAM.** `_onOpen` reserva 20 MB de caché de páginas de SQLite
(`PRAGMA cache_size = -20000`) porque el default de 2 MB obliga a releer del
disco constantemente. El comentario del propio código dice que para soportar
equipos de 2 GB habría que bajarlo a `-8000`; mientras no se haga, 4 GB es el
piso real.

**1024 × 768.** La ventana declara `minimumSize: Size(940, 620)` — por debajo de
eso no se puede encoger. Con 768 px de alto menos la barra de tareas quedan unos
728, así que cabe pero justo. El tamaño de arranque es 1280 × 800.

**500 MB.** El programa compilado pesa 39 MB. El resto es margen para la base de
datos, los respaldos locales previos a cada migración y las exportaciones. Un
negocio con dos años de operación difícilmente pasa de 300 MB de datos.

**SSD recomendado, no obligatorio.** El código está escrito para disco mecánico
o eMMC lenta —está dicho así en los comentarios de `_onOpen`— y funciona. El SSD
se nota al abrir la app y en reportes de rango largo.

---

## Hardware de punto de venta

Nada de esto es obligatorio para que el sistema funcione, pero es lo que hace
falta para operar de verdad. **Lo compra el cliente**; nosotros lo configuramos.

| Equipo | Requisito |
|---|---|
| **Impresora de tickets** | Térmica de 58 o 80 mm. Debe imprimir la página de prueba desde Windows antes de instalar: si no imprime desde ahí, tampoco lo hará desde Pv Control. |
| **Cajón de dinero** | Conectado al puerto RJ11 de la impresora, o por puerto serie COM1-COM8. |
| **Lector de códigos** | Cualquiera que funcione como teclado (HID). Probarlo tecleando en el Bloc de notas. |
| **Unidad de respaldo** | Memoria USB o disco externo que se quede conectado. **Distinta de la USB de instalación.** |

---

## Lo que NO hace falta

- Internet. El sistema funciona completo sin conexión; la sincronización es
  opcional y viene apagada.
- Tarjeta de video dedicada.
- .NET, Java o cualquier otro entorno.
- Cuenta de usuario, registro ni activación en línea.
- Servidor, red local ni equipo adicional.

---

## Cuánto aguanta

Números orientativos para saber cuándo un cliente se sale del rango cómodo.

| | Sin problema | Se empieza a notar |
|---|---|---|
| Productos en catálogo | hasta ~5,000 | más de 20,000 |
| Ventas al día | cualquier volumen realista | — |
| Años de historia | 2-3 años | — |
| Usuarios simultáneos | 1 por equipo | — |

**Catálogo grande.** Al abrir Ventas se carga el catálogo completo
(`ProductoController.obtenerConStock`, dos `LEFT JOIN`, sin `LIMIT`). Con 500
productos es instantáneo; una refaccionaria con 20,000 lo va a sentir al entrar
a la pantalla. La búsqueda por código de barras y por SKU sí usa índice único,
así que escanear es rápido sin importar el tamaño.

**Historia larga.** `Auditorias` se recorta sola a 24 meses
(`auditoria_meses_retencion` en configuración). Sin esa purga el archivo crecía
sin límite y el respaldo diario a la USB tardaba más cada mes.

**Un solo equipo por caja.** El sistema no está pensado para que dos
computadoras compartan el mismo archivo de base de datos por red. Dos cajas son
dos instalaciones, y se consolidan con la sincronización opcional.
