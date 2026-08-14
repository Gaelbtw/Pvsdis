# Contrato de implementación y soporte — Pv Control

> **Cómo usar este documento.** Es una plantilla. Todo lo que va entre
> `[corchetes]` se llena antes de imprimir. Los montos van en el Anexo B para
> que puedas cambiar precios sin volver a redactar el contrato.
>
> **No soy abogado y esto no es asesoría legal.** Es un borrador de trabajo
> construido sobre prácticas comunes del mercado mexicano. Antes de firmarlo
> con un cliente que te importe, que lo revise un abogado — una sola revisión
> te sirve para todos los clientes siguientes, y cuesta mucho menos que el
> primer pleito.
>
> **Este contrato es distinto del EULA** (`docs/EULA.txt`). El EULA rige el uso
> del software y se acepta al instalar. Este rige el *servicio* que tú prestas.
> Los dos conviven: si se contradicen, gana el que sea más específico para el
> tema en disputa, y conviene decirlo (cláusula 14).

---

## CONTRATO DE PRESTACIÓN DE SERVICIOS DE IMPLEMENTACIÓN Y SOPORTE

Celebrado en `[ciudad]`, `[estado]`, el día `[__]` de `[______]` de `[____]`.

**EL PRESTADOR:** 2A2G Company, representada por `[nombre completo]`, con
domicilio en `[domicilio]`, RFC `[RFC]`, correo `[correo]`, teléfono
`[teléfono]`.

**EL CLIENTE:** `[razón social o nombre completo]`, con domicilio en
`[domicilio del negocio]`, RFC `[RFC]`, representado por `[nombre]`, correo
`[correo]`, teléfono `[teléfono]`.

Ambas partes se reconocen la capacidad legal para obligarse y acuerdan lo
siguiente.

---

### 1. Objeto

EL PRESTADOR implementa y da soporte al sistema de punto de venta **Pv
Control** en el establecimiento de EL CLIENTE, en los términos de este
contrato.

La licencia de uso del software se rige por el contrato de licencia (EULA) que
EL CLIENTE acepta al instalar. Este contrato cubre el **servicio**, no la
propiedad del software.

---

### 2. Implementación (pago único)

EL PRESTADOR entrega, por el monto del Anexo B:

1. Instalación de Pv Control en `[__]` equipo(s), con los requisitos del
   Anexo A.
2. Configuración de los datos del negocio: nombre, logo, domicilio, moneda,
   tasa de IVA y mensaje del ticket.
3. Configuración de impresora térmica y cajón de dinero **del equipo que EL
   CLIENTE ya tenga o adquiera**, siempre que sea compatible (Anexo A).
4. Carga inicial del catálogo de hasta `[___]` productos, a partir de la
   información que EL CLIENTE entregue en el formato acordado.
5. Creación de la cuenta de administrador y de hasta `[__]` usuarios con sus
   permisos.
6. Configuración del respaldo automático diario a una unidad externa que EL
   CLIENTE proporcione.
7. Capacitación presencial de hasta `[__]` horas para hasta `[__]` personas.

**Se considera entregada** cuando el sistema queda operando en el
establecimiento y EL CLIENTE firma el Anexo A.

---

### 3. Servicio mensual

Por el monto del Anexo B, EL PRESTADOR presta mensualmente:

1. **Actualizaciones** del sistema, con las correcciones y mejoras que se
   publiquen durante la vigencia.
2. **Soporte técnico** en los términos de la cláusula 5.
3. `[Opcional — borrar si no aplica]` **Respaldo en la nube** de la base de
   datos, con periodicidad `[diaria/semanal]` y retención de `[__]` días.

---

### 4. Lo que NO incluye (se cotiza por separado)

Para evitar malentendidos, estos trabajos no forman parte de los servicios
anteriores:

- Carga de productos adicionales a los del punto 2.4.
- Capacitación adicional, o repetición por cambio de personal.
- Visitas en sitio fuera de `[zona/municipio]`, o adicionales a las incluidas.
- Instalación en equipos adicionales.
- Recuperación de datos por causas ajenas al software: falla de disco, virus,
  borrado accidental, robo, daño por corriente eléctrica.
- Reinstalación por formateo, cambio de equipo o reinstalación de Windows.
- Configuración de hardware distinto al del Anexo A.
- Soporte sobre internet, red, antivirus, Windows o cualquier otro software
  que no sea Pv Control.
- Desarrollo de funciones nuevas a petición de EL CLIENTE.

---

### 5. Soporte: alcance, horario y tiempos de respuesta

**Canal:** `[WhatsApp al número ____]`. Es el canal oficial. Los mensajes
enviados por otros medios pueden no ser atendidos.

**Horario:** de `[lunes a viernes]` de `[9:00]` a `[18:00]` y `[sábados]` de
`[9:00]` a `[14:00]`, hora del centro de México. Fuera de ese horario no hay
obligación de respuesta.

**Tiempos de respuesta**, contados en horario hábil desde que EL CLIENTE
reporta por el canal oficial:

