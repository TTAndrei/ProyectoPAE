/**
 * PAE – Gestión de Rutas de Última Milla
 * Aplicación de página única (SPA) en JavaScript vanilla
 *
 * Estructura general:
 *  1. Estado global (estadoApp)
 *  2. Utilidades (notificacion, peticionApi)
 *  3. Autenticación (formulario de login / logout)
 *  4. Arranque (iniciarApp)
 *  5. Mapa Leaflet (inicializarMapa, limpiarParadasMapa, renderizarRuta)
 *  6. WebSocket (conectarWebSocket, manejarMensajeWs, iniciarEmisionUbicacion)
 *  7. Vista de la central (cargarVistaCentral, renderizarBarraLateralCentral, etc.)
 *  8. Vista del repartidor (cargarVistaRepartidor, renderizarBarraLateralRepartidor, etc.)
 *  9. Modal de recogida (mostrarModalRecogida, aceptar/rechazar)
 * 10. Funciones auxiliares (claseEstado, etiquetaEstado)
 */

// URL base de la API (mismo origen que el frontend)
const URL_API = '';
// URL del WebSocket: ws:// en HTTP, wss:// en HTTPS
const URL_WS = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`;

// ── Estado global de la aplicación ────────────────────────────────────────────
let estadoApp = {
  token: null,                    // Token JWT del usuario autenticado
  usuario: null,                  // Objeto con datos del usuario (id, role, name...)
  ws: null,                       // Conexión WebSocket activa
  mapa: null,                     // Instancia del mapa Leaflet
  marcadoresRepartidores: {},     // id_repartidor → L.Marker (vista central)
  marcadoresParadas: [],          // Array de L.Marker (vista repartidor)
  lineaRuta: null,                // L.Polyline que conecta las paradas
  pedidos: [],                    // Lista de pedidos del usuario actual
  repartidores: [],               // Lista de repartidores (vista central)
  idRepartidorSeleccionado: null, // ID del repartidor actualmente seleccionado
  notificacionPendiente: null,    // { order, extra_minutes } en espera de respuesta
};

// ── Iconos del mapa ────────────────────────────────────────────────────────────
const iconos = {
  // Icono del vehículo del repartidor (círculo azul con camioneta)
  repartidor: L.divIcon({
    className: '',
    html: '<div style="width:34px;height:34px;background:#2b6cb0;border:3px solid #fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,.35);font-size:18px;">🚐</div>',
    iconSize: [34, 34], iconAnchor: [17, 17],
  }),
  // Icono numerado para paradas de entrega (círculo azul con número)
  entrega: (numero) => L.divIcon({
    className: '',
    html: `<div style="width:30px;height:30px;background:#2b6cb0;border:2.5px solid #fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.3);color:#fff;font-weight:700;font-size:13px;">${numero}</div>`,
    iconSize: [30, 30], iconAnchor: [15, 15],
  }),
  // Icono numerado para paradas de recogida (círculo amarillo con número)
  recogida: (numero) => L.divIcon({
    className: '',
    html: `<div style="width:30px;height:30px;background:#d69e2e;border:2.5px solid #fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.3);color:#fff;font-weight:700;font-size:13px;">${numero}</div>`,
    iconSize: [30, 30], iconAnchor: [15, 15],
  }),
};

// ── Utilidades ─────────────────────────────────────────────────────────────────

/**
 * Muestra una notificación flotante (toast) en la esquina inferior derecha.
 * @param {string} mensaje - Texto a mostrar.
 * @param {string} tipo - Clase CSS: 'success', 'error' o '' (neutro).
 */
function notificacion(mensaje, tipo = '') {
  const elemento = document.createElement('div');
  elemento.className = `toast ${tipo}`;
  elemento.textContent = mensaje;
  document.getElementById('toast-container').appendChild(elemento);
  // Eliminar el toast automáticamente después de 3,5 segundos
  setTimeout(() => elemento.remove(), 3500);
}

/**
 * Realiza una petición HTTP a la API incluyendo el token de autenticación.
 * @param {string} ruta - Ruta relativa del endpoint (ej: '/auth/login').
 * @param {object} opciones - Opciones de fetch (method, body, headers...).
 * @returns {Promise<any>} - Datos JSON de la respuesta.
 * @throws {Error} - Si la respuesta no es exitosa (status >= 400).
 */
async function peticionApi(ruta, opciones = {}) {
  const cabeceras = {
    'Content-Type': 'application/json',
    ...(opciones.headers || {}),
  };
  // Añadir token de autenticación si el usuario está autenticado
  if (estadoApp.token) {
    cabeceras['Authorization'] = `Bearer ${estadoApp.token}`;
  }
  const respuesta = await fetch(URL_API + ruta, { ...opciones, headers: cabeceras });
  const datos = await respuesta.json();
  if (!respuesta.ok) throw new Error(datos.detail || 'Error en la petición');
  return datos;
}

// ── Autenticación ──────────────────────────────────────────────────────────────

// Manejar el envío del formulario de login
document.getElementById('login-form').addEventListener('submit', async (evento) => {
  evento.preventDefault();
  const nombreUsuario = document.getElementById('username').value.trim();
  const contrasena = document.getElementById('password').value;
  const elementoError = document.getElementById('login-error');
  elementoError.textContent = '';

  try {
    const datos = await peticionApi('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username: nombreUsuario, password: contrasena }),
    });
    estadoApp.token = datos.token;
    estadoApp.usuario = datos.user;
    iniciarApp();
  } catch (error) {
    elementoError.textContent = error.message;
  }
});

// Manejar el botón de cierre de sesión
document.getElementById('btn-logout').addEventListener('click', () => {
  if (estadoApp.ws) estadoApp.ws.close();
  // Resetear el estado de la aplicación
  estadoApp = { ...estadoApp, token: null, usuario: null, ws: null };
  document.getElementById('app-screen').style.display = 'none';
  document.getElementById('login-screen').style.display = 'flex';
});

// ── Arranque de la aplicación ──────────────────────────────────────────────────

/**
 * Inicializa la aplicación después del login exitoso.
 * Muestra la pantalla principal, inicializa el mapa y carga la vista
 * correspondiente según el rol del usuario (central o repartidor).
 */
function iniciarApp() {
  document.getElementById('login-screen').style.display = 'none';
  const pantallaApp = document.getElementById('app-screen');
  pantallaApp.style.display = 'flex';

  // Mostrar el nombre y rol del usuario en la barra de navegación
  document.getElementById('nav-user').textContent =
    `${estadoApp.usuario.name} (${estadoApp.usuario.role === 'central' ? 'Central' : 'Repartidor'})`;

  inicializarMapa();
  conectarWebSocket();

  // Cargar la vista según el tipo de usuario
  if (estadoApp.usuario.role === 'central') {
    cargarVistaCentral();
  } else {
    cargarVistaRepartidor();
  }
}

// ── Mapa Leaflet ───────────────────────────────────────────────────────────────

/**
 * Inicializa el mapa Leaflet centrado en Madrid con capa de OpenStreetMap.
 * Si ya había un mapa, lo elimina primero para evitar duplicados.
 */
function inicializarMapa() {
  if (estadoApp.mapa) {
    estadoApp.mapa.remove();
    estadoApp.mapa = null;
  }
  estadoApp.mapa = L.map('map').setView([40.4168, -3.7038], 13);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© <a href="https://openstreetmap.org">OpenStreetMap</a>',
    maxZoom: 19,
  }).addTo(estadoApp.mapa);
}

/**
 * Elimina todos los marcadores de paradas y la línea de ruta del mapa.
 */
function limpiarParadasMapa() {
  estadoApp.marcadoresParadas.forEach(marcador => estadoApp.mapa.removeLayer(marcador));
  estadoApp.marcadoresParadas = [];
  if (estadoApp.lineaRuta) {
    estadoApp.mapa.removeLayer(estadoApp.lineaRuta);
    estadoApp.lineaRuta = null;
  }
}

/**
 * Renderiza en el mapa los marcadores numerados de cada parada activa
 * y dibuja una línea discontinua conectándolos en orden.
 * @param {Array} pedidos - Lista de pedidos a visualizar.
 */
function renderizarRuta(pedidos) {
  limpiarParadasMapa();
  if (!pedidos || pedidos.length === 0) return;

  // Solo mostrar paradas no completadas ni rechazadas
  const paradasActivas = pedidos.filter(
    pedido => !['completed', 'rejected'].includes(pedido.status)
  );
  const coordenadas = [];

  paradasActivas.forEach((pedido, indice) => {
    const icono = pedido.type === 'pickup'
      ? iconos.recogida(indice + 1)
      : iconos.entrega(indice + 1);
    const marcador = L.marker([pedido.lat, pedido.lng], { icon: icono })
      .bindPopup(
        `<b>${pedido.type === 'pickup' ? '📦 Recogida' : '📬 Entrega'}</b><br>${pedido.address}`
      )
      .addTo(estadoApp.mapa);
    estadoApp.marcadoresParadas.push(marcador);
    coordenadas.push([pedido.lat, pedido.lng]);
  });

  // Dibujar la línea de ruta si hay más de una parada
  if (coordenadas.length > 1) {
    estadoApp.lineaRuta = L.polyline(coordenadas, {
      color: '#2b6cb0', weight: 4, dashArray: '8 6', opacity: .8,
    }).addTo(estadoApp.mapa);
  }

  // Ajustar el zoom para mostrar todas las paradas
  if (coordenadas.length > 0) {
    estadoApp.mapa.fitBounds(L.latLngBounds(coordenadas).pad(0.15));
  }
}

// ── WebSocket ──────────────────────────────────────────────────────────────────

/**
 * Establece la conexión WebSocket con el servidor.
 * Reconecta automáticamente cada 3 segundos si se pierde la conexión.
 * Los repartidores inician el envío de ubicación al conectarse.
 */
function conectarWebSocket() {
  const ws = new WebSocket(`${URL_WS}?token=${estadoApp.token}`);
  estadoApp.ws = ws;

  ws.onmessage = (evento) => {
    const mensaje = JSON.parse(evento.data);
    manejarMensajeWs(mensaje);
  };

  ws.onclose = () => {
    // Reconectar automáticamente si el usuario sigue autenticado
    if (estadoApp.token) setTimeout(conectarWebSocket, 3000);
  };

  // Los repartidores empiezan a emitir su ubicación nada más conectarse
  if (estadoApp.usuario.role === 'repartidor') {
    ws.onopen = () => iniciarEmisionUbicacion(ws);
  }
}

/**
 * Despacha los mensajes WebSocket recibidos al manejador correspondiente.
 * @param {object} mensaje - Objeto JSON recibido del servidor.
 */
function manejarMensajeWs(mensaje) {
  switch (mensaje.type) {
    case 'driver:location:update':
      // Un repartidor ha actualizado su posición → actualizar marcador en el mapa
      actualizarMarcadorRepartidor(mensaje);
      break;
    case 'driver:offline':
      // Un repartidor se ha desconectado → eliminar su marcador
      eliminarMarcadorRepartidor(mensaje.driver_id);
      break;
    case 'pickup:notification':
      // La central ha asignado una recogida a este repartidor
      mostrarModalRecogida(mensaje.order, mensaje.extra_minutes);
      break;
    case 'pickup:response':
      // Un repartidor ha respondido a una notificación de recogida (vista central)
      alResponderRecogida(mensaje);
      break;
  }
}

// ── Emisión de ubicación del repartidor ────────────────────────────────────────

/**
 * Inicia el envío periódico de la ubicación GPS del repartidor al servidor.
 * Si el navegador soporta geolocalización, usa la API nativa.
 * Si no, simula un movimiento circular alrededor de Madrid para demo.
 * @param {WebSocket} ws - Conexión WebSocket activa.
 */
function iniciarEmisionUbicacion(ws) {
  /**
   * Envía la posición actual al servidor a través del WebSocket.
   * @param {GeolocationPosition} posicion - Posición GPS del navegador.
   */
  function enviarPosicion(posicion) {
    if (ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify({
      type: 'driver:location',
      lat: posicion.coords.latitude,
      lng: posicion.coords.longitude,
      heading: posicion.coords.heading || 0,
    }));
  }

  if (navigator.geolocation) {
    // Usar geolocalización real del dispositivo
    navigator.geolocation.watchPosition(enviarPosicion, () => {}, {
      enableHighAccuracy: true,
    });
  } else {
    // Modo demo: simular movimiento circular en Madrid
    let angulo = 0;
    const centroMadrid = [40.4168, -3.7038];
    setInterval(() => {
      angulo += 0.02;
      const lat = centroMadrid[0] + 0.005 * Math.sin(angulo);
      const lng = centroMadrid[1] + 0.005 * Math.cos(angulo);
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({
          type: 'driver:location',
          lat,
          lng,
          heading: (angulo * 57.3) % 360,
        }));
      }
    }, 3000);
  }
}

// ── Vista de la central ────────────────────────────────────────────────────────

/**
 * Carga la vista del operador central: lista de repartidores y pedidos pendientes.
 * Renderiza los marcadores de todos los repartidores en el mapa.
 */
async function cargarVistaCentral() {
  try {
    const [datosRepartidores, datosPedidos] = await Promise.all([
      peticionApi('/drivers/'),
      peticionApi('/orders/'),
    ]);
    estadoApp.repartidores = datosRepartidores;
    estadoApp.pedidos = datosPedidos;
    renderizarBarraLateralCentral();
    renderizarMarcadoresTodosRepartidores();
  } catch (error) {
    notificacion(error.message, 'error');
  }
}

/**
 * Renderiza el panel lateral de la central con:
 * - Tarjetas de cada repartidor (clic para ver su ruta)
 * - Sección de recogidas pendientes de asignación
 */
function renderizarBarraLateralCentral() {
  const cuerpoBarraLateral = document.getElementById('sidebar-body');
  cuerpoBarraLateral.innerHTML = '';

  // ── Sección de repartidores ────────────────────────────────────────────────
  const seccionRepartidores = document.createElement('div');
  seccionRepartidores.innerHTML =
    '<p style="font-size:.8rem;font-weight:700;color:#4a5568;text-transform:uppercase;letter-spacing:.05em;margin-bottom:.5rem;">Repartidores</p>';

  estadoApp.repartidores.forEach(repartidor => {
    const tarjeta = document.createElement('div');
    const estaSeleccionado = repartidor.id === estadoApp.idRepartidorSeleccionado;
    tarjeta.className = `driver-card${estaSeleccionado ? ' selected' : ''}`;
    tarjeta.innerHTML = `
      <div class="driver-name">🚐 ${repartidor.name}</div>
      <div class="driver-status">${
        repartidor.lat != null
          ? `📍 ${repartidor.lat.toFixed(4)}, ${repartidor.lng.toFixed(4)}`
          : 'Sin ubicación'
      }</div>
    `;
    tarjeta.onclick = () => seleccionarRepartidor(repartidor.id);
    seccionRepartidores.appendChild(tarjeta);
  });
  cuerpoBarraLateral.appendChild(seccionRepartidores);

  // ── Sección de recogidas pendientes ───────────────────────────────────────
  const recogidasPendientes = estadoApp.pedidos.filter(
    pedido => pedido.status === 'pending' && pedido.type === 'pickup'
  );
  if (recogidasPendientes.length > 0) {
    const seccionPendientes = document.createElement('div');
    seccionPendientes.className = 'pending-section';
    seccionPendientes.innerHTML = '<h4>⚠️ Recogidas pendientes de asignación</h4>';

    recogidasPendientes.forEach(pedido => {
      const elemento = document.createElement('div');
      elemento.className = 'stop-item';
      elemento.innerHTML = `
        <div class="stop-number pickup">📦</div>
        <div class="stop-info">
          <div class="stop-address">${pedido.address}</div>
          <select id="selector-rep-${pedido.id}" style="margin-top:.4rem;font-size:.8rem;padding:.2rem .4rem;border-radius:4px;border:1px solid #e2e8f0;width:100%;">
            <option value="">-- Seleccionar repartidor --</option>
            ${estadoApp.repartidores.map(
              rep => `<option value="${rep.id}">${rep.name}</option>`
            ).join('')}
          </select>
          <button class="assign-btn" onclick="asignarRecogida('${pedido.id}')">Asignar</button>
        </div>
      `;
      seccionPendientes.appendChild(elemento);
    });
    cuerpoBarraLateral.appendChild(seccionPendientes);
  }
}

/**
 * Selecciona un repartidor en la vista central y muestra su ruta en el mapa.
 * Los demás marcadores se atenúan para destacar el seleccionado.
 * @param {string} idRepartidor - ID del repartidor a seleccionar.
 */
async function seleccionarRepartidor(idRepartidor) {
  estadoApp.idRepartidorSeleccionado = idRepartidor;
  try {
    const datos = await peticionApi(`/orders/route/${idRepartidor}`);
    renderizarRuta(datos.orders);
    renderizarBarraLateralCentral();
    // Resaltar el marcador del repartidor seleccionado y atenuar los demás
    Object.entries(estadoApp.marcadoresRepartidores).forEach(([id, marcador]) => {
      marcador.setOpacity(id === idRepartidor ? 1 : 0.4);
    });
  } catch {
    notificacion('No se encontró ruta activa para este repartidor', 'error');
  }
}

/**
 * Asigna una recogida pendiente al repartidor seleccionado en el desplegable.
 * Notifica al repartidor a través del WebSocket y recarga la vista.
 * @param {string} idPedido - ID de la recogida a asignar.
 */
async function asignarRecogida(idPedido) {
  const selector = document.getElementById(`selector-rep-${idPedido}`);
  const idRepartidor = selector?.value;
  if (!idRepartidor) {
    notificacion('Selecciona un repartidor primero', 'error');
    return;
  }

  try {
    const datos = await peticionApi(`/orders/${idPedido}/assign`, {
      method: 'POST',
      body: JSON.stringify({ driver_id: idRepartidor }),
    });
    notificacion(`Recogida asignada (+${datos.extra_minutes} min)`, 'success');

    // Notificar al repartidor a través del WebSocket para que reciba el modal
    if (estadoApp.ws && estadoApp.ws.readyState === WebSocket.OPEN) {
      estadoApp.ws.send(JSON.stringify({
        type: 'central:pickup:notify',
        order_id: idPedido,
        driver_id: idRepartidor,
      }));
    }
    cargarVistaCentral();
  } catch (error) {
    notificacion(error.message, 'error');
  }
}

/**
 * Coloca los marcadores de todos los repartidores conocidos en el mapa.
 * Ajusta el zoom para que todos sean visibles.
 */
function renderizarMarcadoresTodosRepartidores() {
  // Eliminar marcadores existentes
  Object.values(estadoApp.marcadoresRepartidores).forEach(
    marcador => estadoApp.mapa.removeLayer(marcador)
  );
  estadoApp.marcadoresRepartidores = {};

  estadoApp.repartidores.forEach(repartidor => {
    if (repartidor.lat == null) return;
    const marcador = L.marker([repartidor.lat, repartidor.lng], {
      icon: iconos.repartidor,
    })
      .bindPopup(`<b>${repartidor.name}</b>`)
      .addTo(estadoApp.mapa);
    estadoApp.marcadoresRepartidores[repartidor.id] = marcador;
  });

  // Ajustar el zoom para mostrar a todos los repartidores
  const todasLasPosiciones = estadoApp.repartidores
    .filter(rep => rep.lat != null)
    .map(rep => [rep.lat, rep.lng]);
  if (todasLasPosiciones.length > 0) {
    estadoApp.mapa.fitBounds(L.latLngBounds(todasLasPosiciones).pad(0.2));
  }
}

/**
 * Actualiza o crea el marcador de un repartidor en el mapa con su nueva posición.
 * @param {object} mensaje - Mensaje WebSocket con driver_id, name, lat, lng.
 */
function actualizarMarcadorRepartidor(mensaje) {
  const { driver_id, name, lat, lng } = mensaje;
  if (estadoApp.marcadoresRepartidores[driver_id]) {
    // Repartidor ya conocido → mover su marcador
    estadoApp.marcadoresRepartidores[driver_id].setLatLng([lat, lng]);
  } else {
    // Nuevo repartidor conectado → crear marcador
    const marcador = L.marker([lat, lng], { icon: iconos.repartidor })
      .bindPopup(`<b>${name}</b>`)
      .addTo(estadoApp.mapa);
    estadoApp.marcadoresRepartidores[driver_id] = marcador;
  }
  // Actualizar las coordenadas en el estado local
  const repartidor = estadoApp.repartidores.find(rep => rep.id === driver_id);
  if (repartidor) { repartidor.lat = lat; repartidor.lng = lng; }
}

/**
 * Elimina el marcador de un repartidor desconectado y muestra una notificación.
 * @param {string} idRepartidor - ID del repartidor que se desconectó.
 */
function eliminarMarcadorRepartidor(idRepartidor) {
  if (estadoApp.marcadoresRepartidores[idRepartidor]) {
    estadoApp.mapa.removeLayer(estadoApp.marcadoresRepartidores[idRepartidor]);
    delete estadoApp.marcadoresRepartidores[idRepartidor];
  }
  notificacion('Repartidor desconectado', 'error');
}

/**
 * Maneja la respuesta de un repartidor a una notificación de recogida (vista central).
 * Muestra el resultado y recarga la vista.
 * @param {object} mensaje - Mensaje WebSocket con driver_name y accepted.
 */
function alResponderRecogida(mensaje) {
  const icono = mensaje.accepted ? '✅' : '❌';
  notificacion(
    `${icono} ${mensaje.driver_name} ${mensaje.accepted ? 'aceptó' : 'rechazó'} la recogida`,
    mensaje.accepted ? 'success' : ''
  );
  cargarVistaCentral();
}

// ── Vista del repartidor ───────────────────────────────────────────────────────

/**
 * Carga la vista del repartidor: obtiene su ruta activa y renderiza el mapa
 * y la barra lateral con la lista de paradas.
 */
async function cargarVistaRepartidor() {
  try {
    const datos = await peticionApi(`/orders/route/${estadoApp.usuario.id}`);
    estadoApp.pedidos = datos.orders;
    renderizarRuta(datos.orders);
    renderizarBarraLateralRepartidor(datos.orders);
  } catch (error) {
    notificacion('No se encontró ruta activa', 'error');
  }
}

/**
 * Renderiza el panel lateral del repartidor con la lista ordenada de paradas.
 * Cada parada muestra la dirección, tipo, estado y un botón para completarla.
 * @param {Array} pedidos - Lista de pedidos de la ruta activa.
 */
function renderizarBarraLateralRepartidor(pedidos) {
  const cuerpoBarraLateral = document.getElementById('sidebar-body');
  cuerpoBarraLateral.innerHTML = '';

  if (!pedidos || pedidos.length === 0) {
    cuerpoBarraLateral.innerHTML =
      '<p style="color:#718096;font-size:.9rem;text-align:center;padding:2rem 0;">No hay paradas en tu ruta</p>';
    return;
  }

  pedidos.forEach((pedido, indice) => {
    const estaCompletado = pedido.status === 'completed';
    const elemento = document.createElement('div');
    elemento.className = 'stop-item';
    elemento.innerHTML = `
      <div class="stop-number ${pedido.type === 'pickup' ? 'pickup' : ''} ${estaCompletado ? 'completed' : ''}">${indice + 1}</div>
      <div class="stop-info">
        <div class="stop-address">${pedido.address}</div>
        <div class="stop-meta">
          <span class="badge badge-${pedido.type}">${pedido.type === 'pickup' ? '📦 Recogida' : '📬 Entrega'}</span>
          <span class="badge badge-${claseEstado(pedido.status)}">${etiquetaEstado(pedido.status)}</span>
        </div>
        ${!estaCompletado && pedido.status !== 'rejected'
          ? `<button class="assign-btn" onclick="marcarCompletado('${pedido.id}')">✔ Completar</button>`
          : ''}
      </div>
    `;
    // Al hacer clic en la parada, centrar el mapa en ella
    elemento.onclick = (evento) => {
      if (evento.target.tagName === 'BUTTON') return;
      estadoApp.mapa.setView([pedido.lat, pedido.lng], 15);
    };
    cuerpoBarraLateral.appendChild(elemento);
  });
}

/**
 * Marca una parada como completada y recarga la vista del repartidor.
 * @param {string} idPedido - ID del pedido a marcar como completado.
 */
async function marcarCompletado(idPedido) {
  try {
    await peticionApi(`/orders/${idPedido}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status: 'completed' }),
    });
    notificacion('Parada completada ✔', 'success');
    cargarVistaRepartidor();
  } catch (error) {
    notificacion(error.message, 'error');
  }
}

