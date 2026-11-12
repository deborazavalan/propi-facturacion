'use strict';
/**
 * Sistema de Gestión de Facturación Propi - servidor (punto de control 1)
 *
 * Idea central: la aplicación NO guarda usuarios ni contraseñas. Cada persona inicia sesión con su
 * login de SQL Server; el servidor abre una conexión a nombre de esa persona, de modo que los
 * permisos (roles) y la bitácora los aplica la propia base de datos (REQ 003 y REQ 004).
 * Todo el acceso a datos se hace con procedimientos almacenados y parámetros (sin SQL concatenado).
 */
require('dotenv').config({ quiet: true });
const express = require('express');
const sql = require('mssql');
const crypto = require('crypto');
const dns = require('dns').promises;
const os = require('os');
const path = require('path');

/* ------------------------------ Configuración ------------------------------ */
const CFG = {
  puerto: Number(process.env.PORT) || 3000,
  servidor: process.env.DB_SERVER || 'localhost',
  puertoBD: Number(process.env.DB_PORT) || 1433,
  instancia: process.env.DB_INSTANCE || '',
  baseDatos: process.env.DB_NAME || 'PropiDB',
  cifrar: (process.env.DB_ENCRYPT || 'true') === 'true',
  confiarCertificado: (process.env.DB_TRUST_CERT || 'true') === 'true',
  minutosInactividad: Number(process.env.SESSION_IDLE_MIN) || 30,
  confiarProxy: process.env.TRUST_PROXY || '',
  cookieSegura: (process.env.COOKIE_SECURE || 'false') === 'true',
};

const ROLES = {
  rol_administrador: 'Administrador',
  rol_digitador: 'Digitador',
  rol_consulta: 'Consulta',
};

// Solo orienta a la interfaz; la seguridad real la aplica SQL Server con GRANT/DENY.
// "reportes" indica qué reportes se ofrecen en el menú, según permisos_roles.sql: el administrador ve los 4,
// consulta solo clientes y facturas, y el digitador ninguno. Si ese script cambia, se ajusta aquí
// (si no coincide, la base responde "no tiene permiso").
const PERMISOS = {
  rol_administrador: {
    clientes: { ver: true, crear: true, editar: true, eliminar: true },
    impuestos: { ver: true, crear: true, editar: true, eliminar: true },
    productos: { ver: true, crear: true, editar: true, eliminar: true },
    facturas: { ver: true, crear: true, editar: true, eliminar: true },
    notas: { ver: true, crear: true, editar: true, eliminar: true },
    reportes: { clientes: true, facturas: true, auditoria: true, seguridad: true },
  },
  rol_digitador: {
    clientes: { ver: true, crear: true, editar: true, eliminar: false },
    impuestos: { ver: true, crear: false, editar: false, eliminar: false },
    productos: { ver: true, crear: false, editar: false, eliminar: false },
    facturas: { ver: true, crear: true, editar: true, eliminar: false },
    notas: { ver: true, crear: true, editar: true, eliminar: false },
    reportes: { clientes: false, facturas: false, auditoria: false, seguridad: false },
  },
  rol_consulta: {
    clientes: { ver: false, crear: false, editar: false, eliminar: false },
    impuestos: { ver: false, crear: false, editar: false, eliminar: false },
    productos: { ver: false, crear: false, editar: false, eliminar: false },
    facturas: { ver: false, crear: false, editar: false, eliminar: false },
    notas: { ver: false, crear: false, editar: false, eliminar: false },
    reportes: { clientes: true, facturas: true, auditoria: false, seguridad: false },
  },
};

/* ------------------------------ Sesiones ------------------------------ */
// sid -> { pool, usuario, rol, codAcceso, ultimo }
const sesiones = new Map();

function configConexion(usuario, clave) {
  const cfg = {
    user: usuario,
    password: clave,
    server: CFG.servidor,
    database: CFG.baseDatos,
    connectionTimeout: 8000,
    requestTimeout: 15000,
    pool: { max: 2, min: 0, idleTimeoutMillis: 60000 },
    options: {
      encrypt: CFG.cifrar,
      trustServerCertificate: CFG.confiarCertificado,
      enableArithAbort: true,
    },
  };
  if (CFG.instancia) cfg.options.instanceName = CFG.instancia;
  else cfg.port = CFG.puertoBD;
  return cfg;
}

