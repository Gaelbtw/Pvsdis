# Aviso de privacidad — quién responde por qué

> **No soy abogado y esto no es asesoría legal.** Es un modelo de trabajo
> basado en la Ley Federal de Protección de Datos Personales en Posesión de los
> Particulares (LFPDPPP) y su Reglamento. Que lo revise un abogado antes de
> usarlo con clientes.

Este documento tiene tres partes:

1. **Cómo se reparte la responsabilidad** entre 2A2G Company y el negocio.
2. **El modelo de aviso** que el negocio entrega a *sus* clientes. Se lo das
   llenado en la implementación.
3. **El aviso corto** para pegar en el mostrador.

---

## Parte 1 — Cómo se reparte la responsabilidad

Esto es lo que hay que tener claro antes de vender, y lo que hay que explicarle
al cliente en la implementación.

### El negocio es el responsable, no tú

En Pv Control, quien decide capturar el nombre y el teléfono de un cliente
final es **el negocio**. Él define para qué los usa (fiar, apartar, avisar de
promociones) y por cuánto tiempo los guarda. En términos de la LFPDPPP, eso lo
hace **responsable del tratamiento**.

Tú no lo eres. Y hay una razón técnica concreta, no un tecnicismo de contrato:

- La base de datos vive **solo** en la computadora del negocio, en
  `%APPDATA%\2A2G Company\Pv Control\pos.db`.
- Pv Control no manda esa información a ningún lado. La sincronización está
  **apagada de fábrica** y solo se enciende si el negocio la configura contra
  su propio servidor.
- Tú no tienes acceso remoto a ese equipo.

**Sin acceso a los datos no hay tratamiento, y sin tratamiento no hay
responsabilidad.** Eso es lo que te protege, y es la razón por la que conviene
no pedirle al cliente su base "para revisar" salvo que de verdad haga falta.

### Las dos situaciones en que sí te toca algo

**1. El cliente te manda su base de datos para soporte.**
Ahí te vuelves **encargado** del tratamiento: la usas solo para lo que te
pidió y la borras al terminar. Está escrito en el EULA (cláusula 4.4) y en el
contrato de servicio (11.4). Cúmplelo de verdad: no la dejes en Descargas.

> Antes de pedir la base, prueba con el **reporte de soporte** (Configuración →
> Sistema y soporte). Trae versión, esquema, estado del respaldo, outbox y
> conteos, y **cero datos de clientes o ventas**. Resuelve la mayoría de las
> incidencias sin que nadie te mande información personal de nadie.

**2. Vendes respaldo en la nube.**
Ahí sí guardas la base del negocio en infraestructura que tú controlas. Eres
encargado, y necesitas un anexo que diga dónde se almacena, por cuánto tiempo,
quién puede acceder y qué pasa al terminar el contrato. **No vendas ese
servicio sin ese anexo.**

### El ticket

Si el negocio imprime el nombre del cliente en el ticket de un apartado o de
una venta a crédito, eso es un tratamiento suyo, no tuyo. Vale la pena
mencionárselo en la capacitación: los tickets con nombre que quedan tirados en
el mostrador son la fuga de datos más común y más tonta de un changarro.

---

## Parte 2 — Modelo de aviso de privacidad integral

> Se lo entregas al cliente llenado, como parte de la implementación. Es un
> entregable que casi ningún competidor da, cuesta poco y se nota.
>
> Todo lo que va entre `[corchetes]` lo llena el negocio.

---

### AVISO DE PRIVACIDAD

**`[Nombre o razón social del negocio]`**, con domicilio en
`[domicilio completo]`, es el responsable del tratamiento de sus datos
personales, conforme a la Ley Federal de Protección de Datos Personales en
Posesión de los Particulares.

#### ¿Qué datos recabamos?

Recabamos únicamente los datos que usted nos proporciona de forma directa al
registrarse como cliente:

- Nombre completo
- Teléfono
- `[Correo electrónico]`
- `[RFC y domicilio, solo si solicita comprobante]`