| Severidad | Qué es | Respuesta |
|---|---|---|
| **Crítica** | No se puede cobrar, o el sistema no abre | `[2]` horas |
| **Alta** | Un módulo no funciona pero sí se puede cobrar | `[8]` horas hábiles |
| **Normal** | Duda de uso, ajuste de configuración, reporte que no cuadra | `[24]` horas hábiles |
| **Mejora** | Petición de función nueva | Sin compromiso de fecha |

**Respuesta no es solución.** El compromiso es responder y empezar a atender
en ese plazo. El tiempo de solución depende de la causa y no se puede
garantizar de antemano.

**Obligación de EL CLIENTE:** al reportar, generar el reporte de soporte desde
*Configuración → Sistema y soporte → Generar reporte de soporte* y enviarlo por
el canal oficial. Ese archivo no contiene datos de sus clientes ni de sus
ventas. Sin él, los tiempos de la tabla no corren.

---

### 6. Respaldos: de quién es la responsabilidad

Esta cláusula es la que más pleitos evita. Léanla las dos partes.

**6.1** Toda la información de EL CLIENTE vive en un solo archivo dentro de su
computadora. Si ese equipo se daña, se pierde o se roba, **y no existe un
respaldo fuera del equipo, la información no se puede recuperar**.

**6.2** EL PRESTADOR deja configurado en la implementación el respaldo
automático diario a una unidad externa.

**6.3** **Es responsabilidad de EL CLIENTE** mantener conectada esa unidad y
verificar que las copias se estén generando. El sistema muestra un aviso
visible cuando el respaldo lleva más de 3 días sin ejecutarse; ignorarlo es
responsabilidad de EL CLIENTE.

**6.4** EL PRESTADOR solo asume responsabilidad sobre los respaldos si el
servicio de respaldo en la nube (cláusula 3.3) está contratado y vigente, y
únicamente sobre las copias efectivamente almacenadas en ese servicio.

**6.5** La recuperación de datos, cuando sea posible, se cotiza aparte
(cláusula 4).

---

### 7. Actualizaciones

**7.1** EL PRESTADOR entrega el instalador de cada versión nueva por el canal
oficial, junto con el listado de cambios y el código SHA256 del archivo.

**7.2** Instalar una actualización **conserva toda la información** de EL
CLIENTE. Aun así, se recomienda respaldar antes.

**7.3** EL CLIENTE se obliga a actualizar **con la caja cerrada y sin ventas en
curso**, nunca a media venta.

**7.4** EL CLIENTE no debe instalar una versión anterior a la que tiene. El
sistema lo impide para proteger su información, pero forzarlo por otros medios
puede dejar la base de datos inutilizable, y esa recuperación no está incluida.

**7.5** EL PRESTADOR no está obligado a mantener compatibilidad con versiones
de Windows que Microsoft haya dejado de soportar.

---

### 8. Contraprestación y forma de pago

**8.1** Montos: Anexo B.

**8.2** La implementación se paga `[100% al firmar / 50% al firmar y 50% al
entregar]`.

**8.3** La mensualidad se paga por adelantado, dentro de los primeros `[5]`
días de cada mes, por `[transferencia / efectivo / depósito]` a
`[datos de pago]`.

**8.4** Los montos `[incluyen / no incluyen]` IVA.

**8.5** EL PRESTADOR puede ajustar la mensualidad una vez al año, avisando por
escrito con `[30]` días de anticipación. Si EL CLIENTE no acepta, puede
terminar el contrato sin penalización antes de que el ajuste entre en vigor.

---

### 9. Falta de pago

**9.1** Con `[15]` días de atraso, EL PRESTADOR avisa por el canal oficial.

**9.2** Con `[30]` días de atraso se **suspende el soporte y las
actualizaciones**.

**9.3** **En ningún caso la falta de pago impide a EL CLIENTE vender, cobrar,
imprimir tickets o cerrar caja.** El sistema instalado sigue operando con las
funciones esenciales del negocio.

> Esto no es generosidad, es criterio: un POS que deja de cobrar destruye la
> reputación del proveedor en el pueblo mucho más rápido de lo que cuesta un
> cliente moroso.

**9.4** Con `[60]` días de atraso, EL PRESTADOR puede terminar el contrato. EL
CLIENTE conserva su información y puede solicitar apoyo para exportarla, que se
cobra conforme a la cláusula 4.

---

### 10. Vigencia y terminación

**10.1** Vigencia inicial de `[__]` meses a partir de la firma, con renovación
automática por periodos iguales salvo aviso en contrario.

**10.2** Cualquiera de las partes puede terminarlo avisando por escrito con
`[30]` días de anticipación. No hay reembolso de mensualidades ya pagadas ni
del pago de implementación.

**10.3** Al terminar, EL CLIENTE conserva el software instalado y **toda su
información**, que sigue siendo suya. Lo que cesa es el soporte, las
actualizaciones y, en su caso, el respaldo en la nube.

---

### 11. Datos personales

**11.1** El sistema permite a EL CLIENTE registrar datos personales de sus
propios clientes.

