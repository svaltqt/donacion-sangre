# Resultados de pruebas

## Resumen por caso

Ejecución del 2026-10-03 por API, sobre la carga de `scripts/cargar-datos.sh`:
- P-01, P-02, P-07, P-10, P-11, P-12, P-14: `scripts/ejecutar-api.sh` → `evidencias/verificaciones.log`.
- P-06, P-08, P-09, P-18: `scripts/ejecutar-api-citas.sh` → `evidencias/verificaciones-citas.log`.
- P-05, P-13, P-15, P-16, P-17, OBS-02, OBS-03 y la comprobación de CF-11: `scripts/ejecutar-api-acceso.sh` (los reportes con `scripts/reportes-excel.cjs`, Node) → `evidencias/verificaciones-acceso.log`.

| Caso | Estado | Evidencia | Pendiente (parte de UI, no ejecutable por API) |
|---|---|---|---|
| P-01 Registro de donante | Aprobado (API) | `evidencias/P-01/` | Formulario; mensajes en pantalla (en SD-02d el frontend envía latitud/longitud en null) |
| P-02 Inicio y cierre de sesión del donante | Aprobado (API) | `evidencias/P-02/` | Redirección a `/home-donante`, cierre de sesión y redirección a `/login` |
| P-05 Mapa de bancos cercanos | Aprobado (API) | `evidencias/P-05/` | Permiso de ubicación, centro del mapa, marcadores y círculo del radio |
| P-06 Triaje y programación | Aprobado (API); triaje con IA **Bloqueado** | `evidencias/P-06/` | Triaje con DonaBot (`gemini.api.key` ficticia en local), paso de agenda y mensajes en pantalla |
| P-07 Administrador de banco | Aprobado (API) | `evidencias/P-07/` | Redirección a `/home-banco` y opciones de menú |
| P-08 Dashboard del banco | Aprobado (API) | `evidencias/P-08/` | Presentación de `/home-banco`, citas pendientes y alerta visual |
| P-09 Completar o rechazar una donación | Aprobado (API) | `evidencias/P-09/` | Modal de finalización de HomeBanco (campos, mensajes) |
| P-10 Inventario del banco | Aprobado (API) | `evidencias/P-10/` | Pantalla `/inventario` e indicador visual de bajo stock |
| P-11 Solicitudes de urgencia | Aprobado (API) | `evidencias/P-11/` | Pantalla `/solicitudes`; vista del donante en `/urgencias` |
| P-12 Superadministrador | Aprobado (API) | `evidencias/P-12/` | Redirección a `/super-admin`, acceso a `/super-admin/reportes` |
| P-13 Dashboard global | Aprobado (API) con CF-14 | `evidencias/P-13/` | Presentación del panel y accesos rápidos |
| P-14 Gestión de bancos | Aprobado (API) | `evidencias/P-14/` | Pantalla `/super-admin/bancos` (tabla, precarga del formulario) |
| P-15 Creación de administrador de banco | Aprobado (API) | `evidencias/P-15/` | Formulario del banco: creación del administrador y desplegable |
| P-16 Reporte de donaciones y Excel | Aprobado (API); Excel verificado fuera del navegador; CF-13 | `evidencias/P-16/` | Tabla e indicadores en pantalla, selector de fechas y clic de descarga |
| P-17 Reporte de inventario y Excel | Aprobado (API); Excel verificado fuera del navegador; CF-13 | `evidencias/P-17/` | Resaltado visual de críticos, tabla y clic de descarga |
| P-18 Flujo end-to-end | Aprobado (API) con CF-12; triaje con IA **Bloqueado** | `evidencias/P-18/` | Triaje (IA), pantallas de los tres roles y reporte/Excel |
| OBS-02 Historial ajeno (PRD §7) | **Fallido** → BUG-02 | `evidencias/OBS-02/` | — |
| OBS-03 Admin de otro banco (PRD §7) | **Fallido** → BUG-03 | `evidencias/OBS-03/` | — |
| P-19 Navegación por rol | En ejecución (UI manual) | `evidencias/P-19/` | Intento cruzado del donante a `/home-banco`; menús de cada rol |

