# Entorno de pruebas local (H2)

Esta guía levanta DonaVida en tu máquina **sin credenciales de Supabase**, usando una base H2 en archivo. Es independiente de la versión publicada: cada quien trabaja con su propia base local.

## Requisitos

- Java 17 o superior
- Node.js 20.19+ o 22 LTS
- Git

No necesitas instalar Maven: el proyecto incluye el wrapper (`mvnw`).

## 1. Clonar el repositorio

```bash
git clone https://github.com/svaltqt/donacion-sangre.git
cd donacion-sangre
git checkout docs/pruebas
```

## 2. Configurar el backend

El archivo `application.properties` no está en el repositorio porque contiene secretos. Crea el tuyo a partir del ejemplo:

```powershell
# Windows (PowerShell)
Copy-Item backend/src/main/resources/application.properties.example backend/src/main/resources/application.properties
```

```bash
# Linux / macOS / Git Bash
cp backend/src/main/resources/application.properties.example backend/src/main/resources/application.properties
```

El ejemplo ya viene configurado para H2 local; no hay que cambiar nada para empezar.

## 3. Arrancar el backend

```powershell
cd backend
.\mvnw.cmd spring-boot:run        # Windows
```

```bash
cd backend
./mvnw spring-boot:run            # Linux / macOS / Git Bash
```

Cuando la consola muestre `Started ApiBancoSangreApplication`, la API está en `http://localhost:8081`. Deja esta terminal abierta.

La base H2 se crea sola en `backend/data/` con los roles iniciales. Para empezar de cero, detén el backend, borra la carpeta `backend/data/` y vuelve a arrancar.

## 4. Configurar y arrancar el frontend

En **otra terminal**, crea el archivo que apunta el frontend a tu backend local:

```powershell
Set-Content frontend/.env.development.local "VITE_API_URL=http://localhost:8081"
```

Luego:

```bash
cd frontend
npm install
npm run dev
```

Abre la URL que muestre Vite (por defecto `http://localhost:5173`).

> Si Vite arranca en otro puerto (5174, etc.), el login fallará por CORS. Libera el 5173 y vuelve a arrancar.

## 5. Crear tu cuenta de prueba

La base local empieza **sin usuarios**. Entra a `http://localhost:5173/registro` y crea tu propia cuenta de donante. Elige tu ubicación en el formulario para que la latitud y la longitud no queden vacías.

Con esa cuenta ya puedes iniciar sesión y probar el flujo del donante.

> La base local no trae los bancos ni los usuarios administradores de la versión publicada. Para cargar datos de prueba (bancos, inventario, solicitudes, cuentas por rol), usa los scripts de `docs/pruebas/scripts/`.

## Resumen de arranque (cuando ya está configurado)

```powershell
# Terminal 1
cd backend
.\mvnw.cmd spring-boot:run

# Terminal 2
cd frontend
npm run dev
```

Cierra cada proceso con Ctrl+C.