async function cerrarSesion(sid, motivo) {
  const s = sesiones.get(sid);
  if (!s) return;
  sesiones.delete(sid);
  try {
    await s.pool
      .request()
      .input('codigo_acceso', sql.Int, s.codAcceso)
      .execute('dbo.usp_BitacoraAcceso_Salida');
  } catch (e) {
    console.error(`No se pudo registrar la salida de ${s.usuario} (${motivo}):`, e.message);
  }
  try {
    await s.pool.close();
  } catch (_) {
    /* la conexión ya estaba cerrada */
  }
}

function leerCookie(req, nombre) {
  const cabecera = req.headers.cookie || '';
  for (const parte of cabecera.split(';')) {
    const i = parte.indexOf('=');
    if (i > -1 && parte.slice(0, i).trim() === nombre) return decodeURIComponent(parte.slice(i + 1).trim());
  }
  return null;
}

function ponerCookie(res, sid, maxAgeSeg) {
  const partes = [`sid=${sid}`, 'Path=/', 'HttpOnly', 'SameSite=Strict', `Max-Age=${maxAgeSeg}`];
  if (CFG.cookieSegura) partes.push('Secure');
  res.setHeader('Set-Cookie', partes.join('; '));
}

/* ------------------------------ Utilidades ------------------------------ */
function normalizarIp(ip) {
  if (!ip) return 'desconocida';
  if (ip.startsWith('::ffff:')) return ip.slice(7);
  return ip;
}

const esLoopback = (ip) => ip === '::1' || ip === '127.0.0.1';

// Un navegador no entrega el nombre del equipo; se obtiene por DNS inverso a partir de la IP.
async function resolverTerminal(ip) {
  if (esLoopback(ip)) return os.hostname();
  try {
    const nombres = await Promise.race([
      dns.reverse(ip),
      new Promise((_, rechazar) => setTimeout(() => rechazar(new Error('timeout')), 1500)),
    ]);
    if (nombres && nombres.length) return nombres[0];
  } catch (_) {
    /* sin DNS inverso */
  }
  return 'desconocido';
}

// Límite de intentos de login por IP: 8 cada 10 minutos.
const intentos = new Map();
function limiteIntentos(ip) {
  const ahora = Date.now();
  const e = intentos.get(ip);
  if (!e || ahora - e.inicio > 10 * 60 * 1000) {
    intentos.set(ip, { inicio: ahora, n: 0 });
    return true;
  }
  return e.n < 8;
}
const sumarIntento = (ip) => {
  const e = intentos.get(ip);
  if (e) e.n += 1;
};

class ErrorHttp extends Error {
  constructor(estado, mensaje) {
    super(mensaje);
    this.estado = estado;
  }
}

function numeroError(err) {
  return err.number ?? err.originalError?.info?.number ?? err.precedingErrors?.[0]?.number;
}

// Traduce errores de SQL Server a respuestas HTTP comprensibles.
function traducirError(err) {
  if (err instanceof ErrorHttp) return { estado: err.estado, mensaje: err.message };
  const n = numeroError(err);
  if (n >= 50000 && n < 60000) return { estado: 400, mensaje: err.message }; // validaciones de los SP
  if (n === 229 || n === 230 || n === 262 || n === 297)
    return { estado: 403, mensaje: 'Su rol no tiene permiso para realizar esta acción.' };
  if (n === 2627 || n === 2601)
    return { estado: 409, mensaje: 'Ya existe un registro con esos datos únicos.' };
  if (n === 547)
    return {
      estado: 409,
      mensaje: 'No se puede completar: el registro está relacionado con otros datos. Inactívelo en lugar de borrarlo.',
    };
  if (err.code === 'ECONNCLOSED' || err.code === 'ESOCKET' || err.code === 'ETIMEOUT' || err.code === 'ENOTOPEN')
    return { estado: 503, mensaje: 'Se perdió la conexión con la base de datos. Inicie sesión de nuevo.' };
  console.error('Error no controlado:', err);
  return { estado: 500, mensaje: 'Ocurrió un error inesperado en el servidor.' };
}

