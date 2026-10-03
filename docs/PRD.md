# PRD — Plataforma de Donación de Sangre

| | |
|---|---|
| **Producto** | Donación de Sangre (API Banco de Sangre + Web) |
| **Versión** | 1.0 (documenta el estado actual del producto) |
| **Fecha** | 2026-10-03 |
| **Equipo** | Carlos Díaz (Backend) · Diego Manco (Frontend) |

---

## 1. Resumen

Sistema web que conecta **donantes** con **bancos de sangre**. Los bancos publican solicitudes urgentes por tipo de sangre; el sistema identifica automáticamente a los donantes compatibles y cercanos y les muestra las urgencias activas. Un **super administrador** gestiona los bancos y consulta reportes consolidados.

## 2. Problema

- Los bancos de sangre dependen de llamados manuales y difusión en redes para cubrir faltantes, lo que es lento e impreciso.
- Los donantes dispuestos no saben dónde ni cuándo su tipo de sangre es necesario.
- Los bancos no tienen una vista unificada del inventario por tipo de sangre ni del historial de donaciones.
- No existe control sistemático de la elegibilidad del donante (intervalo mínimo entre donaciones).

## 3. Objetivos

1. Reducir el tiempo entre la publicación de una necesidad y la llegada de donantes.
2. Dirigir cada solicitud a donantes **compatibles** (tabla OMS) y **cercanos** (radio en km).
3. Dar a cada banco control de su inventario, con alertas de bajo stock.
4. Garantizar el cumplimiento de reglas de seguridad del donante (peso, intervalo de 90 días).
5. Dar al super admin trazabilidad y reportes exportables.

### Métricas de éxito (propuestas)

| Métrica | Meta inicial |
|---|---|
| Donantes registrados activos | Definir con primeros bancos piloto |
| % de solicitudes completadas antes de `fechaLimite` | ≥ 70 % |
| Tiempo medio hasta la primera donación asociada a una solicitud | < 48 h (urgencia ALTA) |
| Bancos con inventario actualizado en los últimos 7 días | ≥ 80 % |

## 4. Usuarios y roles

| Rol | Descripción | Capacidades principales |
|---|---|---|
| **DONANTE** | Persona que se registra para donar | Registro/login, ver urgencias activas y mapa de bancos, registrar y consultar su historial de donaciones |
| **ADMIN_BANCO** | Administrador de un banco de sangre | Gestionar inventario, crear/editar solicitudes, buscar donantes compatibles, gestionar donaciones de su banco |
| **SUPER_ADMIN** | Administrador de la plataforma | CRUD de bancos, crear admins de banco, ver usuarios, reportes con exportación a Excel, completar donaciones, acceso total |

## 5. Alcance funcional

### 5.1 Autenticación y registro
- Registro de donante con: documento, nombre, apellido, correo, celular, contraseña, tipo de sangre, fecha de nacimiento, género, peso, ubicación (latitud/longitud, ciudad, departamento).
- Login con JWT; autorización por rol en backend (`@PreAuthorize`) y rutas protegidas en frontend.
- **Reglas:** correo y documento únicos; peso mínimo 50 kg; todos los datos médicos y de ubicación son obligatorios.

### 5.2 Gestión de bancos (SUPER_ADMIN)
- Alta, edición, desactivación y eliminación de bancos (NIT único, dirección, ciudad, departamento, teléfono, correo, coordenadas, horario).
- Creación de usuarios ADMIN_BANCO y asignación como administrador del banco.
- Consulta pública de bancos activos, por ciudad, departamento y radio geográfico.

### 5.3 Inventario (ADMIN_BANCO / SUPER_ADMIN)
- Un registro por banco y tipo de sangre (único), con unidades disponibles y unidades mínimas (por defecto 5).
- Ajuste incremental de unidades; indicador de **bajo stock** cuando disponibles < mínimas.
- Listados de bajo stock por banco y globales.

### 5.4 Solicitudes / Urgencias
- El banco crea solicitudes con: tipo de sangre, unidades necesarias, urgencia (ALTA/MEDIA/BAJA), motivo, referencia de paciente, fecha límite y radio de búsqueda (50 km por defecto).
- Estados: `ACTIVA`, `COMPLETADA`, `CANCELADA`, `VENCIDA`. Se registran las unidades recibidas.
- Consulta pública de solicitudes activas, filtrables por tipo de sangre, urgencia y radio.

### 5.5 Matching donante ↔ solicitud
- Dada una solicitud (o parámetros libres), el sistema:
  1. Determina los tipos de sangre que pueden donar al tipo requerido (tabla de compatibilidad OMS).
  2. Filtra donantes activos con esos tipos.
  3. Calcula la distancia (Haversine) y filtra por radio.
  4. Ordena por cercanía e indica `aptoParaDonar` y días desde la última donación completada.
