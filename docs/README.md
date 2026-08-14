# docs/

Lo que hace falta para vender e instalar Pv Control en un negocio real. Nada de
esto es documentación técnica del código — eso está en el `README.md` de la
raíz y en los `README` de `lib/core/sync/`.

| Documento | Qué es | Cuándo se usa |
|---|---|---|
| [`distribucion.md`](distribucion.md) | Plan de distribución, licenciamiento y modelo comercial | Para decidir **qué construir y cuándo**. Es propuesta, no describe código existente. |
| [`EULA.txt`](EULA.txt) | Contrato de licencia de uso | Lo muestra el instalador (`LicenseFile` en el `.iss`). El cliente lo acepta al instalar. |
| [`contrato-servicio.md`](contrato-servicio.md) | Contrato de implementación y soporte | Se firma **antes** de instalar. Plantilla: llenar corchetes y Anexo B. |
| [`aviso-privacidad.md`](aviso-privacidad.md) | Reparto de responsabilidad sobre datos + modelo para el negocio | Se entrega en la implementación. |
| [`ficha-instalacion.md`](ficha-instalacion.md) | Checklist de instalación, guion de capacitación y control de clientes | El día de la instalación, y cada vez que publiques una versión. |
| [`licenciamiento.md`](licenciamiento.md) | Cómo se enciende el licenciamiento y cómo se emite una licencia | Cuando pases de ~5 clientes, o el día que alguien te pida el instalador "para su otra tienda". |

## Orden real de un cliente nuevo

1. Cotizar. Decir **por adelantado** las dos cosas que definen el producto:
   funciona sin internet (ventaja) y **no timbra CFDI** (limitación). La
   segunda te la van a exigir gratis después si no la dijiste antes.
2. Firmar `contrato-servicio.md` con el Anexo B lleno.
3. Preparar la USB (`windows\installer\preparar_usb.ps1`) y el catálogo en CSV.
4. Instalar siguiendo `ficha-instalacion.md`. El cliente acepta el EULA en el
   asistente.
5. Entregar el aviso de privacidad y capacitar.
6. Llenar la ficha del cliente y la línea del registro de instalaciones.

## Advertencia sobre lo legal

`EULA.txt`, `contrato-servicio.md` y `aviso-privacidad.md` son borradores de
trabajo, no dictámenes. **Que un abogado los revise una vez** antes de usarlos
con un cliente que te importe: esa revisión sirve para todos los clientes
siguientes y cuesta mucho menos que el primer pleito.