// Valida y normaliza el cuerpo de la petición según una lista de campos.
// campo = [nombre, tipoSQL, obligatorio, longitudMaxima]
function leerCampos(cuerpo, campos) {
  const valores = {};
  const faltantes = [];
  for (const [nombre, , obligatorio, max] of campos) {
    let v = cuerpo?.[nombre];
    if (v === undefined || v === null) v = '';
    if (typeof v !== 'string' && typeof v !== 'number') throw new ErrorHttp(400, `El campo ${nombre} no es válido.`);
    v = String(v).trim();
    if (max && v.length > max) throw new ErrorHttp(400, `El campo ${nombre} supera ${max} caracteres.`);
    if (obligatorio && v === '') faltantes.push(nombre);
    valores[nombre] = v === '' ? null : v;
  }
  if (faltantes.length) throw new ErrorHttp(400, `Faltan campos obligatorios: ${faltantes.join(', ')}.`);
  return valores;
}

function aplicarEntradas(req, campos, valores) {
  for (const [nombre, tipo] of campos) {
    let v = valores[nombre];
    if (tipo === sql.Int && v !== null) {
      v = Number(v);
      if (!Number.isInteger(v) || v <= 0) throw new ErrorHttp(400, `El campo ${nombre} no es válido.`);
    }
    req.input(nombre, tipo, v);
  }
}

/* ------------------------------ Definición de campos ------------------------------ */
// Los nombres coinciden con los parámetros de los SP (sql/02_persona_b_punto_control_1.sql)
const VC = (n) => sql.VarChar(n);
const CAMPOS_CLIENTE = [
  ['nombre', VC(150), true, 150],
  ['codigo_tipo_identificacion', sql.Char(2), true, 2],
  ['numero_identificacion', VC(50), true, 20],
  ['codigo_barrio', sql.Int, true, 10],
  ['direccion', VC(250), false, 250],
  ['profesion', VC(100), false, 100],
  ['codigo_actividad_economica', VC(6), true, 6],
  ['correo', VC(150), true, 150],
  ['telefono', VC(20), true, 20],
  ['estado', sql.Char(1), true, 1],
];

const CAMPOS_IMPUESTO = [
  ['codigo_impuesto', sql.Char(2), true, 2],
  ['descripcion', VC(100), true, 100],
  ['porcentaje', sql.Decimal(5, 2), true, 8],
  ['tarifa', sql.Char(2), true, 2],
  ['estado', sql.Char(1), true, 1],
];

const CAMPOS_PRODUCTO = [
  ['codigo_CABYS', sql.Char(13), true, 13],
  ['descripcion', VC(200), true, 200],
  ['codigo_unidad_medida', VC(10), true, 10],
  ['precio', sql.Decimal(18, 2), true, 20],
  ['codigo_tipo_impuesto', sql.Int, true, 10],
  ['estado', sql.Char(1), true, 1],
];

const CAMPOS_NOTA = [
  ['num_factura', sql.Int, true, 10],
  ['tipo', sql.Char(1), true, 1],
  ['motivo', VC(500), true, 500],
  ['monto', sql.Decimal(18, 2), true, 20],
];

const CAMPOS_FACTURA = [
  ['codigo_cliente', sql.Int, true, 10],
  ['cod_condicion_venta', sql.Char(2), true, 2],
  ['codigo_medio_pago', sql.Char(2), true, 2],
  ['codigo_moneda', sql.Char(3), true, 3],
  ['tipo_cambio', sql.Decimal(12, 4), true, 20],
  ['observaciones', VC(500), false, 500],
];

// Convierte a número un campo que llegó como texto; valida rango y decimales.
function aNumero(valor, nombre, { min = 0, max = 999999999999, decimales = 2, exclusivo = false } = {}) {
  const n = Number(valor);
  const fueraDeRango = exclusivo ? n <= min : n < min;
  if (!Number.isFinite(n) || fueraDeRango || n > max)
    throw new ErrorHttp(400, `El campo ${nombre} no es válido.`);
  if (Math.round(n * 10 ** decimales) / 10 ** decimales !== n)
    throw new ErrorHttp(400, `El campo ${nombre} admite hasta ${decimales} decimales.`);
  return n;
}

/* ------------------------------ Aplicación ------------------------------ */
const app = express();
app.disable('x-powered-by');
if (CFG.confiarProxy) app.set('trust proxy', CFG.confiarProxy === 'true' ? true : CFG.confiarProxy);

app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; form-action 'self'"
  );
  next();
});
app.use(express.json({ limit: '20kb' }));

// Defensa CSRF adicional: las peticiones que cambian datos deben venir del propio JavaScript de la app.
app.use('/api', (req, res, next) => {
  if (['POST', 'PUT', 'DELETE'].includes(req.method) && req.get('X-Requested-With') !== 'fetch')
    return res.status(403).json({ error: 'Petición no permitida.' });
  next();
});

