# ProyectoPAE

Repositorio para la aplicacion de gestion de rutas, pedidos y recogidas de ultima milla.

## Arquitectura objetivo (movil)

| Capa | Tecnologia |
|------|-----------|
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

```
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

## Usuarios demo

| Usuario | Contrasena | Rol |
|---------|------------|-----|
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
|----------|---------|-------------|
| `SECRET_KEY` | `pae_dev_secret_cambiar_en_produccion` | Clave JWT |
| `DB_PATH` | `pae.db` | Ruta de SQLite |
| `CORS_ORIGINS` | `http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080` | Origenes CORS permitidos |

## API resumida

| Metodo | Ruta | Descripcion |
|--------|------|-------------|
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