- Accesible para ADMIN_BANCO y SUPER_ADMIN.

### 5.6 Donaciones
- Registro de donación (donante, banco, solicitud opcional, fecha, tipo de sangre, cantidad en ml — 450 por defecto —, hemoglobina, presión arterial, observaciones).
- Estados: `PENDIENTE`, `COMPLETADA`, `RECHAZADA`, `CANCELADA`.
- **Regla:** mínimo **90 días** entre donaciones; el sistema rechaza el registro e informa los días restantes.
- Consultas por donante (con historial), banco, rango de fechas, solicitud y estado.
- Cambio de estado por ADMIN_BANCO/SUPER_ADMIN; el super admin puede completar una donación desde un modal.

### 5.7 Reportes (SUPER_ADMIN)
- Centro de reportes con exportación a **Excel**.

### 5.8 Asistente conversacional
- Chat en la tarjeta de urgencias que consulta un modelo de lenguaje (Gemini, vía endpoint compatible con OpenAI) a través de un proxy del backend (`/api/claude/chat`) para no exponer la API key.

## 6. Pantallas (frontend)

| Ruta | Pantalla | Rol |
|---|---|---|
| `/login`, `/registro` | Acceso y registro | Público |
| `/home-donante` | Inicio del donante | DONANTE |
| `/urgencias` | Urgencias activas | Autenticado |
| `/mapa` | Mapa de bancos (Leaflet) | Autenticado |
| `/home-banco` | Panel del banco | ADMIN_BANCO |
| `/inventario` | Inventario por tipo de sangre | ADMIN_BANCO |
| `/solicitudes` | Gestión de solicitudes | ADMIN_BANCO |
| `/super-admin` | Panel de super admin | SUPER_ADMIN |
| `/super-admin/bancos` | Gestión de bancos y admins | SUPER_ADMIN |
| `/super-admin/reportes` | Centro de reportes | SUPER_ADMIN |

## 7. Requisitos no funcionales

- **Seguridad:** JWT, contraseñas cifradas, CORS configurado, autorización por rol, secretos fuera del código.
- **Rendimiento:** respuestas de la API < 500 ms en consultas habituales; el matching escala con el número de donantes (ver riesgos).
- **Disponibilidad:** frontend en Vercel; backend y base de datos gestionados (Supabase/PostgreSQL).
- **Privacidad:** datos médicos y de ubicación son sensibles; acceso restringido por rol y por propiedad del registro.
- **Documentación:** API documentada con Swagger UI.
- **Idioma:** interfaz y mensajes en español.

## 8. Arquitectura y stack

- **Frontend:** React + Vite + Tailwind + Leaflet, desplegado en Vercel.
- **Backend:** Spring Boot 3 / Java 17, capas controller → service → repository, DTOs, manejo global de excepciones.
- **Base de datos:** PostgreSQL (Supabase).
- **Entidades:** Usuario, Rol, Banco, Inventario, Solicitud, Donacion.

## 9. Fuera de alcance (v1)

- Notificaciones push/SMS/correo automáticas a donantes compatibles.
- Agendamiento de citas de donación.
- App móvil nativa.
- Integración con sistemas hospitalarios o historia clínica.
- Cuestionario de elegibilidad médica completo.

## 10. Riesgos y puntos abiertos

| Riesgo / pendiente | Mitigación sugerida |
|---|---|
| El matching carga todos los donantes compatibles en memoria | Prefiltrar por bounding box en SQL o usar PostGIS |
| Endpoint `/api/claude/chat` es público y reenvía a un servicio de pago | Exigir autenticación, aplicar rate limiting y limitar el tamaño de la petición |
| Nombre del endpoint (`claude`) no corresponde al proveedor (Gemini) | Renombrar a `/api/asistente/chat` |
| Rutas mezcladas (`/api/v1/auth` vs `/api/...`) | Unificar versionado de la API |
| Falta de pruebas automatizadas (solo test de arranque) | Agregar pruebas de servicio y de integración para reglas de negocio |
| Sin notificaciones, el beneficio depende de que el donante abra la app | Priorizar notificaciones en v2 |
| Datos sensibles de salud y ubicación | Revisar cumplimiento de la normativa local de protección de datos |

## 11. Hoja de ruta

- **v1 (actual):** registro, bancos, inventario, solicitudes, matching, donaciones, reportes, mapa, asistente.
- **v1.1:** pruebas automatizadas, endurecimiento de seguridad, unificación de rutas.
- **v2:** notificaciones a donantes compatibles, citas de donación, métricas avanzadas, app móvil.
