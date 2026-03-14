/**
 * PAE – Delivery Route Manager
 * Vanilla-JS SPA frontend
 */

const API = '';          // same origin
const WS_URL = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`;

// ── State ─────────────────────────────────────────────────────────────────────
let state = {
  token: null,
  user: null,
  ws: null,
  map: null,
  driverMarkers: {},   // driver_id -> L.Marker
  stopMarkers: [],     // L.Marker[]
  routeLine: null,     // L.Polyline
  orders: [],
  drivers: [],
  selectedDriverId: null,
  pendingNotification: null,   // { order, extra_minutes }
};

// ── Icons ─────────────────────────────────────────────────────────────────────
const icons = {
  driver: L.divIcon({
    className: '',
    html: '<div style="width:34px;height:34px;background:#2b6cb0;border:3px solid #fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,.35);font-size:18px;">🚐</div>',
    iconSize: [34, 34], iconAnchor: [17, 17],
  }),
  delivery: (n) => L.divIcon({
    className: '',
    html: `<div style="width:30px;height:30px;background:#2b6cb0;border:2.5px solid #fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.3);color:#fff;font-weight:700;font-size:13px;">${n}</div>`,
    iconSize: [30, 30], iconAnchor: [15, 15],
  }),
  pickup: (n) => L.divIcon({
    className: '',
    html: `<div style="width:30px;height:30px;background:#d69e2e;border:2.5px solid #fff;border-radius:50%;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.3);color:#fff;font-weight:700;font-size:13px;">${n}</div>`,
    iconSize: [30, 30], iconAnchor: [15, 15],
  }),
};

// ── Utility ───────────────────────────────────────────────────────────────────
function toast(msg, type = '') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  document.getElementById('toast-container').appendChild(el);
  setTimeout(() => el.remove(), 3500);
}

async function apiFetch(path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  if (state.token) headers['Authorization'] = `Bearer ${state.token}`;
  const res = await fetch(API + path, { ...opts, headers });
  const data = await res.json();
  if (!res.ok) throw new Error(data.detail || 'Request failed');
  return data;
}

// ── Auth ──────────────────────────────────────────────────────────────────────
document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const username = document.getElementById('username').value.trim();
  const password = document.getElementById('password').value;
  const errEl = document.getElementById('login-error');
  errEl.textContent = '';

  try {
    const data = await apiFetch('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    });
    state.token = data.token;
    state.user = data.user;
    startApp();
  } catch (err) {
    errEl.textContent = err.message;
  }
});

document.getElementById('btn-logout').addEventListener('click', () => {
  if (state.ws) state.ws.close();
  state = { ...state, token: null, user: null, ws: null };
  document.getElementById('app-screen').style.display = 'none';
  document.getElementById('login-screen').style.display = 'flex';
});

// ── App bootstrap ─────────────────────────────────────────────────────────────
function startApp() {
  document.getElementById('login-screen').style.display = 'none';
  const appEl = document.getElementById('app-screen');
  appEl.style.display = 'flex';

  document.getElementById('nav-user').textContent =
    `${state.user.name} (${state.user.role === 'central' ? 'Central' : 'Repartidor'})`;

  initMap();
  connectWebSocket();

  if (state.user.role === 'central') {
    loadCentralView();
  } else {
    loadDriverView();
  }
}

// ── Map ───────────────────────────────────────────────────────────────────────
function initMap() {
  if (state.map) { state.map.remove(); state.map = null; }
  state.map = L.map('map').setView([40.4168, -3.7038], 13);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© <a href="https://openstreetmap.org">OpenStreetMap</a>',
    maxZoom: 19,
  }).addTo(state.map);
}

function clearMapStops() {
  state.stopMarkers.forEach(m => state.map.removeLayer(m));
  state.stopMarkers = [];
  if (state.routeLine) { state.map.removeLayer(state.routeLine); state.routeLine = null; }
}

function renderRoute(orders) {
  clearMapStops();
  if (!orders || orders.length === 0) return;

  const active = orders.filter(o => !['completed', 'rejected'].includes(o.status));
  const latlngs = [];

  active.forEach((o, i) => {
    const icon = o.type === 'pickup' ? icons.pickup(i + 1) : icons.delivery(i + 1);
    const marker = L.marker([o.lat, o.lng], { icon })
      .bindPopup(`<b>${o.type === 'pickup' ? '📦 Recogida' : '📬 Entrega'}</b><br>${o.address}`)
      .addTo(state.map);
    state.stopMarkers.push(marker);
    latlngs.push([o.lat, o.lng]);
  });

  if (latlngs.length > 1) {
    state.routeLine = L.polyline(latlngs, {
      color: '#2b6cb0', weight: 4, dashArray: '8 6', opacity: .8,
    }).addTo(state.map);
  }

  if (latlngs.length > 0) {
    state.map.fitBounds(L.latLngBounds(latlngs).pad(0.15));
  }
}

// ── WebSocket ─────────────────────────────────────────────────────────────────
function connectWebSocket() {
  const ws = new WebSocket(`${WS_URL}?token=${state.token}`);
  state.ws = ws;

  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    handleWsMessage(msg);
  };

  ws.onclose = () => {
    // Reconnect after 3 s unless logged out
    if (state.token) setTimeout(connectWebSocket, 3000);
  };

  // If driver: start sending location
  if (state.user.role === 'repartidor') {
    ws.onopen = () => startLocationBroadcast(ws);
  }
}

function handleWsMessage(msg) {
  switch (msg.type) {
    case 'driver:location:update':
      updateDriverMarker(msg);
      break;
    case 'driver:offline':
      removeDriverMarker(msg.driver_id);
      break;
    case 'pickup:notification':
      showPickupModal(msg.order, msg.extra_minutes);
      break;
    case 'pickup:response':
      onPickupResponse(msg);
      break;
  }
}

// ── Driver location broadcast ─────────────────────────────────────────────────
function startLocationBroadcast(ws) {
  function send(pos) {
    if (ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify({
      type: 'driver:location',
      lat: pos.coords.latitude,
      lng: pos.coords.longitude,
      heading: pos.coords.heading || 0,
    }));
  }

  if (navigator.geolocation) {
    navigator.geolocation.watchPosition(send, () => {}, { enableHighAccuracy: true });
  } else {
    // Simulate movement around Madrid for demo
    let angle = 0;
    const center = [40.4168, -3.7038];
    setInterval(() => {
      angle += 0.02;
      const lat = center[0] + 0.005 * Math.sin(angle);
      const lng = center[1] + 0.005 * Math.cos(angle);
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'driver:location', lat, lng, heading: (angle * 57.3) % 360 }));
      }
    }, 3000);
  }
}

// ── Central view ──────────────────────────────────────────────────────────────
async function loadCentralView() {
  try {
    const [driversData, ordersData] = await Promise.all([
      apiFetch('/drivers/'),
      apiFetch('/orders/'),
    ]);
    state.drivers = driversData;
    state.orders = ordersData;
    renderCentralSidebar();
    renderAllDriverMarkers();
  } catch (err) {
    toast(err.message, 'error');
  }
}

function renderCentralSidebar() {
  const body = document.getElementById('sidebar-body');
  body.innerHTML = '';

  // Driver cards
  const driverSection = document.createElement('div');
  driverSection.innerHTML = '<p style="font-size:.8rem;font-weight:700;color:#4a5568;text-transform:uppercase;letter-spacing:.05em;margin-bottom:.5rem;">Repartidores</p>';
  state.drivers.forEach(d => {
    const card = document.createElement('div');
    card.className = `driver-card${d.id === state.selectedDriverId ? ' selected' : ''}`;
    card.innerHTML = `
      <div class="driver-name">🚐 ${d.name}</div>
      <div class="driver-status">${d.lat != null ? `📍 ${d.lat.toFixed(4)}, ${d.lng.toFixed(4)}` : 'Sin ubicación'}</div>
    `;
    card.onclick = () => selectDriver(d.id);
    driverSection.appendChild(card);
  });
  body.appendChild(driverSection);

  // Pending pickups
  const pending = state.orders.filter(o => o.status === 'pending' && o.type === 'pickup');
  if (pending.length > 0) {
    const section = document.createElement('div');
    section.className = 'pending-section';
    section.innerHTML = '<h4>⚠️ Recogidas pendientes de asignación</h4>';
    pending.forEach(o => {
      const item = document.createElement('div');
      item.className = 'stop-item';
      item.innerHTML = `
        <div class="stop-number pickup">📦</div>
        <div class="stop-info">
          <div class="stop-address">${o.address}</div>
          <select id="assign-driver-${o.id}" style="margin-top:.4rem;font-size:.8rem;padding:.2rem .4rem;border-radius:4px;border:1px solid #e2e8f0;width:100%;">
            <option value="">-- Seleccionar repartidor --</option>
            ${state.drivers.map(d => `<option value="${d.id}">${d.name}</option>`).join('')}
          </select>
          <button class="assign-btn" onclick="assignPickup('${o.id}')">Asignar</button>
        </div>
      `;
      section.appendChild(item);
    });
    body.appendChild(section);
  }
}

async function selectDriver(driverId) {
  state.selectedDriverId = driverId;
  try {
    const data = await apiFetch(`/orders/route/${driverId}`);
    renderRoute(data.orders);
    renderCentralSidebar();
    // Highlight driver marker
    Object.entries(state.driverMarkers).forEach(([id, m]) => {
      m.setOpacity(id === driverId ? 1 : 0.4);
    });
  } catch {
    toast('No se encontró ruta activa para este repartidor', 'error');
  }
}

async function assignPickup(orderId) {
  const select = document.getElementById(`assign-driver-${orderId}`);
  const driverId = select?.value;
  if (!driverId) { toast('Selecciona un repartidor', 'error'); return; }

  try {
    const data = await apiFetch(`/orders/${orderId}/assign`, {
      method: 'POST',
      body: JSON.stringify({ driver_id: driverId }),
    });
    toast(`Recogida asignada (+${data.extra_minutes} min)`, 'success');

    // Notify driver via WebSocket
    if (state.ws && state.ws.readyState === WebSocket.OPEN) {
      state.ws.send(JSON.stringify({
        type: 'central:pickup:notify',
        order_id: orderId,
        driver_id: driverId,
      }));
    }
    loadCentralView();
  } catch (err) {
    toast(err.message, 'error');
  }
}

function renderAllDriverMarkers() {
  // Clear existing
  Object.values(state.driverMarkers).forEach(m => state.map.removeLayer(m));
  state.driverMarkers = {};

  state.drivers.forEach(d => {
    if (d.lat == null) return;
    const marker = L.marker([d.lat, d.lng], { icon: icons.driver })
      .bindPopup(`<b>${d.name}</b>`)
      .addTo(state.map);
    state.driverMarkers[d.id] = marker;
  });

  const allPos = state.drivers.filter(d => d.lat != null).map(d => [d.lat, d.lng]);
  if (allPos.length > 0) state.map.fitBounds(L.latLngBounds(allPos).pad(0.2));
}

function updateDriverMarker(msg) {
  const { driver_id, name, lat, lng } = msg;
  if (state.driverMarkers[driver_id]) {
    state.driverMarkers[driver_id].setLatLng([lat, lng]);
  } else {
    const marker = L.marker([lat, lng], { icon: icons.driver })
      .bindPopup(`<b>${name}</b>`)
      .addTo(state.map);
    state.driverMarkers[driver_id] = marker;
  }
  // Update in state
  const d = state.drivers.find(x => x.id === driver_id);
  if (d) { d.lat = lat; d.lng = lng; }
}

function removeDriverMarker(driverId) {
  if (state.driverMarkers[driverId]) {
    state.map.removeLayer(state.driverMarkers[driverId]);
    delete state.driverMarkers[driverId];
  }
  toast(`Repartidor desconectado`, 'error');
}

function onPickupResponse(msg) {
  const icon = msg.accepted ? '✅' : '❌';
  toast(`${icon} ${msg.driver_name} ${msg.accepted ? 'aceptó' : 'rechazó'} la recogida`, msg.accepted ? 'success' : '');
  loadCentralView();
}

// ── Driver view ───────────────────────────────────────────────────────────────
async function loadDriverView() {
  try {
    const data = await apiFetch(`/orders/route/${state.user.id}`);
    state.orders = data.orders;
    renderRoute(data.orders);
    renderDriverSidebar(data.orders);
  } catch (err) {
    toast('No se encontró ruta activa', 'error');
  }
}

function renderDriverSidebar(orders) {
  const body = document.getElementById('sidebar-body');
  body.innerHTML = '';

  if (!orders || orders.length === 0) {
    body.innerHTML = '<p style="color:#718096;font-size:.9rem;text-align:center;padding:2rem 0;">No hay paradas en tu ruta</p>';
    return;
  }

  orders.forEach((o, i) => {
    const isCompleted = o.status === 'completed';
    const item = document.createElement('div');
    item.className = `stop-item${isCompleted ? '' : ''}`;
    item.innerHTML = `
      <div class="stop-number ${o.type === 'pickup' ? 'pickup' : ''} ${isCompleted ? 'completed' : ''}">${i + 1}</div>
      <div class="stop-info">
        <div class="stop-address">${o.address}</div>
        <div class="stop-meta">
          <span class="badge badge-${o.type}">${o.type === 'pickup' ? '📦 Recogida' : '📬 Entrega'}</span>
          <span class="badge badge-${statusClass(o.status)}">${statusLabel(o.status)}</span>
        </div>
        ${!isCompleted && o.status !== 'rejected' ? `<button class="assign-btn" onclick="markComplete('${o.id}')">✔ Completar</button>` : ''}
      </div>
    `;
    item.onclick = (e) => {
      if (e.target.tagName === 'BUTTON') return;
      state.map.setView([o.lat, o.lng], 15);
    };
    body.appendChild(item);
  });
}

async function markComplete(orderId) {
  try {
    await apiFetch(`/orders/${orderId}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status: 'completed' }),
    });
    toast('Parada completada ✔', 'success');
    loadDriverView();
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ── Pickup notification modal ─────────────────────────────────────────────────
function showPickupModal(order, extraMinutes) {
  state.pendingNotification = { order, extraMinutes };
  const modal = document.getElementById('pickup-modal');
  document.getElementById('modal-address').textContent = order.address;
  document.getElementById('modal-extra-time').innerHTML =
    `Esta recogida añade aproximadamente <strong>${extraMinutes} minutos</strong> a tu ruta.`;
  modal.classList.remove('hidden');
}

