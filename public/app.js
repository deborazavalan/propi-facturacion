'use strict';
/* Interfaz de Propi Facturación. Todo el texto de la base de datos se inserta con textContent (sin innerHTML). */

const $ = (sel) => document.querySelector(sel);
const ESTADOS = { A: 'Activo', I: 'Inactivo' };

/*
  Cada módulo CRUD define:
    columnas: [campo, título, formato?, 'estado'?]
    campos:   los del formulario. tipo 'catalogo' carga sus opciones de /api/catalogos/<catalogo>;
              si tiene "padre", depende de otro campo (cascada). "virtual" = solo ayuda a elegir, no se envía.
*/
const ENTIDADES = {
  clientes: {
    titulo: 'Clientes',
    url: '/api/clientes',
    llave: 'codigo_cliente',
    nombre: 'cliente',
    permiso: 'clientes',
    columnas: [
      ['nombre', 'Nombre'],
      ['tipo_identificacion', 'Tipo'],
      ['numero_identificacion', 'Identificación'],
      ['provincia', 'Provincia'],
      ['correo', 'Correo'],
      ['telefono', 'Teléfono'],
      ['estado', 'Estado', null, 'estado'],
    ],
    campos: [
      { n: 'nombre', t: 'Nombre completo o razón social', tipo: 'texto', max: 150, req: true, completo: true },
      { n: 'codigo_tipo_identificacion', t: 'Tipo de identificación', tipo: 'catalogo', catalogo: 'tipo_identificacion', req: true },
      { n: 'numero_identificacion', t: 'Número de identificación (solo dígitos)', tipo: 'texto', max: 20, req: true, patron: '[0-9]{9,12}' },
      { n: 'codigo_provincia', t: 'Provincia', tipo: 'catalogo', catalogo: 'provincia', virtual: true, req: true },
      { n: 'codigo_canton', t: 'Cantón', tipo: 'catalogo', catalogo: 'canton', padre: 'codigo_provincia', virtual: true, req: true },
      { n: 'codigo_distrito', t: 'Distrito', tipo: 'catalogo', catalogo: 'distrito', padre: 'codigo_canton', virtual: true, req: true },
      { n: 'codigo_barrio', t: 'Barrio', tipo: 'catalogo', catalogo: 'barrio', padre: 'codigo_distrito', req: true },
      { n: 'direccion', t: 'Dirección exacta', tipo: 'texto', max: 250, completo: true },
      { n: 'profesion', t: 'Profesión u oficio', tipo: 'texto', max: 100 },
      { n: 'codigo_actividad_economica', t: 'Actividad económica', tipo: 'catalogo', catalogo: 'actividad_economica', req: true },
      { n: 'correo', t: 'Correo electrónico', tipo: 'correo', max: 150, req: true },
      { n: 'telefono', t: 'Teléfono', tipo: 'tel', max: 20, req: true },
      { n: 'estado', t: 'Estado', tipo: 'lista', opciones: ESTADOS, req: true, defecto: 'A' },
    ],
  },
  facturas: {
    titulo: 'Facturas',
    url: '/api/facturas',
    llave: 'num_factura',
    nombre: 'factura',
    permiso: 'facturas',
    especial: 'factura', // tiene su propio formulario con líneas (factura.js)
    filtro: null,
    buscar: 'Buscar por número de factura o nombre del cliente',
    columnas: [
      ['num_factura', 'N.º'],
      ['fecha', 'Fecha', (v) => formatoCelda(v, 'fecha')],
      ['cliente', 'Cliente'],
      ['codigo_moneda', 'Moneda'],
      ['subtotal', 'Subtotal', (v) => formatoCelda(v, 'dinero')],
      ['total_impuestos', 'Impuestos', (v) => formatoCelda(v, 'dinero')],
      ['monto_total', 'Total', (v) => formatoCelda(v, 'dinero')],
    ],
  },
  notas: {
    titulo: 'Notas crédito/débito',
    url: '/api/notas',
    llave: 'numero_nota',
    nombre: 'nota',
    permiso: 'notas',
    filtro: { param: 'tipo', opciones: { T: 'Todas', C: 'Crédito', D: 'Débito' } },
    buscar: 'Buscar por n.º de nota, n.º de factura o cliente',
    columnas: [
      ['numero_nota', 'N.º'],
      ['fecha', 'Fecha', (v) => formatoCelda(v, 'fecha')],
      ['num_factura', 'Factura'],
      ['cliente', 'Cliente'],
      ['tipo', 'Tipo', (v) => (v === 'C' ? 'Crédito' : 'Débito')],
      ['monto', 'Monto', (v) => formatoCelda(v, 'dinero')],
      ['motivo', 'Motivo'],
    ],
    campos: [
      { n: 'num_factura', t: 'Número de factura', tipo: 'entero', min: 1, req: true },
      { n: 'tipo', t: 'Tipo', tipo: 'lista', opciones: { C: 'Crédito', D: 'Débito' }, req: true, defecto: 'C' },
      { n: 'monto', t: 'Monto', tipo: 'numero', min: 0.01, maxNum: 999999999999, req: true },
      { n: 'motivo', t: 'Motivo', tipo: 'texto', max: 500, req: true, completo: true },
    ],
  },
  productos: {
    titulo: 'Productos y servicios',
    url: '/api/productos',
    llave: 'codigo_producto',
    nombre: 'producto',
    permiso: 'productos',
    buscar: 'Buscar por descripción o CABYS exacto',
    columnas: [
      ['codigo_CABYS', 'CABYS'],
      ['descripcion', 'Descripción'],
      ['codigo_unidad_medida', 'Unidad'],
      ['precio', 'Precio', (v) => formatoCelda(v, 'dinero')],
      ['porcentaje', 'Impuesto', (v) => `${Number(v).toFixed(2)} %`],
      ['estado', 'Estado', null, 'estado'],
    ],
    campos: [
      { n: 'codigo_CABYS', t: 'Código CABYS (13 dígitos)', tipo: 'texto', max: 13, req: true, patron: '[0-9]{13}' },
      { n: 'codigo_unidad_medida', t: 'Unidad de medida', tipo: 'catalogo', catalogo: 'unidad_medida', req: true },
      { n: 'descripcion', t: 'Descripción', tipo: 'texto', max: 200, req: true, completo: true },
      { n: 'precio', t: 'Precio', tipo: 'numero', maxNum: 999999999999, req: true },
      { n: 'codigo_tipo_impuesto', t: 'Tipo de impuesto', tipo: 'catalogo', catalogo: 'tipo_impuesto', req: true },
      { n: 'estado', t: 'Estado', tipo: 'lista', opciones: ESTADOS, req: true, defecto: 'A' },
    ],
  },
  impuestos: {
    titulo: 'Tipos de impuesto',
    url: '/api/impuestos',
    llave: 'codigo_tipo_impuesto',
    nombre: 'tipo de impuesto',
    permiso: 'impuestos',
    columnas: [
      ['codigo_impuesto', 'Código'],
      ['descripcion', 'Descripción'],
      ['porcentaje', 'Porcentaje', (v) => `${Number(v).toFixed(2)} %`],
      ['tarifa', 'Tarifa'],
      ['estado', 'Estado', null, 'estado'],
    ],
    campos: [
      { n: 'codigo_impuesto', t: 'Código de impuesto (2 dígitos)', tipo: 'texto', max: 2, req: true, patron: '[0-9]{2}' },
      { n: 'tarifa', t: 'Código de tarifa (2 dígitos)', tipo: 'texto', max: 2, req: true, patron: '[0-9]{2}' },
      { n: 'descripcion', t: 'Descripción', tipo: 'texto', max: 100, req: true, completo: true },
      { n: 'porcentaje', t: 'Porcentaje (0 a 100)', tipo: 'numero', maxNum: 100, req: true },
      { n: 'estado', t: 'Estado', tipo: 'lista', opciones: ESTADOS, req: true, defecto: 'A' },
    ],
  },
};