function requiereSesion(req, res, next) {
  const sid = leerCookie(req, 'sid');
  const s = sid && sesiones.get(sid);
  if (!s) return res.status(401).json({ error: 'Su sesión no está activa. Inicie sesión.' });
  s.ultimo = Date.now();
  req.sid = sid;
  req.ses = s;
  next();
}

const envolver = (fn) => (req, res) =>
  Promise.resolve(fn(req, res)).catch((err) => {
    const { estado, mensaje } = traducirError(err);
    res.status(estado).json({ error: mensaje });
  });

/* ------------------------------ Login / sesión ------------------------------ */
app.post(
  '/api/login',
  envolver(async (req, res) => {
    const ip = normalizarIp(req.ip);
    if (!limiteIntentos(ip)) throw new ErrorHttp(429, 'Demasiados intentos fallidos. Espere unos minutos.');

    const usuario = typeof req.body?.usuario === 'string' ? req.body.usuario.trim() : '';
    const clave = typeof req.body?.clave === 'string' ? req.body.clave : '';
    if (!usuario || !clave || usuario.length > 128 || clave.length > 128)
      throw new ErrorHttp(400, 'Ingrese usuario y contraseña.');

    const pool = new sql.ConnectionPool(configConexion(usuario, clave));
    pool.on('error', (e) => console.error(`Error en la conexión de ${usuario}:`, e.message));

    try {
      await pool.connect();
    } catch (err) {
      sumarIntento(ip);
      try {
        await pool.close();
      } catch (_) {
        /* nada que cerrar */
      }
      if (err.code === 'ELOGIN') throw new ErrorHttp(401, 'Usuario o contraseña incorrectos.');
      console.error('No se pudo conectar a SQL Server:', err.code, err.message);
      throw new ErrorHttp(503, 'No se pudo conectar con el servidor de base de datos.');
    }

    try {
      const info = (await pool.request().execute('dbo.usp_Sesion_Informacion')).recordset[0];
      if (!info || info.nom_rol === 'sin_rol') {
        await pool.close();
        throw new ErrorHttp(403, 'El usuario no pertenece a ningún rol de la aplicación.');
      }

      const terminal = await resolverTerminal(ip);
      const salida = await pool
        .request()
        .input('terminal', sql.VarChar(128), terminal)
        .input('direccion_ip', sql.VarChar(45), ip)
        .output('codigo_acceso', sql.Int)
        .execute('dbo.usp_BitacoraAcceso_Ingreso');

      const sid = crypto.randomBytes(32).toString('hex');
      sesiones.set(sid, {
        pool,
        usuario: info.nom_usuario,
        rol: info.nom_rol,
        codAcceso: salida.output.codigo_acceso,
        ultimo: Date.now(),
      });
      intentos.delete(ip);
      ponerCookie(res, sid, CFG.minutosInactividad * 60);
      res.json({
        usuario: info.nom_usuario,
        rol: info.nom_rol,
        rolTexto: ROLES[info.nom_rol],
        permisos: PERMISOS[info.nom_rol],
      });
    } catch (err) {
      try {
        await pool.close();
      } catch (_) {
        /* ya cerrada */
      }
      throw err;
    }
  })
);

app.post(
  '/api/logout',
  envolver(async (req, res) => {
    const sid = leerCookie(req, 'sid');
    if (sid) await cerrarSesion(sid, 'salida del usuario');
    res.setHeader('Set-Cookie', 'sid=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0');
    res.json({ ok: true });
  })
);

app.get(
  '/api/me',
  requiereSesion,
  envolver(async (req, res) => {
    const s = req.ses;
    res.json({ usuario: s.usuario, rol: s.rol, rolTexto: ROLES[s.rol], permisos: PERMISOS[s.rol] });
  })
);

/* ------------------------------ Utilidades de rutas ------------------------------ */
function filtroEstado(valor) {
  if (valor === undefined || valor === '' || valor === 'T') return null;
  if (valor !== 'A' && valor !== 'I') throw new ErrorHttp(400, 'El estado debe ser A o I.');
  return valor;
}

function idEntero(valor) {
  const n = Number(valor);
  if (!Number.isInteger(n) || n <= 0) throw new ErrorHttp(400, 'Identificador no válido.');
  return n;
}

const textoBusqueda = (q) => (typeof q === 'string' && q.trim() ? q.trim().slice(0, 100) : null);