Estados: Aprobado · Fallido · Bloqueado. "Aprobado (API)" significa que todos los pasos verificables por API cumplen el resultado esperado de `set-de-datos.csv`; el caso solo se cerrará del todo al ejecutar la parte de UI. Ningún caso P-XX queda Fallido; los fallos de la tercera tanda son las pruebas de propiedad OBS-02 y OBS-03 (BUG-02 y BUG-03). Primera tanda (7 casos): 75 verificaciones aprobadas y 3 no ejecutables por API. Segunda tanda (P-06, P-08, P-09, P-18): 45 aprobadas, 9 observaciones (consultas funcionales) y 5 bloqueadas (triaje con IA y partes de UI). Tercera tanda (P-05, P-13, P-15, P-16, P-17, OBS-02, OBS-03, CF-11): 71 verificaciones aprobadas, 12 falladas (las de BUG-02 y BUG-03), 7 observaciones y 5 bloqueadas (partes de UI). No se dispuso de las HU (HU-D01, HU-B04, etc.), solo `set-de-datos.csv` y el PRD.

### P-19 — Verificación manual de acceso cruzado (2026-10-03)
- **Admin de banco → `/super-admin`:** la aplicación no muestra la pantalla del super admin y redirige a `/login`, aunque la sesión sigue activa (ver CF-07). El acceso queda bloqueado: **cumple** el control de rutas por rol (PRD §6).
- **Donante (Ana) → `/home-banco`:** pendiente.

### Reportes P-16 y P-17: cómo se verificó el Excel
El archivo lo genera el navegador (`XLSX.writeFile` en `Reportes.jsx`), así que no hay endpoint que lo entregue. `scripts/reportes-excel.cjs` extrae el código de `Reportes.jsx` (`generar`, `descargarExcel`, `kpis`), lo ejecuta tal cual con la misma librería `xlsx` y las mismas rutas de `api.js`, abre los archivos resultantes y compara con los datos de la API (`GET /api/donaciones`, camino distinto). Quedan en `evidencias/P-16/archivos/` y `evidencias/P-17/archivos/`, con su volcado en `contenido-excel.csv`.
- **Donaciones:** hoja "Donaciones", 11 columnas (ID, Fecha donación, Donante, Tipo sangre, Banco, Cantidad (ml), Hemoglobina (g/dL), Presión arterial, Estado, Observaciones, ID Solicitud). Cada fila coincide con la API; incluye la donación de SD-10 con 13.5 g/dL y 120/80.
- **Inventario:** hoja "Inventario", 8 columnas (Banco, Ciudad, Tipo sangre, Unidades disponibles, Unidades mínimas, Diferencia, Bajo stock, Última actualización). Los registros en bajo stock van primero; AB- con disponibles = mínimo (diferencia 0) figura "NO".
- Rango sin registros (marzo de 2020): no hay datos y no se genera archivo (ver CF-13).
- **No cubierto:** que el navegador descargue y abra el archivo, y la tabla e indicadores en pantalla.

