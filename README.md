# ProyectoPAE

<!-- markdownlint-disable MD012 -->

Repositorio para la aplicacion de gestion de rutas, pedidos y recogidas de ultima milla.

## Arquitectura objetivo (movil)

| Capa | Tecnologia |
| ---- | ---------- |
| Backend / API | Python 3.12 + FastAPI |
| Frontend movil | Flutter (Dart) |
| Base de datos | Neo4j (Graph Database) |
| Tiempo real | WebSocket (FastAPI nativo) |
| Autenticacion | JWT (`python-jose`) + bcrypt (`passlib`) |
| Tests backend | pytest + pytest-asyncio + HTTPX |

## Funcionalidades

- Dos roles de usuario: `central` y `repartidor`
- Gestion de pedidos (`delivery` y `pickup`)
- Asignacion de pedidos a repartidores con calculo de tiempo extra
- Ruta activa por repartidor
- Estados de pedido (`pending`, `assigned`, `in_progress`, `completed`, `rejected`)
- Flujo en tiempo real por WebSocket (ubicaciones y notificaciones)

## Estructura del proyecto

```text
backend/
    app/
        main.py
        config.py
        database.py
        schemas.py
        auth.py
        routing.py
        ws_manager.py
        routers/
            auth.py
            drivers.py
            orders.py
            ws.py
    static/            # frontend web legado (referencia)
    tests/
    requirements.txt
    pytest.ini

mobile_app/
    lib/
        main.dart
        src/
            app.dart
            config/
            models/
            services/
            state/
            ui/
    pubspec.yaml
    analysis_options.yaml
```

## Configuración de Base de Datos (Neo4j)

Este proyecto utiliza **Neo4j** como base de datos de grafos para gestionar las relaciones entre usuarios, pedidos y rutas.