/* ------------------------------ Catálogos (listas desplegables) ------------------------------ */
const CATALOGOS = [
  'tipo_identificacion', 'provincia', 'canton', 'distrito', 'barrio', 'actividad_economica',
  'condicion_venta', 'medio_pago', 'moneda', 'unidad_medida', 'tipo_impuesto',
];

app.get(
  '/api/catalogos/:nombre',
  requiereSesion,
  envolver(async (req, res) => {
    if (!CATALOGOS.includes(req.params.nombre)) throw new ErrorHttp(404, 'El catálogo no existe.');
    const q = req.ses.pool.request().input('catalogo', VC(30), req.params.nombre);
    q.input('padre', sql.Int, req.query.padre ? idEntero(req.query.padre) : null);
    res.json((await q.execute('dbo.usp_Catalogo_Listar')).recordset);
  })
);

/* ------------------------------ Clientes ------------------------------ */
app.get(
  '/api/clientes',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('texto', VC(100), textoBusqueda(req.query.texto))
      .input('estado', sql.Char(1), filtroEstado(req.query.estado))
      .execute('dbo.usp_Cliente_Listar');
    res.json(r.recordset);
  })
);

app.get(
  '/api/clientes/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('codigo_cliente', sql.Int, idEntero(req.params.id))
      .execute('dbo.usp_Cliente_Obtener');
    if (!r.recordset.length) throw new ErrorHttp(404, 'El cliente no existe.');
    res.json(r.recordset[0]);
  })
);

app.post(
  '/api/clientes',
  requiereSesion,
  envolver(async (req, res) => {
    const v = leerCampos(req.body, CAMPOS_CLIENTE);
    const q = req.ses.pool.request();
    aplicarEntradas(q, CAMPOS_CLIENTE, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    q.output('codigo_cliente', sql.Int);
    const r = await q.execute('dbo.usp_Cliente_Insertar');
    res.status(201).json({ codigo_cliente: r.output.codigo_cliente });
  })
);

app.put(
  '/api/clientes/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const v = leerCampos(req.body, CAMPOS_CLIENTE);
    const q = req.ses.pool.request().input('codigo_cliente', sql.Int, idEntero(req.params.id));
    aplicarEntradas(q, CAMPOS_CLIENTE, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    await q.execute('dbo.usp_Cliente_Actualizar');
    res.json({ ok: true });
  })
);

app.delete(
  '/api/clientes/:id',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('codigo_cliente', sql.Int, idEntero(req.params.id))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_Cliente_Eliminar');
    res.json({ ok: true });
  })
);

/* ------------------------------ Tipos de impuesto ------------------------------ */
function validarPorcentaje(v) {
  const n = Number(v.porcentaje);
  if (!Number.isFinite(n) || n < 0 || n > 100) throw new ErrorHttp(400, 'El porcentaje debe estar entre 0 y 100.');
  v.porcentaje = n;
}

app.get(
  '/api/impuestos',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('texto', VC(100), textoBusqueda(req.query.texto))
      .input('estado', sql.Char(1), filtroEstado(req.query.estado))
      .execute('dbo.usp_TipoImpuesto_Listar');
    res.json(r.recordset);
  })
);

app.get(
  '/api/impuestos/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('codigo_tipo_impuesto', sql.Int, idEntero(req.params.id))
      .execute('dbo.usp_TipoImpuesto_Obtener');
    if (!r.recordset.length) throw new ErrorHttp(404, 'El tipo de impuesto no existe.');
    res.json(r.recordset[0]);
  })
);

app.post(
  '/api/impuestos',
  requiereSesion,
  envolver(async (req, res) => {
    const v = leerCampos(req.body, CAMPOS_IMPUESTO);
    validarPorcentaje(v);
    const q = req.ses.pool.request();
    aplicarEntradas(q, CAMPOS_IMPUESTO, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    q.output('codigo_tipo_impuesto', sql.Int);
    const r = await q.execute('dbo.usp_TipoImpuesto_Insertar');
    res.status(201).json({ codigo_tipo_impuesto: r.output.codigo_tipo_impuesto });
  })
);

app.put(
  '/api/impuestos/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const v = leerCampos(req.body, CAMPOS_IMPUESTO);
    validarPorcentaje(v);
    const q = req.ses.pool.request().input('codigo_tipo_impuesto', sql.Int, idEntero(req.params.id));
    aplicarEntradas(q, CAMPOS_IMPUESTO, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    await q.execute('dbo.usp_TipoImpuesto_Actualizar');
    res.json({ ok: true });
  })
);