### Datos que quedaron en la BD tras la ejecución (afectan a casos posteriores)
- **Ana Prueba** (donante, id 3) creada en P-01; no se debe volver a crear en P-01 sin reiniciar la BD.
- **Inventario AB-** del banco de Medellín: 5 disponibles, mínimo 5 (SD-11, ya ajustado).
- **Dos solicitudes** O- creadas en P-11: una COMPLETADA y otra CANCELADA. No aparecen como activas, pero cuentan en listados y reportes por estado (P-13, P-16).
- **Donantes Dona Ochentaynueve (id 4), Dona Noventa (id 5) y Omar Negativo (id 6)**, creados en P-06/P-18. Sus donaciones de preparación (COMPLETADA hace 89 y 90 días) las sembró el admin de banco por API.
- **Donaciones de la segunda tanda:** Dona90 COMPLETADA (hoy, solicitud A+ id 2), Dona89 RECHAZADA (fecha de mañana), Omar COMPLETADA (hoy, solicitud O- id 1). Omar y Dona90 no podrán donar otra vez en 90 días.
- **Inventario O+** del banco de Medellín: 3 → 4 (sigue en bajo stock). **Solicitudes:** A+ (id 2) y O- (id 1) tienen 1 unidad recibida; siguen ACTIVAS. Esto cambia lo que mostrarán P-04, P-13 y P-16.
- **Administradores:** `admin.envigado` (id 7) administra ahora Envigado y `admin.bello` (id 8) administra Bello; `admin.banco` queda como administrador de Medellín y Bogotá. Los creó la tercera tanda (OBS-03 y P-15).
- **Donantes Prueba Doscientos (id 9) y Prueba DoscientosB (id 10)** con una donación COMPLETADA de 200 ml cada uno. La solicitud B+ (id 3) tiene 2 unidades recibidas y el inventario O+ sigue en 4. La primera ejecución del script de la tercera tanda falló por un error propio (identificadores de banco vacíos) y dejó creados a `admin.bello` y al donante id 9; por eso la creación de `admin.bello` se conserva en `evidencias/P-15/00-creacion-admin-bello-1a-ejecucion.txt` y CF-11 se repitió con el donante id 10.
- Lo creado en Envigado durante OBS-03 (inventario B- y A-, solicitudes) se eliminó con el super admin al terminar: Envigado queda sin inventario ni solicitudes.
- **Banco Prueba Bello** (id 4) creado en P-14, con teléfono editado a 6040000099 y **reactivado** al final para P-15. Está dentro de 50 km de Medellín: puede aparecer en el mapa de P-05 junto a Envigado.

## Bugs

### BUG-01 — El registro público acepta `rolId` y permite crearse como SUPER_ADMIN

- **Severidad (propuesta):** Crítica
- **Hallado en:** preparación de datos (SD-13); afecta al caso P-01 (registro) y a todos los controles de rol (P-12, P-19)
- **Pasos:**
  1. Sin autenticación, enviar `POST /api/v1/auth/registro` con un cuerpo de donante válido y el campo extra `"rolId": 3` (id del rol `SUPER_ADMIN`).
  2. Usar el token devuelto en cualquier endpoint restringido al super admin (por ejemplo `POST /api/bancos`).
- **Esperado:** el registro público solo crea cuentas `DONANTE`; ignora o rechaza `rolId`. Los roles administrativos solo los asigna un `SUPER_ADMIN` autenticado (PRD §4, §5.2).
- **Observado (confirmado el 2026-10-03):** `POST /api/v1/auth/registro` sin `Authorization` y con `"rolId":3` respondió HTTP 201 con `"rol":"SUPER_ADMIN"` y un JWT. Con ese token se crearon bancos, inventario y solicitudes. Cualquier persona puede obtener control total (bancos, usuarios, donaciones, reportes).
- **Causa en el código (solo lectura, sin modificar):** `RegistroDTO.rolId` ("opcional, default DONANTE") se usa en `AuthServiceImpl.registrar`, que hace `rolRepository.findById(dto.getRolId())` sin comprobar quién llama; `SecurityConfig` marca `/api/v1/auth/**` como `permitAll`.
- **Evidencia:** `docs/pruebas/evidencias/BUG-01/peticion-respuesta.txt`. La generó `docs/pruebas/scripts/cargar-datos.sh` al registrar al super admin de SD-13 (petición sin autenticación y respuesta HTTP 201; JWT y contraseña omitidos).
- **Dependencia:** el script de carga de datos usa este defecto para crear los usuarios `ADMIN_BANCO` y `SUPER_ADMIN`. Si se corrige, hay que sembrarlos por SQL con hashes BCrypt.

