# Tutorial de PAE (version movil)

Guia para ejecutar y usar PAE con backend en Python y frontend movil en Flutter.

## 1) Que es PAE

PAE gestiona rutas de ultima milla para una central de despacho y varios repartidores.
Cuando aparece una nueva recogida, la central la asigna y el sistema estima el tiempo
extra usando insercion optima sobre la ruta activa.

## 2) Stack

- Backend: Python + FastAPI
- Frontend movil: Flutter + Dart
- Base de datos: Neo4j (Graph Database)
- Tiempo real: WebSocket

## 3) Roles

| Rol | Usuario demo | Contrasena | Permisos principales |
| --- | ------------ | ---------- | -------------------- |
| Central | `central` | `central123` | Crear pedidos, asignar pedidos, ver repartidores |
| Repartidor | `driver1` | `driver123` | Ver ruta, responder recogidas, actualizar ubicacion |
| Repartidor | `driver2` | `driver123` | Igual que `driver1` |

## 4) Arranque rapido

### Modo automatico (recomendado para demo rapida)

Desde la raiz de `ProyectoPAE`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1
```

Que hace este comando:

- Verifica herramientas base (Python y Flutter)
- Comprueba que Neo4j este iniciado y escuchando en Bolt
- Verifica/instala dependencias backend
- Verifica/instala dependencias Flutter
- Genera plataformas Flutter faltantes
- Compila Flutter Web
- Lanza backend en `localhost:8000`
- Sirve la app web en `localhost:8081`
- Abre Chrome y Edge para probar central y repartidor en paralelo

Comandos utiles:

```powershell
# Reiniciar una sesion anterior automaticamente
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -ForceRestart

# Verificar e instalar sin lanzar apps
powershell -ExecutionPolicy Bypass -File .\scripts\start-demo.ps1 -NoLaunch

# Detener toda la sesion automatizada
powershell -ExecutionPolicy Bypass -File .\scripts\stop-demo.ps1
```

### Backend

1. Crear y activar entorno virtual:
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

2. Instalar dependencias:
```powershell
pip install -r requirements.txt
```

3. Ejecutar:
```powershell
uvicorn app.main:aplicacion --reload --port 8000
```

Backend disponible en `http://localhost:8000`.

### App movil Flutter

```bash
cd mobile_app
flutter create .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000
```

Notas:

- Android Emulator: `10.0.2.2` apunta al host local.
- iOS Simulator: normalmente `http://localhost:8000`.

## 5) Flujo de uso en movil

### Como Central

1. Inicia sesion con `central` / `central123`.
2. Entra al panel central.
3. Crea pedidos nuevos (`pickup` o `delivery`).
4. Asigna pedidos pendientes a un repartidor.
5. Revisa eventos en tiempo real (ubicacion y respuestas de recogida).

### Como Repartidor

1. Inicia sesion con `driver1` / `driver123`.
2. Ve recogidas pendientes de respuesta.
3. Acepta o rechaza una recogida asignada.
4. Marca pedidos como en curso o completados.
5. Envia ubicacion manual (lat/lng) para actualizar a la central.

## 6) Como funciona internamente

### JWT

El login devuelve un token JWT que se envia en cada request:

```http
Authorization: Bearer <token>
```

### Neo4j (Graph Database)

Nodos y relaciones principales:

- `(User)`: Usuarios (central y repartidores).
- `(Order)`: Pedidos y recogidas.
- `(Route)`: Rutas activas conectadas a usuarios.
- `(User)-[:ASSIGNED_TO]->(Order)`
- `(User)-[:HAS_ROUTE]->(Route)`

### WebSocket

Canal: `/ws?token=...`

- Repartidor envia ubicacion y respuestas de recogida.
- Central recibe actualizaciones y notifica nuevas recogidas.

### Insercion optima

Para una recogida nueva, se calcula el desvio minimo probado en cada posible
posicion de la ruta:

$$
desvio = dist(A, nueva) + dist(nueva, B) - dist(A, B)
$$

La distancia usa formula Haversine.

## 7) Pruebas backend

```bash
cd backend
pytest -v
```

## 8) Variables de entorno backend

| Variable | Valor por defecto | Uso |
| -------- | ----------------- | --- |
| `SECRET_KEY` | `pae_dev_secret_cambiar_en_produccion` | Firma JWT |
| `NEO4J_URI` | `neo4j://127.0.0.1:7687` | URI de Neo4j |
| `NEO4J_USER` | `neo4j` | Usuario Neo4j |
| `NEO4J_PASSWORD` | `12345678` | Contrasena Neo4j |
| `CORS_ORIGINS` | `http://localhost:3000,http://localhost:8080,http://127.0.0.1:3000,http://127.0.0.1:8080` | Origenes permitidos |

## 9) Endpoints API

| Metodo | Ruta | Descripcion |
| ------ | ---- | ----------- |
| `POST` | `/auth/login` | Login |
| `POST` | `/auth/register` | Registro |
| `GET` | `/auth/me` | Usuario actual |
| `GET` | `/drivers/` | Repartidores (central) |
| `PUT` | `/drivers/:id/location` | Actualizar ubicacion |
| `GET` | `/orders/` | Pedidos |
| `POST` | `/orders/` | Crear pedido |
| `POST` | `/orders/:id/assign` | Asignar pedido |
| `POST` | `/orders/:id/respond` | Aceptar/rechazar |
| `PATCH` | `/orders/:id/status` | Cambiar estado |
| `GET` | `/orders/route/:driver_id` | Ruta activa |
| `WS` | `/ws?token=...` | Tiempo real |

Swagger: `http://localhost:8000/docs`