app.delete(
  '/api/impuestos/:id',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('codigo_tipo_impuesto', sql.Int, idEntero(req.params.id))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_TipoImpuesto_Eliminar');
    res.json({ ok: true });
  })
);

/* ------------------------------ Productos y servicios ------------------------------ */
function prepararProducto(body) {
  const v = leerCampos(body, CAMPOS_PRODUCTO);
  v.precio = aNumero(v.precio, 'precio');
  return v;
}

app.get(
  '/api/productos',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('texto', VC(100), textoBusqueda(req.query.texto))
      .input('estado', sql.Char(1), filtroEstado(req.query.estado))
      .execute('dbo.usp_Producto_Listar');
    res.json(r.recordset);
  })
);

app.get(
  '/api/productos/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('codigo_producto', sql.Int, idEntero(req.params.id))
      .execute('dbo.usp_Producto_Obtener');
    if (!r.recordset.length) throw new ErrorHttp(404, 'El producto no existe.');
    res.json(r.recordset[0]);
  })
);

app.post(
  '/api/productos',
  requiereSesion,
  envolver(async (req, res) => {
    const v = prepararProducto(req.body);
    const q = req.ses.pool.request();
    aplicarEntradas(q, CAMPOS_PRODUCTO, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    q.output('codigo_producto', sql.Int);
    const r = await q.execute('dbo.usp_Producto_Insertar');
    res.status(201).json({ codigo_producto: r.output.codigo_producto });
  })
);

app.put(
  '/api/productos/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const v = prepararProducto(req.body);
    const q = req.ses.pool.request().input('codigo_producto', sql.Int, idEntero(req.params.id));
    aplicarEntradas(q, CAMPOS_PRODUCTO, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    await q.execute('dbo.usp_Producto_Actualizar');
    res.json({ ok: true });
  })
);

app.delete(
  '/api/productos/:id',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('codigo_producto', sql.Int, idEntero(req.params.id))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_Producto_Eliminar');
    res.json({ ok: true });
  })
);

/* ------------------------------ Notas de crédito / débito ------------------------------ */
function filtroTipoNota(valor) {
  if (valor === undefined || valor === '' || valor === 'T') return null;
  if (valor !== 'C' && valor !== 'D') throw new ErrorHttp(400, 'El tipo debe ser C o D.');
  return valor;
}

function prepararNota(body) {
  const v = leerCampos(body, CAMPOS_NOTA);
  v.monto = aNumero(v.monto, 'monto', { min: 0, exclusivo: true });
  return v;
}

app.get(
  '/api/notas',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('texto', VC(100), textoBusqueda(req.query.texto))
      .input('tipo', sql.Char(1), filtroTipoNota(req.query.tipo))
      .execute('dbo.usp_Nota_Listar');
    res.json(r.recordset);
  })
);

app.get(
  '/api/notas/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('numero_nota', sql.Int, idEntero(req.params.id))
      .execute('dbo.usp_Nota_Obtener');
    if (!r.recordset.length) throw new ErrorHttp(404, 'La nota no existe.');
    res.json(r.recordset[0]);
  })
);

app.post(
  '/api/notas',
  requiereSesion,
  envolver(async (req, res) => {
    const v = prepararNota(req.body);
    const q = req.ses.pool.request();
    aplicarEntradas(q, CAMPOS_NOTA, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    q.output('numero_nota', sql.Int);
    const r = await q.execute('dbo.usp_Nota_Insertar');
    res.status(201).json({ numero_nota: r.output.numero_nota });
  })
);

app.put(
  '/api/notas/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const v = prepararNota(req.body);
    const q = req.ses.pool.request().input('numero_nota', sql.Int, idEntero(req.params.id));
    aplicarEntradas(q, CAMPOS_NOTA, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    await q.execute('dbo.usp_Nota_Actualizar');
    res.json({ ok: true });
  })
);

app.delete(
  '/api/notas/:id',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('numero_nota', sql.Int, idEntero(req.params.id))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_Nota_Eliminar');
    res.json({ ok: true });
  })
);

/* ------------------------------ Facturas y detalle ------------------------------ */
function prepararFactura(body) {
  const v = leerCampos(body, CAMPOS_FACTURA);
  v.tipo_cambio = aNumero(v.tipo_cambio, 'tipo_cambio', { min: 0, max: 99999999, decimales: 4, exclusivo: true });
  return v;
}