### BUG-02 — Un donante puede leer el historial y los datos clínicos de otro donante

- **Severidad (propuesta):** Alta
- **Hallado en:** OBS-02 (PRD §7: acceso restringido por propiedad del registro)
- **Pasos:**
  1. Iniciar sesión como un donante (Ana, id 3).
  2. `GET /api/donaciones/usuario/6/historial` con su token, siendo 6 el id de otro donante (Omar).
  3. Repetir con `GET /api/donaciones/usuario/6` y con `GET /api/donaciones/{id}` de una donación de Omar (los ids son correlativos).
  4. Control: Dona90 pide el historial de Ana.
- **Esperado:** 403. Solo el propio donante, el administrador del banco implicado o un `SUPER_ADMIN` deberían ver esas donaciones (PRD §7).
- **Observado:** las tres consultas responden HTTP 200 con la donación completa de Omar (hemoglobina 14.0, presión 118/78, banco, solicitud, estado); el historial de Ana también lo lee Dona90. El control de rol sí funciona en otro punto: un donante recibe 403 en `GET /api/donaciones/banco/{id}`.
- **Causa en el código (solo lectura):** en `DonacionController`, `/{id}`, `/usuario/{usuarioId}` y `/usuario/{usuarioId}/historial` solo llevan `@PreAuthorize("isAuthenticated()")`; no se compara `usuarioId` con el usuario del token.
- **Evidencia:** `docs/pruebas/evidencias/OBS-02/` (pasos 02 a 05; el 01 es el control de lectura propia).
- **Agravante:** con BUG-01 el registro es libre, por lo que cualquiera puede crear una cuenta y recorrer los ids de donantes y donaciones.

### BUG-03 — Un administrador de banco puede gestionar el inventario, las solicitudes y las donaciones de otro banco

- **Severidad (propuesta):** Alta
- **Hallado en:** OBS-03 (PRD §7: acceso restringido por propiedad del registro)
- **Preparación:** la carga de datos asignó todos los bancos a `admin.banco`, lo que habría invalidado la prueba; se creó `admin.envigado` y se le asignó Envigado (pasos 01 a 05). Controles positivos: `admin.envigado` crea inventario y solicitudes en Envigado (pasos 06 y 07).
- **Pasos:** iniciar sesión como `admin.banco` (banco de Medellín, id 1) y operar sobre Envigado (id 2):
  1. `POST /api/inventario` (tipo A-, `bancoId`: 2).
  2. `PATCH /api/inventario/ajustar?bancoId=2&tipoSangre=B-&cantidad=1` y `PUT /api/inventario/{id}` (poner 0 unidades).
  3. `POST /api/solicitudes` con `bancoId`: 2; `PATCH /api/solicitudes/{id}/estado?estado=CANCELADA` y `PUT /api/solicitudes/{id}` sobre una solicitud de Envigado.
  4. `GET /api/donaciones/banco/2` y `GET /api/donaciones/banco/2/rango?...`.
- **Esperado:** 403 en todos los casos (PRD §7).
- **Observado:** las 8 acciones se ejecutaron (HTTP 201 o 200): se creó y alteró stock de Envigado, se creó, canceló y editó una solicitud suya y se leyeron sus donaciones, que incluyen datos clínicos de donantes.
- **Causa en el código (solo lectura):** los controllers solo exigen `hasAnyRole('SUPER_ADMIN','ADMIN_BANCO')` y los servicios no comparan el banco con el administrador (revisado en `InventarioServiceImpl.crear` y `ajustarUnidades`); el resto lo confirma el comportamiento observado.
- **Evidencia:** `docs/pruebas/evidencias/OBS-03/` (pasos 08 a 15).

## Consultas funcionales

Comportamientos que el PRD no especifica. No son bugs; requieren decisión del equipo.

