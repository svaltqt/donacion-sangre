// P-16 (reporte de donaciones) y P-17 (reporte de inventario): genera los Excel y los verifica.
//
// El navegador no se usa. Para no probar una copia, este script EXTRAE el código de
// frontend/src/pages/Reportes.jsx (generar, descargarExcel, kpis y sus ayudas) y lo ejecuta tal cual
// con la misma librería `xlsx` del frontend. Solo se sustituyen los servicios de axios por
// llamadas HTTP a las mismas rutas de services/api.js (bancos, donaciones/banco/{id},
// inventario/banco/{id}) con el token del super admin, y los setState por variables.
// Después se abre cada archivo con xlsx y se comparan columnas y filas con los datos de la API
// obtenidos por un camino independiente (GET /api/donaciones, que es solo del super admin).
//
// Fuera de alcance (UI): el clic de descarga del navegador, la tabla en pantalla y los selectores de fecha.
// Requiere el backend en $API, `npm install` hecho en frontend/ y los datos de las tandas anteriores.
// Añade sus veredictos a evidencias/verificaciones-acceso.log; archivos en evidencias/P-16|P-17/archivos/.

const fs = require('fs');
const path = require('path');
const API = process.env.API || 'http://localhost:8081';
const RAIZ = path.join(__dirname, '..');
const EVID = path.join(RAIZ, 'evidencias');
const LOG = path.join(EVID, 'verificaciones-acceso.log');
const FRONT = path.join(RAIZ, '..', '..', 'frontend');
const XLSX = require(path.join(FRONT, 'node_modules', 'xlsx'));
const SRC = fs.readFileSync(path.join(FRONT, 'src', 'pages', 'Reportes.jsx'), 'utf8');

