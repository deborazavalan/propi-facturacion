'use strict';
/*
  Formulario de factura (REQ 002): encabezado + líneas en una sola ventana.
  - Factura nueva: las líneas se arman en pantalla y se envían juntas al guardar (usp_Factura_Insertar).
  - Factura existente: cada cambio de línea se envía enseguida (usp_FacturaDetalle_*), y "Guardar" actualiza el encabezado.
  El precio y el impuesto los calcula la base de datos; aquí solo se muestra una vista previa para quien digita.
  Usa $, el, api, mostrar, avisar, estado, ENTIDADES y formatoCelda de app.js.
*/

const FA = { num: null, lineas: [], productos: new Map() };
const fa = (id) => $(`#fa-${id}`);
const redondear = (n) => Math.round((n + Number.EPSILON) * 100) / 100;
const dinero = (v) => formatoCelda(v, 'dinero');

function errorFactura(texto) {
  const e = $('#factura-error');
  e.textContent = texto || '';
  mostrar(e, Boolean(texto));
}

function llenarSelect(sel, opciones, vacio, valor) {
  sel.replaceChildren(el('option', { value: '', texto: vacio }));
  for (const [v, t] of opciones) sel.append(el('option', { value: v, texto: t }));
  sel.disabled = false;
  if (valor !== undefined && valor !== null) sel.value = String(valor);
}

async function catalogoFactura(sel, catalogo, valor) {
  try {
    const filas = await api('GET', `/api/catalogos/${catalogo}`);
    llenarSelect(sel, filas.map((f) => [f.codigo, f.nombre]), 'Seleccione...', valor);
  } catch (err) {
    llenarSelect(sel, [], 'No se pudo cargar');
    sel.disabled = true;
  }
}

async function buscarClientes() {
  const sel = fa('cliente');
  const params = new URLSearchParams({ estado: 'A' });
  const texto = fa('buscar-cliente').value.trim();
  if (texto) params.set('texto', texto);
  try {
    const filas = await api('GET', `/api/clientes?${params}`);
    llenarSelect(
      sel,
      filas.map((c) => [c.codigo_cliente, `${c.nombre} (${c.numero_identificacion})`]),
      filas.length ? 'Seleccione un cliente...' : 'Sin resultados'
    );
  } catch (err) {
    errorFactura(err.message);
  }
}

async function buscarProductos() {
  const params = new URLSearchParams({ estado: 'A' });
  const texto = fa('buscar-producto').value.trim();
  if (texto) params.set('texto', texto);
  try {
    const filas = await api('GET', `/api/productos?${params}`);
    for (const p of filas) FA.productos.set(String(p.codigo_producto), p);
    llenarSelect(
      fa('producto'),
      filas.map((p) => [p.codigo_producto, `${p.descripcion} - ${dinero(p.precio)}`]),
      filas.length ? 'Seleccione un producto...' : 'Sin resultados'
    );
  } catch (err) {
    errorFactura(err.message);
  }
}

function pintarLineas() {
  const esNueva = FA.num === null;
  const permisos = estado.permisos.facturas;
  const cuerpo = fa('lineas');
  cuerpo.replaceChildren();

  if (!FA.lineas.length) {
    cuerpo.append(el('tr', {}, el('td', { clase: 'vacio', colspan: 6, texto: 'Agregue al menos un producto.' })));
  }

  FA.lineas.forEach((l, i) => {
    const cantidad = el('input', { type: 'number', min: '0.001', max: '999999999', step: '0.001', value: String(Number(l.cantidad)), 'aria-label': 'Cantidad' });
    cantidad.addEventListener('change', () => cambiarCantidad(i, cantidad));
    const acciones = el('td');
    if (esNueva || permisos.eliminar) {
      const quitar = el('button', { type: 'button', clase: 'peligro', texto: 'Quitar' });
      quitar.addEventListener('click', () => quitarLinea(i));
      acciones.append(quitar);
    }
    cuerpo.append(
      el('tr', {}, [
        el('td', { texto: l.producto }),
        el('td', {}, cantidad),
        el('td', { texto: dinero(l.precio_unitario) }),
        el('td', { texto: dinero(l.impuesto) }),
        el('td', { texto: dinero(l.monto_linea) }),
        acciones,
      ])
    );
  });

  const subtotal = redondear(FA.lineas.reduce((a, l) => a + Number(l.monto_linea), 0));
  const impuestos = redondear(FA.lineas.reduce((a, l) => a + Number(l.impuesto), 0));
  const fila = (titulo, valor, negrita) =>
    el('tr', { clase: negrita ? 'total' : '' }, [
      el('td', { colspan: 4, clase: 'derecha', texto: titulo }),
      el('td', { texto: dinero(valor) }),
      el('td'),
    ]);
  fa('totales').replaceChildren(fila('Subtotal', subtotal), fila('Impuestos', impuestos), fila('Total', redondear(subtotal + impuestos), true));
}

// Vista previa de una línea nueva (la base la vuelve a calcular al guardar).
function lineaLocal(producto, cantidad) {
  return {
    codigo_producto: Number(producto.codigo_producto),
    producto: producto.descripcion,
    cantidad,
    precio_unitario: Number(producto.precio),
    impuesto: redondear((cantidad * Number(producto.precio) * Number(producto.porcentaje)) / 100),
    monto_linea: redondear(cantidad * Number(producto.precio)),
    porcentaje: Number(producto.porcentaje),
  };
}

async function recargarLineas() {
  const f = await api('GET', `/api/facturas/${FA.num}`);
  FA.lineas = f.lineas;
  pintarLineas();
}