| ID | Caso | Observado | Pregunta |
|---|---|---|---|
| CF-01 | P-02, P-07, P-12 | Un login fallido (clave incorrecta o correo inexistente) responde **HTTP 400** con el mensaje genérico "Credenciales inválidas", no 401. | ¿Debe ser 401? El mensaje genérico evita revelar si el correo existe. |
| CF-02 | P-02 | Una petición protegida sin token responde **HTTP 403**, no 401. | ¿Se espera 401 para "no autenticado"? |
| CF-03 | P-01, P-06, P-10, P-14 | Los duplicados se rechazan con códigos distintos: correo y documento repetidos en el registro dan **400**; inventario duplicado, NIT repetido y la regla de 90 días entre donaciones dan **409**. | ¿Se unifica el código para duplicados? |
| CF-04 | P-01 | Los errores de validación (peso 49 kg, falta de latitud/longitud) llegan como `{"error":"Error de validación","errores":{campo:mensaje}}`, mientras que los de negocio llegan como `{"mensaje":...}`. | El frontend debe leer ambos formatos; verificarlo en P-20. |
| CF-05 | P-02 | No existe endpoint de cierre de sesión: es solo del cliente (borra `localStorage`) y el JWT sigue siendo válido hasta que expira. | ¿Se requiere invalidación del token en el servidor? |
| CF-06 | P-14 | Al desactivar un banco, la consulta pública (`/activos` y `/radio`) deja de mostrarlo. No se comprobó si `GET /api/bancos/{id}` sigue devolviéndolo a un donante. | Definir si un banco desactivado debe seguir siendo consultable por id. |
| CF-07 | P-19 | Con sesión de **ADMIN_BANCO**, al abrir manualmente la URL `/super-admin` la aplicación no muestra la pantalla y **redirige a `/login`**, pero **la sesión sigue activa**: al escribir después `/home-banco` se entra directo sin volver a autenticarse. El usuario ve la pantalla de inicio de sesión estando autenticado, lo que sugiere que su sesión terminó cuando no es así. El acceso a la ruta ajena queda bloqueado (correcto). Severidad propuesta: Baja (UI). | Ante una ruta no permitida para el rol, ¿se debe redirigir al panel propio del rol (o mostrar "acceso denegado") en lugar de enviar a `/login` con la sesión viva? |
| CF-08 | P-06, P-18 | **Alta relevancia.** El botón **"SALTAR →"** de DonaBot (`UrgenciaCard.jsx`) permite agendar sin triaje: pasa directo al paso de fecha y de ahí a `POST /api/donaciones`. Está siempre visible durante el triaje, **incluso después de un veredicto "NO APTO"**, y si DonaBot falla el propio mensaje de error indica usarlo (en local ocurre siempre, porque la clave de Gemini es ficticia). Además el backend no recibe ni exige ningún dato de triaje: el registro por API creó la cita PENDIENTE sin él (`evidencias/P-06/`, pasos de agendar). | ¿El triaje debe ser obligatorio y quedar registrado? Hoy es solo una conversación en el navegador, sin efecto en el servidor. Sin las HU (HU-D06) no se puede decir si es un defecto. |
| CF-09 | P-06 | La regla de 90 días se aplica con criterios distintos: el backend mide el intervalo hasta la **fecha elegida** y aceptó agendar a mañana a una donante con 89 días (cita PENDIENTE); la UI compara contra **hoy** y la bloquearía (paso NO_PUEDE); el matching también usa hoy. | ¿Se puede agendar a futuro cuando el intervalo se cumple en esa fecha? |
| CF-10 | P-08 | El PRD no define las métricas del dashboard. Con los datos actuales la API da: 18 unidades totales, 1 tipo en bajo stock (O+), 2 citas pendientes (donaciones PENDIENTE) y 4 solicitudes activas. Según el código, "donaciones del mes" cuenta las COMPLETADA con fecha del mes en curso. | Definir las métricas esperadas. |
| CF-11 | P-09 | Al completar una donación, el inventario suma al **tipo de la donación** (O+ 3 → 4) y la solicitud suma **1 unidad recibida** (A+ id 2: 0 → 1), aunque el tipo del donante (O+) no coincida con el de la solicitud (A+). Leyendo el código (no probado), el inventario suma `cantidadMl / 450` con división entera (200 ml no suma nada) mientras la solicitud suma siempre 1. **Confirmado en la tercera tanda con una donación de 200 ml:** el inventario O+ no cambió (4 → 4) y la solicitud B+ pasó de 1 a 2 unidades recibidas (`evidencias/CF-11/`). | ¿Cómo debe contabilizarse una donación compatible pero de otro tipo, o de menos de 450 ml? |
| CF-12 | P-18 | **Alta relevancia.** SD-19 no define inventario O- y el banco de Medellín no tiene fila O-. Al completar la donación de Omar (O-) el estado, el reporte y la solicitud se actualizan, pero **no se crea ni se suma stock y no hay aviso** (`evidencias/P-18/`, inventario antes y después). El efecto en inventario pedido por P-18 no se pudo verificar. | ¿Debe crearse la fila al completar, o rechazarse la operación? Para verificar P-18 completo, añadir O- al set de datos de SD-19. |
| CF-13 | P-16, P-17 | Con un rango sin registros no se genera ningún archivo: `descargarExcel` termina si no hay datos y la pantalla muestra (según el código) "No hay datos que coincidan con los filtros aplicados." | ¿Debe descargarse un archivo solo con cabeceras? |
| CF-14 | P-13 | El PRD no define las métricas del panel global. Con los datos actuales: 4 bancos, 4 activos, 4 solicitudes activas y 1 en bajo stock. La tarjeta "tipos bajo stock" cuenta **filas banco × tipo** (`data.length` de `/api/inventario/bajo-stock`), no tipos distintos: O+ bajo en dos bancos contaría 2. | ¿Debe contar tipos distintos o combinaciones banco-tipo? |
| CF-15 | P-05 | Un radio negativo (`radioKm=-5`) responde HTTP 200 con lista vacía; no hay validación en el servidor (la UI limita el control deslizante). | Definir límites del radio como en las solicitudes (1 a 500 km). |