### 1. Descargar e instalar
Es necesario descargar e instalar **Neo4j Desktop 2** (o superior) desde la [página oficial de Neo4j](https://neo4j.com/download/).

### 2. Crear base de datos local
1.  Abre **Neo4j Desktop**.
2.  Crea un nuevo proyecto o usa el por defecto.
3.  Haz clic en **"Add"** -> **"Local DBMS"**.
4.  Configura un nombre (ej: `PAE`) y una contraseña (recomendado: `12345678`).
5.  Haz clic en **"Create"**.
6.  Una vez creado, pulsa el botón **"Start"** para iniciar el servidor.

### 3. Conexión
Por defecto, la aplicación intentará conectarse a:
- **URL**: `neo4j://127.0.0.1:7687`
- **Usuario**: `neo4j`
- **Contraseña**: La que hayas configurado (ej: `12345678`)

> [!NOTE]
> No es necesario crear las tablas/nodos manualmente. El backend se encarga de crear las restricciones y los datos de prueba (`seeding`) automáticamente al arrancar.

## Arranque del backend (Python)

1. Crear y activar entorno virtual:
```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
```` cmd
.venv\Scripts\activate
```

2. Instalar dependencias:
```powershell
pip install -r requirements.txt
```

3. Ejecutar:
```powershell
uvicorn app.main:aplicacion --reload --port 8000
```

Backend disponible en:

- API: `http://localhost:8000`
- Swagger: `http://localhost:8000/docs`

## Arranque del frontend movil (Flutter)

```bash
cd mobile_app
flutter create .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Notas:

- Android Emulator usa `10.0.2.2` para acceder al host local.
- En iOS Simulator suele funcionar `http://localhost:8000`.

## Arranque por consola (demo estable)

## Arranque visual para demo (Flutter)

Para presentaciones a publico no tecnico, usa doble clic en:

- `Iniciar Demo.bat`

Este acceso abre un panel Flutter de escritorio con botones para iniciar/detener,
y activa por defecto reinicio automatico de sesion para evitar el error:
`Ya existe una sesion activa`.

Si necesitas cerrar todo de emergencia sin abrir el panel, usa:

- `Detener Demo.bat`

Desde la raiz de `ProyectoPAE`, ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1
```

Este script hace todo automaticamente:

- Verifica Python y Flutter en PATH
- Comprueba que Neo4j este iniciado antes de arrancar backend/Flutter
- Verifica/instala backend (`pip install -r backend/requirements.txt`)
- Verifica/instala mobile (`flutter pub get`)
- Genera plataformas Flutter faltantes para los dispositivos elegidos
- Compila Flutter Web con `flutter build web`
- Lanza backend en `localhost:8000`
- Sirve la app web en `localhost:8081`
- Abre dos navegadores: Chrome para central y Edge para repartidor

Parametros utiles:

```powershell
# Reinicia sesion previa automaticamente
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -ForceRestart

# Solo verifica e instala dependencias, sin lanzar terminales
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -NoLaunch

# Cambiar dispositivos Flutter
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -CentralDevice chrome -DriverDevice edge

# Cambiar URL API usada en la build Flutter Web
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -ApiBaseUrl http://10.0.2.2:8000
```

Para detener rapido los procesos y navegadores abiertos por el script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop-demo.ps1
```

### Ubuntu/Linux (Flutter Web)

En Linux el flujo de demo es independiente del flujo Windows: usa Flutter Web,
FastAPI y una instancia local de Neo4j ya iniciada. Los scripts crean
`backend/.venv` con `python3` y, si Flutter no existe en PATH, descargan el SDK
estable en `~/.local/share/flutter` sin requerir una instalacion global.

Primera preparacion:

```bash
bash scripts/setup-linux.sh
```

El setup instala dependencias backend, ejecuta `flutter pub get` y verifica que
Neo4j escuche por Bolt. No instala ni configura Neo4j automaticamente. Por
defecto se espera:

- Bolt: `bolt://127.0.0.1:7687`
- Usuario: `neo4j`
- Contrasena: `12345678`
- Base de datos: `neo4j`

Si Neo4j no esta levantado, inicia tu servicio/instancia local y repite el
comando. En Ubuntu puedes seguir la guia oficial:
<https://neo4j.com/docs/operations-manual/current/installation/linux/debian/>.

Arrancar la demo web:

```bash
bash scripts/start-demo-linux.sh --force-restart
```

Arrancar sin abrir navegador automaticamente:

```bash
bash scripts/start-demo-linux.sh --no-launch
```

Por defecto:

- Backend: `http://127.0.0.1:8000`
- Healthcheck: `http://127.0.0.1:8000/health`
- Frontend Flutter Web: `http://localhost:8081`
- Estado runtime: `scripts/.demo-state-linux.json`
- Logs runtime: `scripts/.demo-logs/`

Parametros utiles:

```bash
# Cambiar URL de API embebida en Flutter Web
bash scripts/start-demo-linux.sh --api-base-url http://localhost:8000

# Cambiar puertos locales
bash scripts/start-demo-linux.sh --backend-port 8000 --frontend-port 8081

# Detener la sesion Linux
bash scripts/stop-demo-linux.sh
```

Si el script instalo Flutter localmente, puedes diagnosticarlo con:

```bash
$HOME/.local/share/flutter/bin/flutter doctor -v
```

## Usuarios demo

| Usuario | Contrasena | Rol |
| ------- | ---------- | --- |
| `central` | `central123` | Central |
| `driver1` | `driver123` | Repartidor |
| `driver2` | `driver123` | Repartidor |

## Tests backend

```bash
cd backend
pytest -v
```

## Variables de entorno backend

| Variable | Defecto | Descripcion |
| -------- | ------- | ----------- |
| `SECRET_KEY` | `pae_dev_secret_cambiar_en_produccion` | Clave JWT |
| `NEO4J_URI` | `bolt://127.0.0.1:7687` | URI de conexión a Neo4j |
| `NEO4J_USER` | `neo4j` | Usuario de la base de datos |
| `NEO4J_PASSWORD` | `12345678` | Contraseña de la base de datos |
| `NEO4J_DATABASE` | `neo4j` | Nombre de la base de datos |
| `CORS_ORIGINS` | `http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080` | Origenes CORS permitidos |
| `CORS_ORIGIN_REGEX` | `^https?://(localhost\|127\.0\.0\.1)(:\d+)?$` | Permite origenes locales con puertos dinamicos (Flutter web) |
| `OSRM_ENABLED` | `1` | Activa calculo de ruta real por calles con OSRM (0 para desactivar) |
| `OSRM_BASE_URL` | `https://router.project-osrm.org` | Endpoint OSRM para tabla de tiempos y geometria de ruta |
| `OSRM_TIMEOUT_SECONDS` | `2.0` | Timeout por peticion a OSRM en segundos |

## API resumida

| Metodo | Ruta | Descripcion |
| ------ | ---- | ----------- |
| `POST` | `/auth/login` | Login y token JWT |
| `POST` | `/auth/register` | Registro de nuevo usuario (UUID) |
| `GET` | `/auth/me` | Usuario autenticado |
| `GET` | `/drivers/` | Lista repartidores (central) |
| `PUT` | `/drivers/:id/location` | Actualizar ubicacion (repartidor) |
| `GET` | `/orders/` | Listar pedidos |
| `POST` | `/orders/` | Crear pedido (central) |
| `POST` | `/orders/:id/assign` | Asignar pedido (central) |
| `POST` | `/orders/:id/respond` | Aceptar/rechazar (repartidor) |
| `PATCH` | `/orders/:id/status` | Cambiar estado |
| `GET` | `/orders/route/:driver_id` | Ruta activa |
| `WS` | `/ws?token=...` | Canal tiempo real |

---

Tutorial detallado: [TUTORIAL.md](TUTORIAL.md)