/*
  Reportes (REQ 007). Cada uno llama a un procedimiento de la base mediante /api/reportes/<clave>.
    filtros:  campos que se piden antes de generar. tipo 'fecha' | 'texto' | 'lista'
    columnas: [campo, título, formato?]  formato: 'fecha' | 'dinero' | 'largo' (texto extenso, se recorta en pantalla)
*/
const hoyISO = (diasAtras = 0) => {
  const d = new Date();
  d.setDate(d.getDate() - diasAtras);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

const REPORTES = {
  clientes: {
    titulo: 'Reporte de clientes',
    url: '/api/reportes/clientes',
    filtros: [
      { n: 'desde', t: 'Registrados desde', tipo: 'fecha', defecto: () => hoyISO(800) },
      { n: 'hasta', t: 'Hasta', tipo: 'fecha', defecto: () => hoyISO() },
      { n: 'estado', t: 'Estado', tipo: 'lista', opciones: { T: 'Todos', A: 'Activos', I: 'Inactivos' }, defecto: () => 'T' },
    ],
    columnas: [
      ['nombre', 'Nombre'],
      ['numero_identificacion', 'Identificación'],
      ['actividad_economica', 'Actividad económica'],
      ['correo', 'Correo'],
      ['telefono', 'Teléfono'],
    ],
  },
  facturas: {
    titulo: 'Reporte de facturas',
    url: '/api/reportes/facturas',
    filtros: [
      { n: 'desde', t: 'Facturas desde', tipo: 'fecha', defecto: () => hoyISO(800) },
      { n: 'hasta', t: 'Hasta', tipo: 'fecha', defecto: () => hoyISO() },
    ],
    columnas: [
      ['nombre_cliente', 'Cliente'],
      ['numero_identificacion', 'Identificación'],
      ['actividad_economica', 'Actividad económica'],
      ['num_factura', 'N.º factura'],
      ['fecha', 'Fecha', 'fecha'],
      ['subtotal', 'Subtotal', 'dinero'],
      ['total_impuestos', 'Impuestos', 'dinero'],
      ['total_factura', 'Total', 'dinero'],
    ],
  },
  auditoria: {
    titulo: 'Reporte de auditoría',
    url: '/api/reportes/auditoria',
    filtros: [
      { n: 'desde', t: 'Desde', tipo: 'fecha', defecto: () => hoyISO(365) },
      { n: 'hasta', t: 'Hasta', tipo: 'fecha', defecto: () => hoyISO() },
      { n: 'usuario', t: 'Usuario (vacío = todos)', tipo: 'texto', max: 128 },
    ],
    columnas: [
      ['fecha_registro', 'Fecha', 'fecha'],
      ['accion', 'Acción'],
      ['nombre_usuario', 'Usuario'],
      ['tabla_afectada', 'Tabla'],
      ['llave_registro', 'Llave'],
      ['datos_afectados', 'Datos afectados', 'largo'],
      ['datos_antes', 'Antes', 'largo'],
      ['datos_despues', 'Después', 'largo'],
    ],
  },
  seguridad: {
    titulo: 'Reporte de seguridad',
    url: '/api/reportes/seguridad',
    filtros: [{ n: 'usuario', t: 'Usuario (vacío = todos)', tipo: 'texto', max: 128 }],
    columnas: [
      ['nombre_usuario', 'Usuario'],
      ['rol', 'Rol'],
      ['nombre_objeto', 'Objeto'],
      ['tipo_objeto', 'Tipo de objeto'],
      ['tipo_permiso', 'Permiso'],
      ['estado', 'Estado'],
    ],
  },
};

const estado = { usuario: null, permisos: null, actual: null, editando: null, reporte: null, ultimoReporte: null };

/* ----------------------------- Utilidades de DOM ----------------------------- */
function el(etiqueta, atributos = {}, hijos = []) {
  const nodo = document.createElement(etiqueta);
  for (const [k, v] of Object.entries(atributos)) {
    if (v === false || v === null || v === undefined) continue;
    if (k === 'clase') nodo.className = v;
    else if (k === 'texto') nodo.textContent = v;
    else nodo.setAttribute(k, v === true ? '' : v);
  }
  for (const h of [].concat(hijos)) nodo.append(h);
  return nodo;
}

const mostrar = (nodo, visible) => nodo.classList.toggle('oculto', !visible);

function avisar(texto, esError = false) {
  const m = $('#mensaje-panel');
  m.textContent = texto;
  m.classList.toggle('es-error', esError);
  mostrar(m, Boolean(texto));
}

/* ----------------------------- Llamadas a la API ----------------------------- */
async function api(metodo, url, cuerpo) {
  const respuesta = await fetch(url, {
    method: metodo,
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'fetch' },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  let datos = null;
  try {
    datos = await respuesta.json();
  } catch (_) {
    /* respuesta sin cuerpo */
  }
  if (respuesta.status === 401 && url !== '/api/login' && url !== '/api/me') {
    irALogin('Su sesión terminó. Inicie sesión de nuevo.');
    throw new Error('sesión terminada');
  }
  if (!respuesta.ok) throw new Error((datos && datos.error) || 'No se pudo completar la operación.');
  return datos;
}

/* ----------------------------- Login y sesión ----------------------------- */
function irALogin(mensaje) {
  estado.usuario = null;
  estado.permisos = null;
  estado.actual = null;
  estado.reporte = null;
  estado.ultimoReporte = null;
  if ($('#dialogo').open) $('#dialogo').close();
  if ($('#dialogo-factura').open) $('#dialogo-factura').close();
  mostrar($('#vista-app'), false);
  mostrar($('#vista-login'), true);
  $('#clave').value = '';
  const e = $('#login-error');
  e.textContent = mensaje || '';
  mostrar(e, Boolean(mensaje));
  $('#usuario').focus();
}

function irALaApp(sesion) {
  estado.usuario = sesion.usuario;
  estado.permisos = sesion.permisos;
  $('#info-usuario').textContent = `${sesion.usuario} · ${sesion.rolTexto}`;
  mostrar($('#vista-login'), false);
  mostrar($('#vista-app'), true);
  construirMenu();
}

$('#form-login').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const boton = $('#btn-login');
  const e = $('#login-error');
  mostrar(e, false);
  boton.disabled = true;
  boton.textContent = 'Ingresando...';
  try {
    const sesion = await api('POST', '/api/login', { usuario: $('#usuario').value, clave: $('#clave').value });
    $('#clave').value = '';
    irALaApp(sesion);
  } catch (err) {
    e.textContent = err.message;
    mostrar(e, true);
  } finally {
    boton.disabled = false;
    boton.textContent = 'Ingresar';
  }
});