function leerCantidad(valor) {
  return aNumero(valor, 'cantidad', { min: 0, max: 999999999, decimales: 3, exclusivo: true });
}

// Convierte las líneas recibidas en el JSON que espera usp_Factura_Insertar
function leerLineas(lineas) {
  if (!Array.isArray(lineas) || lineas.length === 0) throw new ErrorHttp(400, 'La factura debe tener al menos una línea.');
  if (lineas.length > 200) throw new ErrorHttp(400, 'Una factura admite como máximo 200 líneas.');
  return JSON.stringify(
    lineas.map((l) => ({ codigo_producto: idEntero(l?.codigo_producto), cantidad: leerCantidad(l?.cantidad) }))
  );
}

app.get(
  '/api/facturas',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('texto', VC(100), textoBusqueda(req.query.texto))
      .execute('dbo.usp_Factura_Listar');
    res.json(r.recordset);
  })
);

app.get(
  '/api/facturas/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('num_factura', sql.Int, idEntero(req.params.id))
      .execute('dbo.usp_Factura_Obtener');
    if (!r.recordsets[0]?.length) throw new ErrorHttp(404, 'La factura no existe.');
    res.json({ ...r.recordsets[0][0], lineas: r.recordsets[1] || [] });
  })
);

app.post(
  '/api/facturas',
  requiereSesion,
  envolver(async (req, res) => {
    const v = prepararFactura(req.body);
    const lineas = leerLineas(req.body?.lineas);
    const q = req.ses.pool.request();
    aplicarEntradas(q, CAMPOS_FACTURA, v);
    q.input('lineas', sql.NVarChar(sql.MAX), lineas);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    q.output('num_factura', sql.Int);
    const r = await q.execute('dbo.usp_Factura_Insertar');
    res.status(201).json({ num_factura: r.output.num_factura });
  })
);

app.put(
  '/api/facturas/:id',
  requiereSesion,
  envolver(async (req, res) => {
    const v = prepararFactura(req.body);
    const q = req.ses.pool.request().input('num_factura', sql.Int, idEntero(req.params.id));
    aplicarEntradas(q, CAMPOS_FACTURA, v);
    q.input('id_sesion', sql.Int, req.ses.codAcceso);
    await q.execute('dbo.usp_Factura_Actualizar');
    res.json({ ok: true });
  })
);

app.delete(
  '/api/facturas/:id',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('num_factura', sql.Int, idEntero(req.params.id))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_Factura_Eliminar');
    res.json({ ok: true });
  })
);

app.post(
  '/api/facturas/:id/lineas',
  requiereSesion,
  envolver(async (req, res) => {
    const r = await req.ses.pool
      .request()
      .input('num_factura', sql.Int, idEntero(req.params.id))
      .input('codigo_producto', sql.Int, idEntero(req.body?.codigo_producto))
      .input('cantidad', sql.Decimal(18, 3), leerCantidad(req.body?.cantidad))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .output('numero_linea', sql.SmallInt)
      .execute('dbo.usp_FacturaDetalle_Insertar');
    res.status(201).json({ numero_linea: r.output.numero_linea });
  })
);

app.put(
  '/api/facturas/:id/lineas/:linea',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('num_factura', sql.Int, idEntero(req.params.id))
      .input('numero_linea', sql.SmallInt, idEntero(req.params.linea))
      .input('cantidad', sql.Decimal(18, 3), leerCantidad(req.body?.cantidad))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_FacturaDetalle_Actualizar');
    res.json({ ok: true });
  })
);

app.delete(
  '/api/facturas/:id/lineas/:linea',
  requiereSesion,
  envolver(async (req, res) => {
    await req.ses.pool
      .request()
      .input('num_factura', sql.Int, idEntero(req.params.id))
      .input('numero_linea', sql.SmallInt, idEntero(req.params.linea))
      .input('id_sesion', sql.Int, req.ses.codAcceso)
      .execute('dbo.usp_FacturaDetalle_Eliminar');
    res.json({ ok: true });
  })
);

/* ------------------------------ Reportes (REQ 007) ------------------------------ */
// Cada ruta llama a un usp_Reporte_* de la base; la app solo muestra lo que el procedimiento devuelva.
const MAX_FILAS_REPORTE = 2000; // el navegador solo recibe esta cantidad; el resto se acota con filtros

