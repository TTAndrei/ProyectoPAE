# ProyectoPAE
Repositorio para la aplicación de gestión de rutas, pedidos y recogidas

---

> 📖 **Tutorial completo en español**: [TUTORIAL.md](TUTORIAL.md)

## PAE – Gestión de Rutas de Última Milla

Aplicación web full-stack para gestionar rutas de repartidores en tiempo real, con notificaciones de recogidas y optimización de trayectos.

### Tecnologías

| Capa | Tecnología |
|------|-----------|
| Backend / API | **Python 3.12 + FastAPI** |
| Base de datos | **SQLite** (stdlib `sqlite3`) |
| Tiempo real | **WebSockets** (FastAPI nativo) |
| Autenticación | **JWT** (`python-jose`) + bcrypt (`passlib`) |
| Frontend | **HTML + CSS + JavaScript vanilla + Leaflet.js** |
| Tests | **pytest + pytest-asyncio + HTTPX** |

---

### Funcionalidades implementadas

- **Dos tipos de usuario**: `central` (despachador) y `repartidor`
- **Mapa interactivo** con Leaflet.js – visualización de posiciones y rutas en tiempo real
- **Ubicación en tiempo real** de los conductores mediante WebSockets
- **Algoritmo de pathfinding** (inserción óptima por mínimo desvío, fórmula Haversine)
- **Sistema de elección**: el repartidor ve el tiempo extra estimado y puede **aceptar o rechazar** cada recogida
- **HUD** limpio y responsivo para escritorio y móvil
- **Arquitectura de asignación**: cada usuario (repartidor) tiene una ruta (`Route`) con una lista ordenada de paradas (`Order`)

---

### Estructura del proyecto

```
backend/
├── app/
│   ├── main.py          # Aplicación FastAPI (factory)
│   ├── config.py        # Configuración y constantes
│   ├── database.py      # Inicialización SQLite + seed
│   ├── schemas.py       # Modelos Pydantic
│   ├── auth.py          # JWT utilities
│   ├── routing.py       # Haversine + algoritmo de inserción óptima
│   ├── ws_manager.py    # Gestor de conexiones WebSocket
│   └── routers/
│       ├── auth.py      # POST /auth/login, GET /auth/me
│       ├── drivers.py   # GET/PUT /drivers/
│       ├── orders.py    # CRUD /orders/ + /orders/route/:id
│       └── ws.py        # WebSocket /ws?token=...
├── static/              # Frontend servido por FastAPI
│   ├── index.html
│   ├── css/style.css
│   ├── js/app.js
│   └── vendor/          # Leaflet.js (local)
├── tests/
│   ├── conftest.py
│   ├── test_routing.py  # 9 tests unitarios
│   └── test_api.py      # 18 tests de integración
├── requirements.txt
└── pytest.ini
```

---

### Instalación y arranque

```bash
cd backend

# 1. Crear entorno virtual (recomendado)
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate

# 2. Instalar dependencias
pip install -r requirements.txt

# 3. Arrancar el servidor (crea la BD y datos demo automáticamente)
uvicorn app.main:aplicacion --reload --port 8000
```

Abrir **http://localhost:8000** en el navegador.

#### Usuarios demo

| Usuario | Contraseña | Rol |
|---------|-----------|-----|
| `central` | `central123` | Central (despachador) |
| `driver1` | `driver123` | Repartidor |
| `driver2` | `driver123` | Repartidor |

---

### Tests

```bash
cd backend
pytest -v
```

Resultado esperado: **27 passed**.

---

### Variables de entorno

| Variable | Defecto | Descripción |
|----------|---------|-------------|
| `SECRET_KEY` | `pae_dev_secret_change_in_production` | Clave secreta JWT – **cambiar en producción** |
| `DB_PATH` | `pae.db` | Ruta al archivo SQLite |
| `CORS_ORIGINS` | `http://localhost:3000` | Orígenes CORS permitidos |

---

### API REST resumida

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/auth/login` | Autenticación, devuelve JWT |
| `GET` | `/auth/me` | Usuario actual |
| `GET` | `/drivers/` | Lista repartidores con ubicación (Central) |
| `PUT` | `/drivers/:id/location` | Actualizar ubicación (Repartidor) |
| `GET` | `/orders/` | Listar pedidos |
| `POST` | `/orders/` | Crear pedido (Central) |
| `POST` | `/orders/:id/assign` | Asignar pedido a repartidor + tiempo extra |
| `POST` | `/orders/:id/respond` | Aceptar/rechazar recogida (Repartidor) |
| `PATCH` | `/orders/:id/status` | Actualizar estado |
| `GET` | `/orders/route/:driver_id` | Ruta activa del repartidor |
| `WS` | `/ws?token=...` | Canal WebSocket tiempo real |

Documentación interactiva disponible en **http://localhost:8000/docs**.