$('#btn-salir').addEventListener('click', async () => {
  try {
    await api('POST', '/api/logout');
  } catch (_) {
    /* si falla, igual se vuelve al login */
  }
  irALogin('Sesión cerrada.');
});

/* ----------------------------- Menú y paneles ----------------------------- */
function construirMenu() {
  const menu = $('#menu');
  menu.replaceChildren();
  const disponibles = Object.entries(ENTIDADES).filter(([, d]) => estado.permisos[d.permiso].ver);
  for (const [clave, def] of disponibles) {
    const b = el('button', { type: 'button', 'data-vista': `ent:${clave}`, texto: def.titulo });
    b.addEventListener('click', () => abrirEntidad(clave));
    menu.append(b);
  }
  const reportes = Object.entries(REPORTES).filter(([clave]) => estado.permisos.reportes?.[clave]);
  for (const [clave, def] of reportes) {
    const b = el('button', { type: 'button', 'data-vista': `rep:${clave}`, texto: def.titulo.replace('Reporte de ', 'Rep. ') });
    b.addEventListener('click', () => abrirReporte(clave));
    menu.append(b);
  }
  mostrar($('#panel-vacio'), false);
  if (disponibles.length) abrirEntidad(disponibles[0][0]);
  else if (reportes.length) abrirReporte(reportes[0][0]);
  else {
    mostrar($('#panel-entidad'), false);
    mostrar($('#panel-reporte'), false);
    $('#texto-vacio').textContent = 'Su rol no tiene módulos disponibles.';
    mostrar($('#panel-vacio'), true);
  }
}

