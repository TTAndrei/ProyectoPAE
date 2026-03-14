# Tutorial de PAE – Gestión de Rutas de Última Milla

Esta guía explica cómo funciona el sistema PAE, qué hace cada componente y
cómo usarlo paso a paso.

---

## ¿Qué es PAE?

PAE es una aplicación web que permite a una **central de reparto** gestionar
las rutas de varios **repartidores** en tiempo real. Cuando surge una nueva
recogida, la central la asigna al repartidor más adecuado y el sistema calcula
automáticamente cuántos minutos extra supone el desvío.

---

## Roles de usuario

| Rol | Usuario demo | Contraseña | ¿Qué puede hacer? |
|-----|-------------|-----------|-------------------|
| **Central** (despachador) | `central` | `central123` | Ver todos los pedidos, crear recogidas, asignarlas a repartidores |
| **Repartidor** | `driver1` | `driver123` | Ver su ruta, actualizar su ubicación, aceptar o rechazar recogidas |
| **Repartidor** | `driver2` | `driver123` | Igual que `driver1` |

---

## Instalación y arranque rápido

```bash
# 1. Ir al directorio backend
cd backend

# 2. Crear un entorno virtual de Python (recomendado)
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

# 3. Instalar las dependencias
pip install -r requirements.txt

# 4. Arrancar el servidor (crea la BD y datos demo automáticamente)
uvicorn app.main:aplicacion --reload --port 8000
```

Abrir **http://localhost:8000** en el navegador.

---

## Tutorial paso a paso

### Como operador **Central**

1. **Iniciar sesión** con `central` / `central123`.
2. Se abrirá un mapa con los marcadores azules de cada repartidor.
3. En la barra lateral izquierda verás la lista de repartidores y sus posiciones.
4. Haz clic sobre el nombre de un repartidor para ver su ruta en el mapa
   (la línea azul discontinua conecta sus paradas pendientes en orden).
5. Si hay **recogidas pendientes** (sección amarilla en la barra lateral):
   - Selecciona un repartidor en el desplegable de cada recogida.
   - Haz clic en **Asignar**: el sistema calculará el tiempo extra de desvío
     y enviará una notificación al repartidor a través del WebSocket.
6. El mapa se actualiza en tiempo real cuando los repartidores mueven su posición.

### Como **Repartidor**

1. **Iniciar sesión** con `driver1` / `driver123`.
2. Se abrirá el mapa con los marcadores numerados de tus paradas pendientes.
3. En la barra lateral verás la lista de paradas ordenadas con su tipo
   (📬 entrega o 📦 recogida) y estado actual.
4. Haz clic en una parada para centrar el mapa en ella.
5. Cuando termines una parada, pulsa **✔ Completar** para marcarla como finalizada.
6. Si la central te asigna una **nueva recogida**, aparecerá un modal con:
   - La dirección de la recogida.
   - El tiempo extra estimado que supondría aceptarla.
   - Botones para **Aceptar** ✅ o **Rechazar** ❌.
7. Tu posición GPS se envía automáticamente al servidor en segundo plano
   (si no hay GPS disponible, se simula un movimiento circular en Madrid para la demo).

---

## Cómo funciona por dentro

### Autenticación (JWT)

Al hacer login, el servidor genera un **token JWT** firmado con una clave secreta.
El cliente incluye ese token en cada petición HTTP en el encabezado:
```
Authorization: Bearer <token>
```
El token expira en 8 horas. Cada rol (central/repartidor) tiene acceso solo
a los endpoints permitidos para ese rol.

### Base de datos (SQLite)

Se usan 4 tablas:
- `users`: usuarios del sistema (central y repartidores).
- `orders`: pedidos/recogidas con dirección, coordenadas y estado.
- `routes`: rutas activas de cada repartidor (lista ordenada de IDs de pedidos).
- `driver_locations`: última posición GPS de cada repartidor.

La base de datos se crea automáticamente al arrancar si no existe.

### Comunicación en tiempo real (WebSocket)

El canal `/ws?token=...` permite:
- Los **repartidores** envían su posición GPS periódicamente.
- La **central** recibe actualizaciones de posición de todos los repartidores.
- La **central** notifica a un repartidor cuando se le asigna una recogida.
- El **repartidor** responde si acepta o rechaza la recogida.

### Algoritmo de inserción óptima (Haversine)

Cuando se asigna una recogida, el sistema calcula automáticamente cuántos
minutos extra supone para el repartidor:

1. Se obtiene la posición actual del repartidor y sus paradas pendientes.
2. Se prueba insertar la nueva recogida entre cada par de puntos consecutivos
   de la ruta (posición actual → parada 1 → parada 2 → ...).
3. Se elige la posición que minimiza el desvío total:
   ```
   desvío = dist(A → nueva) + dist(nueva → B) − dist(A → B)
   ```
4. La distancia entre dos puntos geográficos se calcula con la
   **fórmula Haversine**, que tiene en cuenta la curvatura de la Tierra.

---

## Ejecución de las pruebas

```bash
cd backend
pytest -v
```

Resultado esperado: **27 pruebas pasadas**.

Las pruebas están divididas en:
- `tests/test_routing.py`: pruebas unitarias del algoritmo Haversine e inserción óptima.
- `tests/test_api.py`: pruebas de integración de todos los endpoints REST.

---

## Variables de entorno

| Variable | Valor por defecto | Descripción |
|----------|------------------|-------------|
| `SECRET_KEY` | `pae_dev_secret_cambiar_en_produccion` | Clave secreta para firmar los tokens JWT. **¡Cambiar en producción!** |
| `DB_PATH` | `pae.db` | Ruta al archivo SQLite de la base de datos |
| `CORS_ORIGINS` | `http://localhost:3000` | Orígenes permitidos para peticiones cross-origin |

---

## API REST resumida

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/auth/login` | Inicia sesión y devuelve un token JWT |
| `GET` | `/auth/me` | Devuelve los datos del usuario autenticado |
| `GET` | `/drivers/` | Lista los repartidores con su ubicación (solo Central) |
| `PUT` | `/drivers/:id/location` | Actualiza la ubicación GPS del repartidor |
| `GET` | `/orders/` | Lista los pedidos según el rol |
| `POST` | `/orders/` | Crea un nuevo pedido (solo Central) |
| `POST` | `/orders/:id/assign` | Asigna un pedido a un repartidor y calcula el tiempo extra |
| `POST` | `/orders/:id/respond` | El repartidor acepta o rechaza una recogida |
| `PATCH` | `/orders/:id/status` | Actualiza el estado de un pedido a 'in_progress' o 'completed' |
| `GET` | `/orders/route/:id` | Devuelve la ruta activa del repartidor con todas sus paradas |
| `WS` | `/ws?token=...` | Canal WebSocket para comunicación en tiempo real |

Documentación interactiva (Swagger): **http://localhost:8000/docs**