function leerFecha(valor, nombre) {
  if (typeof valor !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(valor))
    throw new ErrorHttp(400, `La fecha ${nombre} es obligatoria (formato AAAA-MM-DD).`);
  const [a, m, d] = valor.split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1, d));
  // se rechazan fechas imposibles como 2026-02-31
  if (a < 1900 || a > 2100 || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d)
    throw new ErrorHttp(400, `La fecha ${nombre} no es válida.`);
  return f;
}

function leerRango(query) {
  const desde = leerFecha(query.desde, 'desde');
  const hasta = leerFecha(query.hasta, 'hasta');
  if (desde > hasta) throw new ErrorHttp(400, 'La fecha desde no puede ser mayor que la fecha hasta.');
  return { desde, hasta };
}

async function ejecutarReporte(req, res, procedimiento, preparar) {
  const q = req.ses.pool.request();
  preparar(q);
  const filas = (await q.execute(procedimiento)).recordset || [];
  res.json({ total: filas.length, truncado: filas.length > MAX_FILAS_REPORTE, filas: filas.slice(0, MAX_FILAS_REPORTE) });
}

app.get(
  '/api/reportes/clientes',
  requiereSesion,
  envolver(async (req, res) => {
    const { desde, hasta } = leerRango(req.query);
    const est = req.query.estado === undefined || req.query.estado === '' ? 'T' : req.query.estado;
    if (!['A', 'I', 'T'].includes(est)) throw new ErrorHttp(400, 'El estado debe ser A, I o T.');
    await ejecutarReporte(req, res, 'dbo.usp_Reporte_Clientes', (q) => {
      q.input('fecha_desde', sql.Date, desde).input('fecha_hasta', sql.Date, hasta).input('estado', sql.Char(1), est);
    });
  })
);

app.get(
  '/api/reportes/facturas',
  requiereSesion,
  envolver(async (req, res) => {
    const { desde, hasta } = leerRango(req.query);
    await ejecutarReporte(req, res, 'dbo.usp_Reporte_Facturas', (q) => {
      q.input('fecha_desde', sql.Date, desde).input('fecha_hasta', sql.Date, hasta);
    });
  })
);

app.get(
  '/api/reportes/auditoria',
  requiereSesion,
  envolver(async (req, res) => {
    const { desde, hasta } = leerRango(req.query);
    await ejecutarReporte(req, res, 'dbo.usp_Reporte_Auditoria', (q) => {
      q.input('fecha_desde', sql.Date, desde)
        .input('fecha_hasta', sql.Date, hasta)
        .input('usuario', VC(128), textoBusqueda(req.query.usuario));
    });
  })
);

app.get(
  '/api/reportes/seguridad',
  requiereSesion,
  envolver(async (req, res) => {
    await ejecutarReporte(req, res, 'dbo.usp_Reporte_Seguridad', (q) => {
      q.input('usuario', sql.VarChar(128), textoBusqueda(req.query.usuario));
    });
  })
);

/* ------------------------------ Estáticos y errores ------------------------------ */
app.use(express.static(path.join(__dirname, 'public')));

app.use('/api', (req, res) => res.status(404).json({ error: 'Ruta no encontrada.' }));

// Errores de express (por ejemplo JSON mal formado)
app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'El cuerpo de la petición no es JSON válido.' });
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'La petición es demasiado grande.' });
  console.error(err);
  res.status(500).json({ error: 'Ocurrió un error inesperado en el servidor.' });
});

/* ------------------------------ Inactividad y cierre ------------------------------ */
// Las sesiones inactivas se cierran y quedan con su fecha/hora de salida en la bitácora.
setInterval(() => {
  const limite = Date.now() - CFG.minutosInactividad * 60 * 1000;
  for (const [sid, s] of sesiones) if (s.ultimo < limite) cerrarSesion(sid, 'inactividad');
}, 60 * 1000).unref();

const servidor = app.listen(CFG.puerto, () => {
  console.log(`Propi Facturación en http://localhost:${CFG.puerto}  (BD: ${CFG.servidor}/${CFG.baseDatos})`);
});

let cerrando = false;
async function apagar(senal) {
  if (cerrando) return;
  cerrando = true;
  console.log(`\n${senal}: cerrando sesiones y registrando salidas...`);
  servidor.close();
  await Promise.allSettled([...sesiones.keys()].map((sid) => cerrarSesion(sid, 'apagado del servidor')));
  process.exit(0);
}
process.on('SIGINT', () => apagar('SIGINT'));
process.on('SIGTERM', () => apagar('SIGTERM'));
