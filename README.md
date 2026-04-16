# ProyectoPAE

<!-- markdownlint-disable MD012 -->

Repositorio para la aplicacion de gestion de rutas, pedidos y recogidas de ultima milla.

## Arquitectura objetivo (movil)

| Capa | Tecnologia |
| ---- | ---------- |
| Backend / API | Python 3.12 + FastAPI |
| Frontend movil | Flutter (Dart) |
| Base de datos | SQLite (`sqlite3`) |
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

## Arranque del backend (Python)

```bash
cd backend
pip install -r requirements.txt
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

## Arranque por consola (1 comando, 3 terminales)

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
- Verifica/instala backend (`pip install -r backend/requirements.txt`)
- Verifica/instala mobile (`flutter pub get`)
- Genera plataformas Flutter faltantes para los dispositivos elegidos
- Lanza 3 terminales: backend, app central y app repartidor

Parametros utiles:

```powershell
# Reinicia sesion previa automaticamente
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -ForceRestart

# Solo verifica e instala dependencias, sin lanzar terminales
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -NoLaunch

# Cambiar dispositivos Flutter
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -CentralDevice chrome -DriverDevice edge

# Cambiar URL API para flutter run
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -ApiBaseUrl http://10.0.2.2:8000
```

Para detener rapido las 3 terminales abiertas por el script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop-demo.ps1
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
| `DB_PATH` | `pae.db` | Ruta de SQLite |
| `CORS_ORIGINS` | `http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080` | Origenes CORS permitidos |
| `CORS_ORIGIN_REGEX` | `^https?://(localhost\|127\.0\.0\.1)(:\d+)?$` | Permite origenes locales con puertos dinamicos (Flutter web) |
| `OSRM_ENABLED` | `1` | Activa calculo de ruta real por calles con OSRM (0 para desactivar) |
| `OSRM_BASE_URL` | `https://router.project-osrm.org` | Endpoint OSRM para tabla de tiempos y geometria de ruta |
| `OSRM_TIMEOUT_SECONDS` | `2.0` | Timeout por peticion a OSRM en segundos |

## API resumida

| Metodo | Ruta | Descripcion |
| ------ | ---- | ----------- |
| `POST` | `/auth/login` | Login y token JWT |
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