function marcarMenu(vista) {
  for (const b of document.querySelectorAll('#menu button')) b.classList.toggle('activo', b.dataset.vista === vista);
}

function abrirEntidad(clave) {
  estado.actual = clave;
  const def = ENTIDADES[clave];
  marcarMenu(`ent:${clave}`);
  mostrar($('#panel-reporte'), false);
  $('#titulo-entidad').textContent = def.titulo;
  mostrar($('#btn-nuevo'), estado.permisos[def.permiso].crear);
  $('#filtro-texto').value = '';
  configurarFiltro(def);
  $('#filtro-texto').placeholder = def.buscar || (clave === 'clientes' ? 'Buscar por nombre o identificación exacta' : 'Buscar por descripción, código o tarifa');
  avisar('');

  const fila = el('tr');
  for (const [, titulo] of def.columnas) fila.append(el('th', { texto: titulo }));
  fila.append(el('th', { texto: 'Acciones' }));
  $('#tabla-cabecera').replaceChildren(fila);

  mostrar($('#panel-entidad'), true);
  mostrar($('#panel-vacio'), false);
  cargarLista();
}

// El selector de la derecha filtra por estado (activos/inactivos), por tipo de nota, o no se muestra.
function configurarFiltro(def) {
  const sel = $('#filtro-estado');
  const filtro = def.filtro === undefined ? { param: 'estado', opciones: { T: 'Todos', A: 'Activos', I: 'Inactivos' } } : def.filtro;
  mostrar(sel, filtro !== null);
  sel.replaceChildren();
  if (filtro) for (const [v, t] of Object.entries(filtro.opciones)) sel.append(el('option', { value: v, texto: t }));
  sel.value = 'T';
}