// ── Modal de notificación de recogida ──────────────────────────────────────────

/**
 * Muestra el modal de notificación con los detalles de la nueva recogida
 * y el tiempo extra estimado que supondría aceptarla.
 * @param {object} pedido - Objeto del pedido con address, lat, lng, etc.
 * @param {number} minutosExtra - Tiempo adicional estimado en minutos.
 */
function mostrarModalRecogida(pedido, minutosExtra) {
  estadoApp.notificacionPendiente = { pedido, minutosExtra };
  const modal = document.getElementById('pickup-modal');
  document.getElementById('modal-address').textContent = pedido.address;
  document.getElementById('modal-extra-time').innerHTML =
    `Esta recogida añade aproximadamente <strong>${minutosExtra} minutos</strong> a tu ruta.`;
  modal.classList.remove('hidden');
}

// Botón "Aceptar" del modal de recogida
document.getElementById('btn-accept-pickup').addEventListener('click', async () => {
  if (!estadoApp.notificacionPendiente) return;
  const { pedido } = estadoApp.notificacionPendiente;
  try {
    await peticionApi(`/orders/${pedido.id}/respond`, {
      method: 'POST',
      body: JSON.stringify({ accepted: true }),
    });
    // Notificar a la central a través del WebSocket
    if (estadoApp.ws?.readyState === WebSocket.OPEN) {
      estadoApp.ws.send(JSON.stringify({
        type: 'driver:pickup:response',
        order_id: pedido.id,
        accepted: true,
      }));
    }
    notificacion('Recogida aceptada ✅', 'success');
    document.getElementById('pickup-modal').classList.add('hidden');
    estadoApp.notificacionPendiente = null;
    cargarVistaRepartidor();   // Recargar la ruta con la nueva parada añadida
  } catch (error) {
    notificacion(error.message, 'error');
  }
});