document.getElementById('btn-accept-pickup').addEventListener('click', async () => {
  if (!state.pendingNotification) return;
  const { order } = state.pendingNotification;
  try {
    await apiFetch(`/orders/${order.id}/respond`, {
      method: 'POST',
      body: JSON.stringify({ accepted: true }),
    });
    if (state.ws?.readyState === WebSocket.OPEN) {
      state.ws.send(JSON.stringify({ type: 'driver:pickup:response', order_id: order.id, accepted: true }));
    }
    toast('Recogida aceptada ✅', 'success');
    document.getElementById('pickup-modal').classList.add('hidden');
    state.pendingNotification = null;
    loadDriverView();
  } catch (err) {
    toast(err.message, 'error');
  }
});

document.getElementById('btn-reject-pickup').addEventListener('click', async () => {
  if (!state.pendingNotification) return;
  const { order } = state.pendingNotification;
  try {
    await apiFetch(`/orders/${order.id}/respond`, {
      method: 'POST',
      body: JSON.stringify({ accepted: false }),
    });
    if (state.ws?.readyState === WebSocket.OPEN) {
      state.ws.send(JSON.stringify({ type: 'driver:pickup:response', order_id: order.id, accepted: false }));
    }
    toast('Recogida rechazada', '');
    document.getElementById('pickup-modal').classList.add('hidden');
    state.pendingNotification = null;
  } catch (err) {
    toast(err.message, 'error');
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────
function statusClass(status) {
  const map = { pending: 'pending', assigned: 'assigned', in_progress: 'progress', completed: 'completed', rejected: 'completed' };
  return map[status] || 'pending';
}
function statusLabel(status) {
  const map = { pending: 'Pendiente', assigned: 'Asignado', in_progress: 'En curso', completed: 'Completado', rejected: 'Rechazado' };
  return map[status] || status;
}