async function cargarLista() {
  const def = ENTIDADES[estado.actual];
  const params = new URLSearchParams();
  const texto = $('#filtro-texto').value.trim();
  if (texto) params.set('texto', texto);
  if (def.filtro !== null) params.set(def.filtro?.param || 'estado', $('#filtro-estado').value);
  try {
    pintarTabla(def, await api('GET', `${def.url}?${params}`));
  } catch (err) {
    $('#tabla-cuerpo').replaceChildren();
    $('#resumen').textContent = '';
    avisar(err.message, true);
  }
}

function pintarTabla(def, filas) {
  const permisos = estado.permisos[def.permiso];
  const cuerpo = $('#tabla-cuerpo');
  cuerpo.replaceChildren();

  if (!filas.length) {
    const td = el('td', { clase: 'vacio', colspan: def.columnas.length + 1, texto: 'No hay registros para mostrar.' });
    cuerpo.append(el('tr', {}, td));
  }

  for (const fila of filas) {
    const tr = el('tr');
    for (const [campo, , formato, especial] of def.columnas) {
      const valor = fila[campo];
      if (especial === 'estado') {
        const et = el('span', { clase: valor === 'A' ? 'etiqueta' : 'etiqueta inactivo', texto: ESTADOS[valor] || valor });
        tr.append(el('td', {}, et));
      } else {
        const texto = valor === null || valor === undefined ? '' : formato ? formato(valor) : String(valor);
        tr.append(el('td', { texto }));
      }
    }
    const acciones = el('td', { clase: 'acciones-celda' });
    const id = fila[def.llave];
    if (permisos.editar) {
      const b = el('button', { type: 'button', texto: 'Editar' });
      b.addEventListener('click', () => abrirFormulario(id));
      acciones.append(b);
    }
    if (permisos.eliminar) {
      const b = el('button', { type: 'button', clase: 'peligro', texto: 'Eliminar' });
      b.addEventListener('click', () => eliminar(id));
      acciones.append(b);
    }
    tr.append(acciones);
    cuerpo.append(tr);
  }

  $('#resumen').textContent =
    `${filas.length} registro(s)` + (filas.length >= 500 ? ' (se muestran hasta 500; use la búsqueda)' : '');
}