async function agregarLinea() {
  errorFactura('');
  const id = fa('producto').value;
  const cantidad = Number(fa('cantidad').value);
  if (!id) return errorFactura('Seleccione un producto.');
  if (!Number.isFinite(cantidad) || cantidad <= 0) return errorFactura('La cantidad debe ser mayor a 0.');
  try {
    if (FA.num === null) {
      FA.lineas.push(lineaLocal(FA.productos.get(id), cantidad));
      pintarLineas();
    } else {
      await api('POST', `/api/facturas/${FA.num}/lineas`, { codigo_producto: Number(id), cantidad });
      await recargarLineas();
    }
    fa('cantidad').value = '1';
  } catch (err) {
    errorFactura(err.message);
  }
}

async function cambiarCantidad(i, input) {
  errorFactura('');
  const cantidad = Number(input.value);
  const linea = FA.lineas[i];
  if (!Number.isFinite(cantidad) || cantidad <= 0) {
    input.value = String(Number(linea.cantidad));
    return errorFactura('La cantidad debe ser mayor a 0.');
  }
  try {
    if (FA.num === null) {
      const p = { codigo_producto: linea.codigo_producto, descripcion: linea.producto, precio: linea.precio_unitario, porcentaje: linea.porcentaje };
      FA.lineas[i] = lineaLocal(p, cantidad);
      pintarLineas();
    } else {
      await api('PUT', `/api/facturas/${FA.num}/lineas/${linea.numero_linea}`, { cantidad });
      await recargarLineas();
    }
  } catch (err) {
    input.value = String(Number(linea.cantidad));
    errorFactura(err.message);
  }
}

async function quitarLinea(i) {
  errorFactura('');
  try {
    if (FA.num === null) {
      FA.lineas.splice(i, 1);
      pintarLineas();
    } else {
      await api('DELETE', `/api/facturas/${FA.num}/lineas/${FA.lineas[i].numero_linea}`);
      await recargarLineas();
    }
  } catch (err) {
    errorFactura(err.message);
  }
}

async function abrirFactura(id) {
  avisar('');
  errorFactura('');
  FA.num = id === undefined ? null : id;
  FA.lineas = [];
  FA.productos.clear();
  let factura = null;
  if (FA.num !== null) {
    try {
      factura = await api('GET', `/api/facturas/${encodeURIComponent(FA.num)}`);
    } catch (err) {
      avisar(err.message, true);
      return;
    }
  }

  $('#factura-titulo').textContent = factura ? `Factura N.º ${factura.num_factura}` : 'Nueva factura';
  fa('buscar-cliente').value = '';
  fa('buscar-producto').value = '';
  fa('cantidad').value = '1';
  fa('cambio').value = factura ? String(Number(factura.tipo_cambio)) : '1';
  fa('obs').value = factura?.observaciones || '';
  FA.lineas = factura ? factura.lineas : [];
  pintarLineas();
  $('#dialogo-factura').showModal();

  await Promise.all([
    catalogoFactura(fa('condicion'), 'condicion_venta', factura ? factura.cod_condicion_venta : '01'),
    catalogoFactura(fa('medio'), 'medio_pago', factura ? factura.codigo_medio_pago : '01'),
    catalogoFactura(fa('moneda'), 'moneda', factura ? factura.codigo_moneda : 'CRC'),
    buscarProductos(),
    factura
      ? Promise.resolve(llenarSelect(fa('cliente'), [[factura.codigo_cliente, factura.cliente]], 'Seleccione...', factura.codigo_cliente))
      : buscarClientes(),
  ]);
}

fa('btn-cliente').addEventListener('click', buscarClientes);
fa('btn-producto').addEventListener('click', buscarProductos);
fa('btn-agregar').addEventListener('click', agregarLinea);
// Enter dentro de una caja de búsqueda busca, no guarda la factura
fa('buscar-cliente').addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter') {
    ev.preventDefault();
    buscarClientes();
  }
});
fa('buscar-producto').addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter') {
    ev.preventDefault();
    buscarProductos();
  }
});
fa('cantidad').addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter') {
    ev.preventDefault();
    agregarLinea();
  }
});
fa('cancelar').addEventListener('click', () => $('#dialogo-factura').close());
// Al cerrar se refresca la lista (en una factura existente las líneas ya se guardaron)
$('#dialogo-factura').addEventListener('close', () => {
  if (estado.actual === 'facturas' && estado.usuario) cargarLista();
});

$('#form-factura').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  errorFactura('');
  const datos = {
    codigo_cliente: fa('cliente').value,
    cod_condicion_venta: fa('condicion').value,
    codigo_medio_pago: fa('medio').value,
    codigo_moneda: fa('moneda').value,
    tipo_cambio: fa('cambio').value,
    observaciones: fa('obs').value,
  };
  const esNueva = FA.num === null;
  if (esNueva) {
    if (!FA.lineas.length) return errorFactura('Agregue al menos un producto a la factura.');
    datos.lineas = FA.lineas.map((l) => ({ codigo_producto: l.codigo_producto, cantidad: Number(l.cantidad) }));
  }

  const boton = fa('guardar');
  boton.disabled = true;
  try {
    let numero = FA.num;
    if (esNueva) numero = (await api('POST', '/api/facturas', datos)).num_factura;
    else await api('PUT', `/api/facturas/${encodeURIComponent(FA.num)}`, datos);
    $('#dialogo-factura').close();
    avisar(esNueva ? `Factura N.º ${numero} creada correctamente.` : `Factura N.º ${numero} actualizada correctamente.`);
  } catch (err) {
    errorFactura(err.message);
  } finally {
    boton.disabled = false;
  }
});