let caso = '';
function registrar(texto, resultado, detalle = '') {
  fs.appendFileSync(LOG, `${caso}|${resultado}|${texto}|${detalle}\n`);
  console.log(`    ${resultado}: ${texto}${detalle ? ` (${detalle})` : ''}`);
}
function verificar(texto, ok, detalle = '') { registrar(texto, ok ? 'PASA' : 'FALLA', detalle); }
function igual(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

// ── Extracción del código de la aplicación ──────────────────────────────────
function trozo(inicio, fin) {
  const i = SRC.indexOf(inicio);
  const j = SRC.indexOf(fin, i);
  if (i < 0 || j < 0) throw new Error(`No se encontró en Reportes.jsx: ${inicio} .. ${fin}`);
  return SRC.slice(i, j);
}
const CODIGO = [
  trozo('function hoyStr()', 'function fromYMD'),                  // hoyStr y toYMD
  trozo('const fechaAYMD', '// ── Generar preview'),
  trozo('const generar = async', '// ── Descargar Excel'),
  trozo('const descargarExcel = () =>', '// ── KPIs de resumen'),
  trozo('const kpis = () =>', '// ── Presets'),
].join('\n');

function crearReporte({ tipo, desde, hasta, servicios }) {
  const fabrica = new Function(
    'tipoSeleccionado', 'fechaDesde', 'fechaHasta', 'bancoService', 'donacionService', 'inventarioService', 'XLSX',
    `let datos = [];
     const setDatos = (d) => { datos = d; };
     const setError = () => {}; const setGenerando = () => {}; const setGenerado = () => {};
     ${CODIGO}
     return { generar, descargarExcel, kpis, datos: () => datos };`
  );
  return fabrica(tipo, desde, hasta, servicios.bancoService, servicios.donacionService, servicios.inventarioService, XLSX);
}

// ── HTTP ────────────────────────────────────────────────────────────────────
async function http(metodo, ruta, token, cuerpo) {
  const r = await fetch(API + ruta, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  const texto = await r.text();
  let data; try { data = JSON.parse(texto); } catch { data = texto; }
  if (!r.ok) throw Object.assign(new Error(`HTTP ${r.status} ${ruta}`), { response: { status: r.status, data } });
  return { data };
}

const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
function leerHoja(archivo) {
  const libro = XLSX.readFile(archivo);
  const nombre = libro.SheetNames[0];
  const hoja = libro.Sheets[nombre];
  return { hojas: libro.SheetNames, filas: XLSX.utils.sheet_to_json(hoja), csv: XLSX.utils.sheet_to_csv(hoja), cabecera: XLSX.utils.sheet_to_json(hoja, { header: 1 })[0] };
}

(async () => {
  const login = await http('POST', '/api/v1/auth/login', null, { correo: 'super.admin@test.com', contrasena: 'Admin123*' });
  const token = login.data.token;
  const servicios = {
    bancoService: { listarTodos: () => http('GET', '/api/bancos', token) },
    donacionService: { listarPorBanco: (id) => http('GET', `/api/donaciones/banco/${id}`, token) },
    inventarioService: { listarPorBanco: (id) => http('GET', `/api/inventario/banco/${id}`, token) },
  };
  const hoy = new Date();
  const hace30 = new Date(hoy); hace30.setDate(hace30.getDate() - 30);
  const manana = new Date(hoy); manana.setDate(manana.getDate() + 1);
  const hoyS = ymd(hoy), hace30S = ymd(hace30), mananaS = ymd(manana);

  // ═════ P-16  Reporte de donaciones ═════
  caso = 'P-16';
  const dirP16 = path.join(EVID, 'P-16', 'archivos');
  fs.rmSync(dirP16, { recursive: true, force: true }); fs.mkdirSync(dirP16, { recursive: true });
  console.log('\n=== P-16 ===');
  const todasDon = (await http('GET', '/api/donaciones', token)).data;   // camino independiente
  fs.writeFileSync(path.join(EVID, 'P-16', 'datos-api-donaciones.json'), JSON.stringify(todasDon, null, 2));

  const rep = crearReporte({ tipo: 'DONACIONES', desde: hace30S, hasta: hoyS, servicios });
  await rep.generar();
  const datos = rep.datos();
  const esperadas = todasDon.filter(d => d.fechaDonacion >= hace30S && d.fechaDonacion <= hoyS);
  verificar('El reporte (rango ultimos 30 dias) trae las mismas donaciones que la API', igual(datos.map(d => d.id).sort((a, b) => a - b), esperadas.map(d => d.id).sort((a, b) => a - b)), `${datos.length} registros`);
  verificar('Orden por fecha de donacion descendente', datos.every((d, i) => i === 0 || datos[i - 1].fechaDonacion >= d.fechaDonacion));
  const k = rep.kpis();
  const compl = esperadas.filter(d => d.estado === 'COMPLETADA');
  verificar('Indicadores: Total / Completadas / Pendientes / ml recolectados coinciden con la API',
    igual(k.map(x => x.valor), [esperadas.length, compl.length, esperadas.filter(d => d.estado === 'PENDIENTE').length, compl.reduce((s, d) => s + (d.cantidadMl || 0), 0)]),
    k.map(x => `${x.label}=${x.valor}`).join(', '));

  process.chdir(dirP16);
  const antes = new Set(fs.readdirSync(dirP16));
  rep.descargarExcel();
  const nuevos = fs.readdirSync(dirP16).filter(f => !antes.has(f));
  verificar('Se genera un archivo .xlsx', nuevos.length === 1 && nuevos[0].endsWith('.xlsx'), nuevos.join(', '));
  const archivo = path.join(dirP16, nuevos[0] || '');
  verificar('El nombre sigue el patron donavida_donaciones_<desde>_a_<hasta>_<AAAAMMDD>.xlsx',
    new RegExp(`^donavida_donaciones_${hace30S}_a_${hoyS}_\\d{8}\\.xlsx$`).test(nuevos[0] || ''), nuevos[0]);
  const cab = Buffer.alloc(2); const fd = fs.openSync(archivo, 'r'); fs.readSync(fd, cab, 0, 2, 0); fs.closeSync(fd);
  verificar('El archivo es un paquete OOXML valido (cabecera PK)', cab.toString() === 'PK', `${fs.statSync(archivo).size} bytes`);
  const x = leerHoja(archivo);
  verificar('El archivo se abre y tiene una hoja llamada "Donaciones"', igual(x.hojas, ['Donaciones']));
  const COLS_DON = ['ID', 'Fecha donación', 'Donante', 'Tipo sangre', 'Banco', 'Cantidad (ml)', 'Hemoglobina (g/dL)', 'Presión arterial', 'Estado', 'Observaciones', 'ID Solicitud'];
  verificar('Columnas del Excel de donaciones', igual(x.cabecera, COLS_DON), (x.cabecera || []).join(' | '));
  verificar('Una fila por donacion del reporte', x.filas.length === datos.length, `${x.filas.length} filas`);
  const porId = Object.fromEntries(todasDon.map(d => [d.id, d]));
  const malas = x.filas.filter(f => {
    const d = porId[f['ID']]; if (!d) return true;
    return f['Donante'] !== `${d.usuarioNombre || ''} ${d.usuarioApellido || ''}`.trim() || f['Estado'] !== d.estado
      || f['Banco'] !== d.bancoNombre || f['Cantidad (ml)'] !== d.cantidadMl || f['Fecha donación'] !== d.fechaDonacion
      || (d.usuarioNombre ? f['Donante'].trim() === '' : false);
  });
  verificar('Cada fila coincide con la donacion de la API (donante, banco, estado, ml, fecha)', malas.length === 0, malas.length ? `distintas: ${malas.map(f => f['ID']).join(',')}` : '');
  const sd10 = x.filas.find(f => f['Observaciones'] === 'SD-10');
  verificar('SD-17: el reporte incluye la donacion de SD-10 con sus datos clinicos (13.5 g/dL, 120/80, COMPLETADA)',
    !!sd10 && sd10['Hemoglobina (g/dL)'] === 13.5 && sd10['Presión arterial'] === '120/80' && sd10['Estado'] === 'COMPLETADA', sd10 ? JSON.stringify(sd10) : 'no aparece');
  verificar('Donaciones sin solicitud muestran "—" en ID Solicitud', x.filas.filter(f => f['ID Solicitud'] === '—').length === datos.filter(d => !d.solicitudId).length);
  fs.writeFileSync(path.join(EVID, 'P-16', 'contenido-excel.csv'), '﻿' + x.csv);

  // Rango sin registros (un mes de 2020)
  const vacio = crearReporte({ tipo: 'DONACIONES', desde: '2020-03-01', hasta: '2020-03-31', servicios });
  await vacio.generar();
  verificar('Rango de 2020: el reporte no trae registros', vacio.datos().length === 0);
  const antes2 = new Set(fs.readdirSync(dirP16));
  vacio.descargarExcel();
  verificar('Rango vacio: no se genera ningun archivo', fs.readdirSync(dirP16).every(f => antes2.has(f)));
  verificar('Rango vacio: la UI tiene un mensaje "No hay datos que coincidan con los filtros aplicados."', SRC.includes('No hay datos que coincidan con los filtros aplicados.'), 'segun el codigo de Reportes.jsx; no se vio en pantalla');
  registrar('Rango vacio: el codigo no descarga archivo vacio (descargarExcel retorna si no hay datos); la HU no esta disponible para confirmar si debia descargarse un archivo solo con cabeceras', 'OBSERVADO', 'consulta funcional CF-13');
  registrar('Pantalla de reportes: tabla, tarjetas de indicadores, selector de fechas y clic de descarga (parte de UI)', 'BLOQUEADO', 'no ejecutable por API; el archivo se genero con el mismo codigo de la aplicacion fuera del navegador');

  // ═════ P-17  Reporte de inventario ═════
  caso = 'P-17';
  const dirP17 = path.join(EVID, 'P-17', 'archivos');
  fs.rmSync(dirP17, { recursive: true, force: true }); fs.mkdirSync(dirP17, { recursive: true });
  console.log('\n=== P-17 ===');
  const bancos = (await http('GET', '/api/bancos', token)).data;
  let inv = [];
  for (const b of bancos) inv = inv.concat((await http('GET', `/api/inventario/banco/${b.id}`, token)).data);
  fs.writeFileSync(path.join(EVID, 'P-17', 'datos-api-inventario.json'), JSON.stringify(inv, null, 2));

  const repI = crearReporte({ tipo: 'INVENTARIO', desde: hace30S, hasta: hoyS, servicios });
  await repI.generar();
  const di = repI.datos();
  verificar('El reporte de inventario (ultimos 30 dias por ultima actualizacion) trae todos los registros de la API', di.length === inv.length, `${di.length} registros`);
  const iBajo = di.map(d => d.bajoStock);
  verificar('Prioridad visual: los registros en bajo stock van primero', iBajo.every((v, i) => i === 0 || !(v && !iBajo[i - 1]) ), iBajo.map(v => v ? 'B' : 'ok').join(' '));
  const ki = repI.kpis();
  verificar('Indicadores: Registros / Tipos bajo stock / Unidades totales / Bancos cubiertos coinciden con la API',
    igual(ki.map(z => z.valor), [inv.length, inv.filter(d => d.bajoStock).length, inv.reduce((s, d) => s + d.unidadesDisponibles, 0), new Set(inv.map(d => d.bancoNombre)).size]),
    ki.map(z => `${z.label}=${z.valor}`).join(', '));
  process.chdir(dirP17);
  const antesI = new Set(fs.readdirSync(dirP17));
  repI.descargarExcel();
  const nuevosI = fs.readdirSync(dirP17).filter(f => !antesI.has(f));
  verificar('Se genera un archivo .xlsx', nuevosI.length === 1 && nuevosI[0].endsWith('.xlsx'), nuevosI.join(', '));
  verificar('El nombre sigue el patron donavida_inventario_<desde>_a_<hasta>_<AAAAMMDD>.xlsx',
    new RegExp(`^donavida_inventario_${hace30S}_a_${hoyS}_\\d{8}\\.xlsx$`).test(nuevosI[0] || ''), nuevosI[0]);
  const archI = path.join(dirP17, nuevosI[0] || '');
  const y = leerHoja(archI);
  verificar('El archivo se abre y tiene una hoja llamada "Inventario"', igual(y.hojas, ['Inventario']));
  const COLS_INV = ['Banco', 'Ciudad', 'Tipo sangre', 'Unidades disponibles', 'Unidades mínimas', 'Diferencia', 'Bajo stock', 'Última actualización'];
  verificar('Columnas del Excel de inventario', igual(y.cabecera, COLS_INV), (y.cabecera || []).join(' | '));
  verificar('Una fila por registro de inventario', y.filas.length === di.length, `${y.filas.length} filas`);
  const malasI = y.filas.filter((f, i) => {
    const d = di[i];
    return f['Banco'] !== d.bancoNombre || f['Tipo sangre'] !== d.tipoSangre || f['Unidades disponibles'] !== d.unidadesDisponibles
      || f['Unidades mínimas'] !== d.unidadesMinimas || f['Diferencia'] !== d.unidadesDisponibles - d.unidadesMinimas
      || f['Bajo stock'] !== (d.bajoStock ? 'SI' : 'NO');
  });
  verificar('Cada fila coincide con la API (banco, tipo, unidades, diferencia y SI/NO de bajo stock)', malasI.length === 0, malasI.length ? `${malasI.length} distintas` : '');
  verificar('SD-18: aparecen O+ (en bajo stock) y A+ / AB- (sin bajo stock) del banco de Medellin',
    y.filas.some(f => f['Tipo sangre'] === 'O+' && f['Banco'].includes('Medell') && f['Bajo stock'] === 'SI')
    && y.filas.some(f => f['Tipo sangre'] === 'A+' && f['Banco'].includes('Medell') && f['Bajo stock'] === 'NO')
    && y.filas.some(f => f['Tipo sangre'] === 'AB-' && f['Banco'].includes('Medell') && f['Bajo stock'] === 'NO' && f['Diferencia'] === 0),
    'AB- con disponibles = minimo (diferencia 0) no es bajo stock');
  verificar('"Ultima actualizacion" tiene formato de fecha legible', y.filas.every(f => /\d{1,2}\/\d{1,2}\/\d{4}/.test(String(f['Última actualización']))), String(y.filas[0] && y.filas[0]['Última actualización']));
  fs.writeFileSync(path.join(EVID, 'P-17', 'contenido-excel.csv'), '﻿' + y.csv);

  const futuro = crearReporte({ tipo: 'INVENTARIO', desde: mananaS, hasta: '', servicios });
  await futuro.generar();
  verificar('El filtro por ultima actualizacion funciona: desde manana no hay registros', futuro.datos().length === 0);
  const vaciaI = crearReporte({ tipo: 'INVENTARIO', desde: '2020-03-01', hasta: '2020-03-31', servicios });
  await vaciaI.generar();
  const antesI2 = new Set(fs.readdirSync(dirP17));
  vaciaI.descargarExcel();
  verificar('Rango de 2020: sin registros y sin archivo descargado', vaciaI.datos().length === 0 && fs.readdirSync(dirP17).every(f => antesI2.has(f)));
  registrar('Pantalla de reportes: resaltado visual de registros criticos, tabla y clic de descarga (parte de UI)', 'BLOQUEADO', 'no ejecutable por API');
})().catch(e => { console.error('ERROR', e.message, e.response ? JSON.stringify(e.response.data) : ''); process.exit(1); });