$('#form-filtros').addEventListener('submit', (ev) => {
  ev.preventDefault();
  avisar('');
  cargarLista();
});

/* ----------------------------- Formulario crear / editar ----------------------------- */
function construirCampo(campo) {
  const id = `campo-${campo.n}`;
  let control;
  if (campo.tipo === 'lista' || campo.tipo === 'catalogo') {
    control = el('select', { id, name: campo.n, required: campo.req });
    if (campo.tipo === 'lista') {
      for (const [v, t] of Object.entries(campo.opciones)) control.append(el('option', { value: v, texto: t }));
      control.value = campo.defecto ?? '';
    } else {
      control.append(el('option', { value: '', texto: campo.padre ? 'Seleccione el nivel anterior' : 'Cargando...' }));
      control.disabled = true;
    }
  } else {
    const tipoInput = { texto: 'text', correo: 'email', tel: 'tel', numero: 'number', entero: 'number' }[campo.tipo];
    const esNum = campo.tipo === 'numero' || campo.tipo === 'entero';
    control = el('input', {
      id,
      name: campo.n,
      type: tipoInput,
      maxlength: campo.max,
      required: campo.req,
      pattern: campo.patron,
      min: esNum ? String(campo.min ?? 0) : false,
      max: esNum && campo.maxNum !== undefined ? String(campo.maxNum) : false,
      step: campo.tipo === 'entero' ? '1' : campo.tipo === 'numero' ? '0.01' : false,
    });
  }
  return el('div', { clase: campo.completo ? 'completo' : '' }, [
    el('label', { for: id, texto: campo.t + (campo.req ? ' *' : '') }),
    control,
  ]);
}

// Llena un catálogo; "valor" deja una opción preseleccionada (edición).
async function llenarCatalogo(campo, valor) {
  const sel = $(`#campo-${campo.n}`);
  const padreSel = campo.padre ? $(`#campo-${campo.padre}`) : null;
  sel.replaceChildren();
  if (padreSel && !padreSel.value) {
    sel.append(el('option', { value: '', texto: 'Seleccione el nivel anterior' }));
    sel.disabled = true;
    return;
  }
  try {
    const url = `/api/catalogos/${campo.catalogo}` + (padreSel ? `?padre=${encodeURIComponent(padreSel.value)}` : '');
    const filas = await api('GET', url);
    sel.append(el('option', { value: '', texto: filas.length ? 'Seleccione...' : 'Sin opciones registradas' }));
    for (const f of filas) sel.append(el('option', { value: f.codigo, texto: f.nombre }));
    sel.disabled = !filas.length;
    if (valor !== undefined && valor !== null) sel.value = String(valor);
  } catch (err) {
    sel.append(el('option', { value: '', texto: 'No se pudo cargar' }));
    sel.disabled = true;
  }
}

// Al cambiar un catálogo se recargan en cadena los que dependen de él.
function enlazarCascada(def) {
  for (const campo of def.campos) {
    if (campo.tipo !== 'catalogo') continue;
    $(`#campo-${campo.n}`).addEventListener('change', async () => {
      let actual = campo.n;
      for (let hijo = def.campos.find((c) => c.padre === actual); hijo; hijo = def.campos.find((c) => c.padre === actual)) {
        await llenarCatalogo(hijo);
        actual = hijo.n;
      }
    });
  }
}

async function abrirFormulario(id) {
  const def = ENTIDADES[estado.actual];
  if (def.especial === 'factura') return abrirFactura(id);
  avisar('');
  let registro = {};
  if (id !== undefined) {
    try {
      registro = await api('GET', `${def.url}/${encodeURIComponent(id)}`);
    } catch (err) {
      avisar(err.message, true);
      return;
    }
  }
  estado.editando = id === undefined ? null : id;
  $('#dialogo-titulo').textContent = id === undefined ? `Nuevo ${def.nombre}` : `Editar ${def.nombre}`;
  $('#dialogo-campos').replaceChildren(...def.campos.map(construirCampo));
  mostrar($('#dialogo-error'), false);

  // Valores iniciales de los campos que no son catálogos
  for (const c of def.campos) {
    if (c.tipo === 'catalogo') continue;
    const v = registro[c.n];
    if (v !== undefined && v !== null) $(`#campo-${c.n}`).value = c.tipo === 'numero' || c.tipo === 'entero' ? Number(v) : String(v);
  }
  enlazarCascada(def);
  $('#dialogo').showModal();

  // Catálogos en orden (los hijos necesitan el valor del padre)
  for (const c of def.campos.filter((x) => x.tipo === 'catalogo')) await llenarCatalogo(c, registro[c.n]);
}