## Observaciones

### Observación 1 — El triaje y las citas existen aunque el PRD §9 los declara fuera de alcance
El PRD §9 deja fuera "agendamiento de citas de donación" y "cuestionario de elegibilidad completo", pero el frontend los implementa:
- **Triaje (DonaBot, `UrgenciaCard.jsx`):** cuatro preguntas generadas por un modelo de lenguaje a través de `POST /api/claude/chat` (proxy a Gemini). Solo funciona con una clave real; en local es ficticia, por eso esa parte queda **bloqueada**.
- **Agendar:** `GET /api/donaciones/usuario/{id}/historial` (comprobación de 90 días en el cliente) y `POST /api/donaciones` (crea la cita; estado inicial PENDIENTE).
- **Citas en HomeBanco:** `GET /api/bancos/activos` (para localizar su banco), `GET /api/inventario/banco/{id}`, `GET /api/solicitudes/banco/{id}` y `GET /api/donaciones/banco/{id}` (las PENDIENTE se muestran como "citas pendientes"); rechazar con `PATCH /api/donaciones/{id}/estado?estado=RECHAZADA`; completar con `PUT /api/donaciones/{id}` más `PATCH .../estado?estado=COMPLETADA`.
- En el backend no existe una entidad "cita": una cita es una donación PENDIENTE.

Consecuencia: P-06, P-08, P-09 y P-18 sí son ejecutables (por API en lo que no es interfaz). La decisión de alcance (¿actualizar el PRD o retirar la función?) es del equipo.

## Observaciones de tandas anteriores ya ejecutadas
- **OBS-02** (un donante lee el historial de otro): confirmada, ver BUG-02.
- **OBS-03** (un administrador gestiona otro banco): confirmada, ver BUG-03.
