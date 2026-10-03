# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Monorepo de una plataforma que conecta donantes de sangre con bancos de sangre (UI y mensajes en español). Producto descrito en [docs/PRD.md](docs/PRD.md).

- `backend/` — Spring Boot 3 / Java 17 (paquete `com.bancosangre.api_banco_sangre`), puerto 8081
- `frontend/` — React 19 + Vite + Tailwind + Leaflet, puerto 5173

## Comandos

Backend (desde `backend/`):
```bash
./mvnw spring-boot:run                     # levanta la API en :8081
./mvnw test                                # todos los tests (solo existe un test de arranque)
./mvnw test -Dtest=NombreTest#metodo       # un solo test
```
Swagger: `http://localhost:8081/swagger-ui/index.html`. Consola H2: `/h2-console`.

Frontend (desde `frontend/`):
```bash
npm install
npm run dev      # servidor de desarrollo
npm run build
npm run lint     # eslint; no hay tests de frontend
```

## Arquitectura

### Backend
Capas `controller → service (interfaz + impl/) → repository`, con DTOs de entrada/salida y `GlobalExceptionHandler` (`RecursoNoEncontradoException` para 404).

- **Seguridad:** JWT sin sesión (`JwtAuthFilter`, `JwtService`/`security/JwtUtils`). Hay **dos capas de autorización**: `SecurityConfig` define con `requestMatchers` qué GET son públicos (bancos activos, urgencias, auth, proxy de chat), y cada controller usa `@PreAuthorize` con los roles `SUPER_ADMIN`, `ADMIN_BANCO`, `DONANTE`. Al añadir un endpoint público hay que tocar `SecurityConfig`; si no, exige token.
- **Prefijos de ruta inconsistentes:** auth vive en `/api/v1/auth/**`; el resto en `/api/<recurso>` (`bancos`, `solicitudes`, `donaciones`, `inventario`, `matching`, `usuarios`).
- **Matching** (`MatchingServiceImpl`): tabla de compatibilidad OMS hardcodeada, filtra donantes activos compatibles, distancia Haversine en memoria contra el radio de la solicitud (50 km por defecto), marca `aptoParaDonar` con ≥ 90 días desde la última donación completada.
- **Reglas de negocio en `DonacionServiceImpl`:** intervalo mínimo de 90 días entre donaciones; estados `PENDIENTE/COMPLETADA/RECHAZADA/CANCELADA`. Solicitudes: `ACTIVA/COMPLETADA/CANCELADA/VENCIDA`, urgencia `ALTA/MEDIA/BAJA`. Inventario es único por (banco, tipo de sangre) y `isBajoStock` compara disponibles con mínimas.
- **`ClaudeController`:** a pesar del nombre, es un proxy sin autenticación hacia la API de Gemini (formato OpenAI-compatible) usando `gemini.api.key`; lo consume el chat de `UrgenciaCard.jsx`.
- **Base de datos local:** `application.properties` apunta a H2 en archivo (`./data/donavida`) con `ddl-auto=update` y carga `data-h2.sql` al arrancar. En producción la BD es PostgreSQL (Supabase); la configuración local no es la de producción.

### Frontend
- `services/api.js`: instancia única de axios (`VITE_API_URL`, por defecto `http://localhost:8081`) con interceptor que agrega el `Bearer` token de `localStorage`; los servicios por recurso (`authService`, `solicitudService`, …) viven ahí.
- `context/AuthContext.jsx` guarda `token` y `usuario` en `localStorage`; `App.jsx` define las rutas protegidas por rol (`/home-donante`, `/home-banco`, `/inventario`, `/solicitudes`, `/super-admin/*`, `/urgencias`, `/mapa`).
- Despliegue en Vercel; `vercel.json` reescribe todo a `/` para el router SPA. `.env.production` define la URL del backend.

## Ramas
`main` es la rama principal; el trabajo se hace en ramas de feature/docs (p. ej. `docs/documentacion`).

## Pruebas (tarea actual)

Objetivo: ejecutar los casos P-01 a P-20 y documentar resultados y bugs.
- Casos y set de datos: `docs/pruebas/` (casos de prueba, set de datos, plan).
- Evidencias: `docs/pruebas/evidencias/P-XX/` (capturas o petición/respuesta HTTP).
- Resultados: `docs/pruebas/resultados.md` (caso, estado Aprobado/Fallido/Bloqueado,
  evidencia; para fallidos: ID BUG-XX, pasos, esperado, observado, severidad propuesta).

### Reglas
- NUNCA corregir código de la aplicación para que una prueba pase. Un fallo se documenta como bug.
  Excepción: solo `data-h2.sql` y el código de pruebas se pueden modificar.
- NUNCA usar la API de producción (`*.railway.app`) ni tocar `.env.production` ni `.env.local`.
  En local el frontend usa `frontend/.env.development.local` → `http://localhost:8081`.
- Si un criterio de la HU es ambiguo, registrarlo como "consulta funcional", no como bug.
- Antes de reportar un bug de UI, descartar que sea un error de la propia prueba (selector, espera).

### Entorno de pruebas
- Reiniciar datos: detener el backend, borrar `backend/data/` y volver a arrancar.
- CORS solo permite `http://localhost:5173`; si Vite arranca en otro puerto, liberar el 5173.
- Contraseñas en BD cifradas con BCrypt: crear usuarios vía `/api/v1/auth/registro`
  o insertar hashes BCrypt válidos, nunca texto plano.
- Pruebas de API: JUnit + MockMvc (`spring-boot-starter-test` ya está en el pom).
- Pruebas de UI y end-to-end (P-18, P-19, P-20): Playwright en `frontend/`, captura en cada paso.