$('#btn-nuevo').addEventListener('click', () => abrirFormulario());
$('#dialogo-cancelar').addEventListener('click', () => $('#dialogo').close());

$('#form-entidad').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const def = ENTIDADES[estado.actual];
  const datos = {};
  for (const c of def.campos) if (!c.virtual) datos[c.n] = $(`#campo-${c.n}`).value;

  const boton = $('#dialogo-guardar');
  boton.disabled = true;
  const esNuevo = estado.editando === null;
  try {
    if (esNuevo) await api('POST', def.url, datos);
    else await api('PUT', `${def.url}/${encodeURIComponent(estado.editando)}`, datos);
    $('#dialogo').close();
    avisar(esNuevo ? 'Registro creado correctamente.' : 'Registro actualizado correctamente.');
    cargarLista();
  } catch (err) {
    const e = $('#dialogo-error');
    e.textContent = err.message;
    mostrar(e, true);
  } finally {
    boton.disabled = false;
  }
});

async function eliminar(id) {
  const def = ENTIDADES[estado.actual];
  if (!window.confirm(`¿Eliminar este ${def.nombre}? Esta acción no se puede deshacer.`)) return;
  try {
    await api('DELETE', `${def.url}/${encodeURIComponent(id)}`);
    avisar('Registro eliminado.');
    cargarLista();
  } catch (err) {
    avisar(err.message, true);
  }
}

/* ----------------------------- Reportes ----------------------------- */
function avisarReporte(texto, esError = false) {
  const m = $('#mensaje-reporte');
  m.textContent = texto;
  m.classList.toggle('es-error', esError);
  mostrar(m, Boolean(texto));
}