**No recabamos datos personales sensibles** (origen racial o étnico, estado de
salud, creencias religiosas, preferencia sexual, opiniones políticas ni
información financiera distinta al registro de sus compras y pagos en este
establecimiento).

#### ¿Para qué los usamos?

Finalidades **necesarias** para la relación con usted:

1. Registrar y dar seguimiento a sus compras, apartados y pagos.
2. Avisarle sobre el estado de un apartado o pedido, y sobre saldos pendientes.
3. Emitir los comprobantes de sus operaciones.
4. Atender aclaraciones, garantías y devoluciones.

Finalidades **no necesarias**, a las que puede oponerse sin afectar la relación
con nosotros:

5. `[Enviarle promociones y avisos de ofertas.]`

> Si no desea que usemos sus datos para las finalidades no necesarias, dígalo
> en el mostrador o comuníquelo a `[correo o teléfono]`. Su negativa no será
> motivo para negarle nuestros servicios.

#### ¿Con quién los compartimos?

**Con nadie.** No transferimos sus datos a terceros, salvo requerimiento de
autoridad competente.

Sus datos se almacenan en un sistema de punto de venta instalado en nuestro
propio equipo. El proveedor de ese sistema no tiene acceso a ellos.

#### ¿Cómo los protegemos?

El equipo donde se guarda la información está protegido con usuario y
contraseña individual, y el acceso está limitado al personal que lo necesita
para su trabajo. Conservamos copias de seguridad para evitar pérdidas.

Conservamos sus datos mientras exista relación comercial y hasta `[__]` año(s)
después de su última operación, salvo obligación legal de conservarlos por más
tiempo.

#### Sus derechos ARCO

Usted puede en cualquier momento **Acceder** a sus datos, solicitar su
**Rectificación** si son inexactos, su **Cancelación** cuando considere que no
son necesarios, u **Oponerse** a un uso específico. También puede revocar su
consentimiento.

Para ejercerlos, preséntese en nuestro domicilio o escriba a `[correo]`,
indicando su nombre, un medio para contactarle, la descripción clara de lo que
solicita y una identificación oficial. Responderemos en un plazo máximo de
**20 días hábiles**.

#### Cambios a este aviso

Cualquier modificación se dará a conocer `[en este mismo lugar visible del
establecimiento / en nuestra página ______]`.

#### Consentimiento

Al proporcionarnos sus datos personales, usted acepta el tratamiento descrito.

**Fecha de última actualización:** `[__/__/____]`

---

## Parte 3 — Aviso corto para el mostrador

> Media cuartilla, para imprimir y pegar junto a la caja. La ley permite el
> aviso simplificado siempre que remita al integral.

---

### AVISO DE PRIVACIDAD SIMPLIFICADO

**`[Nombre del negocio]`**, con domicilio en `[domicilio]`, es el responsable
del tratamiento de sus datos personales.

Los datos que nos proporciona (nombre y teléfono) los usamos únicamente para
registrar sus compras, apartados y pagos, avisarle de su estado y atender
aclaraciones. `[Y para hacerle llegar promociones, a lo que puede oponerse en
cualquier momento.]`

**No los compartimos con nadie.** Se guardan en nuestro propio equipo, no en
internet.

Puede acceder, rectificar, cancelar u oponerse al uso de sus datos
solicitándolo en caja o al correo `[correo]`.

Puede consultar el aviso de privacidad completo `[solicitándolo en caja /
en ______]`.

---

## Lista de verificación para la implementación

Al instalar en un cliente nuevo:

- [ ] Explicarle que **él** es el responsable de los datos de sus clientes, no
      tú, y por qué (los datos nunca salen de su computadora).
- [ ] Entregarle la Parte 2 llena con sus datos.
- [ ] Entregarle la Parte 3 impresa para el mostrador.
- [ ] Explicarle lo del nombre en los tickets de apartado.
- [ ] Mostrarle el reporte de soporte y decirle explícitamente que **no lleva
      datos de sus clientes**, para que no dude en mandarlo cuando algo falle.
- [ ] Anotarlo en la ficha del cliente (`docs/ficha-instalacion.md`).