**11.2** **EL CLIENTE es el responsable** del tratamiento de esos datos frente
a sus titulares, en términos de la Ley Federal de Protección de Datos
Personales en Posesión de los Particulares. EL PRESTADOR no tiene acceso a esa
información, salvo lo previsto en 11.4.

**11.3** Es obligación de EL CLIENTE contar con su propio aviso de privacidad y
ponerlo a disposición de sus clientes. EL PRESTADOR le entrega un modelo (ver
`docs/aviso-privacidad.md`), **que no sustituye la revisión de su propio
abogado**.

**11.4** Si para resolver una incidencia EL CLIENTE entrega voluntariamente su
base de datos a EL PRESTADOR, éste la usará únicamente para diagnosticar y
resolver el problema reportado, y la eliminará al concluir la atención.

---

### 12. El sistema no es de facturación fiscal

**12.1** Pv Control **no emite, no timbra y no cancela CFDI**. No está
certificado ni autorizado por el SAT ni por ningún PAC.

**12.2** Los comprobantes que imprime son **tickets de venta** de control
interno. No tienen validez fiscal y no sustituyen a una factura.

**12.3** El cumplimiento fiscal de EL CLIENTE es responsabilidad exclusiva
suya. EL PRESTADOR no responde por multas, créditos fiscales, recargos ni
sanciones.

**12.4** EL CLIENTE declara conocer esto **antes** de contratar.

---

### 13. Confidencialidad

Cada parte se obliga a guardar confidencialidad sobre la información de la otra
a la que tenga acceso con motivo de este contrato, durante su vigencia y por
`[2]` años después de su terminación.

---

### 14. Límite de responsabilidad

**14.1** La responsabilidad total y acumulada de EL PRESTADOR por cualquier
reclamación derivada de este contrato no excederá el monto que EL CLIENTE le
haya pagado en los `[12]` meses anteriores al hecho que la origine.

**14.2** EL PRESTADOR no responde por daños indirectos o consecuenciales,
incluidos pérdida de ganancias, interrupción del negocio o pérdida de
información fuera de lo previsto en la cláusula 6.

**14.3** Estos límites no aplican en casos de dolo o mala fe.

---

### 15. Acuerdo completo y ley aplicable

**15.1** Este contrato, sus anexos y el EULA constituyen el acuerdo íntegro
entre las partes y sustituyen cualquier acuerdo verbal previo. En caso de
contradicción entre este contrato y el EULA, prevalece el que regule de forma
más específica el punto en disputa.

**15.2** Se rige por las leyes de los Estados Unidos Mexicanos. Para su
interpretación y cumplimiento, las partes se someten a los tribunales
competentes de `[ciudad/estado]`, renunciando a cualquier otro fuero.

**15.3** Si alguna cláusula resulta inválida, el resto permanece en vigor.

---

### Firmas

Leído el contrato y enteradas las partes de su contenido y alcance legal, lo
firman por duplicado.

<br>

| EL PRESTADOR | EL CLIENTE |
|---|---|
| <br><br>_______________________ | <br><br>_______________________ |
| `[nombre]` | `[nombre]` |
| 2A2G Company | `[razón social]` |

---

## Anexo A — Equipo e instalación

| Concepto | Dato |
|---|---|
| Fecha de instalación | `[__/__/____]` |
| Equipo (marca y modelo) | `[____]` |
| Sistema operativo | `[Windows __]` |
| Versión de Pv Control instalada | `[__.__.__]` |
| Impresora de tickets | `[marca, modelo, ancho 58/80 mm]` |
| Cajón de dinero | `[modelo / conexión: RJ11 a impresora o puerto COM__]` |
| Lector de código de barras | `[marca y modelo / no aplica]` |
| Unidad de respaldo | `[marca, capacidad, letra de unidad]` |
| Hora del respaldo automático | `[23:00]` |
| Usuarios creados | `[__]` |
| Productos cargados | `[____]` |
| Personas capacitadas | `[nombres]` |

**El hardware lo adquiere EL CLIENTE por su cuenta.** EL PRESTADOR lo
configura; no lo vende ni responde por su garantía.

Recibí el sistema instalado y funcionando, y la capacitación descrita:

<br>

_______________________
`[nombre y firma de EL CLIENTE]` — Fecha: `[__/__/____]`

---

## Anexo B — Contraprestación

| Concepto | Monto (MXN) |
|---|---|
| Implementación (pago único) | `$[______]` |
| Mensualidad | `$[______]` |
| Producto adicional al catálogo inicial (por cada 100) | `$[______]` |
| Hora de capacitación adicional | `$[______]` |
| Visita en sitio fuera de zona | `$[______]` |
| Reinstalación por formateo o cambio de equipo | `$[______]` |
| Recuperación de datos (por evento, sujeto a diagnóstico) | `$[______]` |
| Equipo adicional | `$[______]` |

Los montos `[incluyen / no incluyen]` IVA.

> **Para poner precios**, mira las anclas del mercado en
> `docs/distribucion.md` §3.1. Tu argumento de venta es que funciona sin
> internet; tu desventaja declarada es que no timbra CFDI. Di las dos por
> adelantado.