// Las fechas llegan como si fueran UTC (sin zona), por eso se muestran en UTC para no correrlas de hora.
function formatoCelda(valor, formato) {
  if (valor === null || valor === undefined) return '';
  if (formato === 'fecha') {
    const d = new Date(valor);
    return Number.isNaN(d.getTime()) ? String(valor) : d.toLocaleString('es-CR', {
          timeZone: 'UTC', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false,
        });
  }
  if (formato === 'dinero') {
    const n = Number(valor);
    return Number.isFinite(n) ? n.toLocaleString('es-CR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : String(valor);
  }
  return String(valor);
}

function construirFiltro(f) {
  const id = `rf-${f.n}`;
  let control;
  if (f.tipo === 'lista') {
    control = el('select', { id, name: f.n });
    for (const [v, t] of Object.entries(f.opciones)) control.append(el('option', { value: v, texto: t }));
  } else {
    control = el('input', { id, name: f.n, type: f.tipo === 'fecha' ? 'date' : 'text', maxlength: f.max, required: f.tipo === 'fecha' });
  }
  if (f.defecto) control.value = f.defecto();
  return el('div', {}, [el('label', { for: id, texto: f.t }), control]);
}

function abrirReporte(clave) {
  const def = REPORTES[clave];
  estado.reporte = clave;
  estado.actual = null;
  estado.ultimoReporte = null;
  marcarMenu(`rep:${clave}`);
  mostrar($('#panel-entidad'), false);
  mostrar($('#panel-vacio'), false);
  mostrar($('#panel-reporte'), true);
  $('#titulo-reporte').textContent = def.titulo;
  $('#filtros-reporte').replaceChildren(...def.filtros.map(construirFiltro));
  $('#rep-cabecera').replaceChildren();
  $('#rep-cuerpo').replaceChildren();
  mostrar($('#btn-csv'), false);
  $('#resumen-reporte').textContent = 'Elija los filtros y pulse Generar.';
  avisarReporte('');
}

// Si el procedimiento devolviera columnas con otros nombres, se muestran tal como vienen.
function columnasDe(def, filas) {
  if (!filas.length) return def.columnas;
  const claves = Object.keys(filas[0]);
  if (def.columnas.every(([c]) => claves.includes(c))) return def.columnas;
  return claves.map((c) => [c, c.replace(/_/g, ' ')]);
}

function pintarReporte(clave, def, datos) {
  const columnas = columnasDe(def, datos.filas);
  const fila = el('tr');
  for (const [, titulo, formato] of columnas) fila.append(el('th', { texto: titulo, clase: formato === 'dinero' ? 'numero' : false }));
  $('#rep-cabecera').replaceChildren(fila);

  const cuerpo = $('#rep-cuerpo');
  cuerpo.replaceChildren();
  if (!datos.filas.length) {
    cuerpo.append(el('tr', {}, el('td', { clase: 'vacio', colspan: columnas.length, texto: 'No hay registros para los filtros indicados.' })));
  }
  for (const f of datos.filas) {
    const tr = el('tr');
    for (const [campo, , formato] of columnas) {
      const texto = formatoCelda(f[campo], formato);
      const clase = formato === 'dinero' ? 'numero' : formato === 'largo' ? 'largo' : false;
      tr.append(el('td', { texto, clase, title: formato === 'largo' && texto ? texto : false }));
    }
    cuerpo.append(tr);
  }

  $('#resumen-reporte').textContent = datos.truncado
    ? `Se muestran las primeras ${datos.filas.length} de ${datos.total} filas. Acote las fechas o el usuario para ver el resto.`
    : `${datos.total} fila(s)`;
  estado.ultimoReporte = { clave, columnas, filas: datos.filas };
  mostrar($('#btn-csv'), datos.filas.length > 0);
}

$('#form-reporte').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const clave = estado.reporte;
  const def = REPORTES[clave];
  const params = new URLSearchParams();
  for (const f of def.filtros) {
    const v = $(`#rf-${f.n}`).value.trim();
    if (v) params.set(f.n, v);
  }
  const boton = $('#form-reporte button[type="submit"]');
  boton.disabled = true;
  avisarReporte('');
  $('#resumen-reporte').textContent = 'Generando...';
  try {
    const datos = await api('GET', `${def.url}?${params}`);
    if (estado.reporte === clave) pintarReporte(clave, def, datos); // por si cambió de reporte mientras cargaba
  } catch (err) {
    if (estado.reporte !== clave) return;
    $('#rep-cuerpo').replaceChildren();
    $('#resumen-reporte').textContent = '';
    mostrar($('#btn-csv'), false);
    avisarReporte(err.message, true);
  } finally {
    boton.disabled = false;
  }
});

// CSV con separador ";" y BOM, para que Excel (configuración regional de Costa Rica) lo abra con tildes y columnas.
$('#btn-csv').addEventListener('click', () => {
  const u = estado.ultimoReporte;
  if (!u) return;
  const esc = (t) => {
    let s = String(t);
    // evita que Excel interprete el texto como fórmula
    if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && !/^-[\d.,\s]+$/.test(s))) s = `'${s}`;
    return `"${s.replace(/"/g, '""')}"`;
  };
  const lineas = [u.columnas.map(([, t]) => esc(t)).join(';')];
  for (const f of u.filas) lineas.push(u.columnas.map(([c, , fmt]) => esc(formatoCelda(f[c], fmt))).join(';'));
  const url = URL.createObjectURL(new Blob(['﻿' + lineas.join('\r\n')], { type: 'text/csv;charset=utf-8' }));
  const a = el('a', { href: url, download: `reporte_${u.clave}_${hoyISO()}.csv` });
  document.body.append(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
});

/* ----------------------------- Inicio: ¿ya hay sesión? ----------------------------- */
(async () => {
  try {
    irALaApp(await api('GET', '/api/me'));
  } catch (_) {
    mostrar($('#vista-login'), true);
  }
})();