// Botón "Rechazar" del modal de recogida
document.getElementById('btn-reject-pickup').addEventListener('click', async () => {
  if (!estadoApp.notificacionPendiente) return;
  const { pedido } = estadoApp.notificacionPendiente;
  try {
    await peticionApi(`/orders/${pedido.id}/respond`, {
      method: 'POST',
      body: JSON.stringify({ accepted: false }),
    });
    // Notificar a la central del rechazo
    if (estadoApp.ws?.readyState === WebSocket.OPEN) {
      estadoApp.ws.send(JSON.stringify({
        type: 'driver:pickup:response',
        order_id: pedido.id,
        accepted: false,
      }));
    }
    notificacion('Recogida rechazada', '');
    document.getElementById('pickup-modal').classList.add('hidden');
    estadoApp.notificacionPendiente = null;
  } catch (error) {
    notificacion(error.message, 'error');
  }
});

// ── Funciones auxiliares ───────────────────────────────────────────────────────

/**
 * Devuelve la clase CSS correspondiente al estado de un pedido.
 * Usado para colorear los badges de estado en la barra lateral.
 * @param {string} estado - Estado del pedido.
 * @returns {string} - Clase CSS (sin prefijo 'badge-').
 */
function claseEstado(estado) {
  const mapa = {
    pending: 'pending',
    assigned: 'assigned',
    in_progress: 'progress',
    completed: 'completed',
    rejected: 'completed',
  };
  return mapa[estado] || 'pending';
}

/**
 * Devuelve la etiqueta en español para el estado de un pedido.
 * @param {string} estado - Estado del pedido (en inglés).
 * @returns {string} - Etiqueta traducida al español.
 */
function etiquetaEstado(estado) {
  const mapa = {
    pending: 'Pendiente',
    assigned: 'Asignado',
    in_progress: 'En curso',
    completed: 'Completado',
    rejected: 'Rechazado',
  };
  return mapa[estado] || estado;
}
