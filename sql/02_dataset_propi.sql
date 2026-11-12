/* =====================================================================
   PropiDB - Dataset de prueba (REQ 009): 1,000+ registros por tabla
   ---------------------------------------------------------------------
   Qué carga (aproximado):
     Barrio ............ 1,000 nuevos
     Cliente ........... 1,200 (cifrados igual que en la aplicación)
     Producto_Servicio . 1,200
     Factura ........... 1,500 (con totales calculados desde el detalle)
     Factura_Detalle ... ~3,000 (1 a 3 líneas por factura)
     Nota_Credito_Debito 1,000
     Bitacora_Acceso ... 1,000
     Bitacora_Auditoria  ~1,100 (se generan de verdad con los triggers,
                         al final, actualizando clientes y productos)

   Importante:
   - Ejecuten PRIMERO triggers_auditoria.sql, para que al final se
     generen las filas de la bitácora de auditoría.
   - Durante la carga los triggers se apagan (si no, la bitácora se
     llenaría con miles de filas de carga) y se vuelven a encender al
     terminar, incluso si algo falla.
   - Los datos sensibles de Cliente se cifran con la misma llave y el
     mismo formato que usan los procedimientos (VARCHAR + SHA2_256),
     así la aplicación los puede descifrar y buscar por hash.
   - Todo el script es UN solo lote: si el dataset ya fue cargado, se
     detiene sin duplicar nada.
   ===================================================================== */
USE PropiDB;
GO
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE direccion LIKE N'Dataset:%')
    THROW 50100, N'El dataset ya fue cargado. No se vuelve a cargar para no duplicar datos.', 1;

BEGIN TRY

    /* ---------- Apagar triggers de las tablas que se cargan ---------- */
    DISABLE TRIGGER ALL ON dbo.Barrio;
    DISABLE TRIGGER ALL ON dbo.Cliente;
    DISABLE TRIGGER ALL ON dbo.Producto_Servicio;
    DISABLE TRIGGER ALL ON dbo.Factura;
    DISABLE TRIGGER ALL ON dbo.Factura_Detalle;
    DISABLE TRIGGER ALL ON dbo.Nota_Credito_Debito;
    DISABLE TRIGGER ALL ON dbo.Bitacora_Acceso;

    /* ---------- Tablas auxiliares (temporales) ---------- */
    IF OBJECT_ID('tempdb..#n') IS NOT NULL DROP TABLE #n;
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    INTO #n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b;

    CREATE TABLE #nom    (rn INT PRIMARY KEY, v NVARCHAR(40));
    CREATE TABLE #ape    (rn INT PRIMARY KEY, v NVARCHAR(40));
    CREATE TABLE #emp    (rn INT PRIMARY KEY, v NVARCHAR(40));
    CREATE TABLE #motivo (rn INT PRIMARY KEY, v NVARCHAR(100));

    INSERT INTO #nom VALUES
      (1,N'María'),(2,N'José'),(3,N'Ana'),(4,N'Luis'),(5,N'Carmen'),(6,N'Carlos'),(7,N'Laura'),
      (8,N'Jorge'),(9,N'Sofía'),(10,N'Andrés'),(11,N'Daniela'),(12,N'Mario'),(13,N'Paola'),
      (14,N'Diego'),(15,N'Karla'),(16,N'Esteban'),(17,N'Valeria'),(18,N'Marco'),(19,N'Gabriela'),(20,N'Raúl');
    INSERT INTO #ape VALUES
      (1,N'Fernández'),(2,N'Solano'),(3,N'Vargas'),(4,N'Mora'),(5,N'Jiménez'),(6,N'Rojas'),(7,N'Castro'),
      (8,N'Araya'),(9,N'Calderón'),(10,N'Chaves'),(11,N'Quesada'),(12,N'Salazar'),(13,N'Brenes'),
      (14,N'Campos'),(15,N'Ulate'),(16,N'Zúñiga'),(17,N'Cordero'),(18,N'Alfaro'),(19,N'Barrantes'),(20,N'Núñez');
    INSERT INTO #emp VALUES
      (1,N'Inversiones'),(2,N'Desarrollos'),(3,N'Constructora'),(4,N'Servicios'),
      (5,N'Grupo'),(6,N'Corporación'),(7,N'Bienes Raíces'),(8,N'Comercial');
    INSERT INTO #motivo VALUES
      (1,N'Descuento por pronto pago'),(2,N'Corrección de monto facturado'),(3,N'Anulación parcial del servicio'),
      (4,N'Ajuste por tipo de cambio'),(5,N'Intereses por mora'),(6,N'Cargo adicional por gestión');

    /* Open de la llave de cifrado (fuera de la transacción, igual que los SP) */
    OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

    BEGIN TRANSACTION;

    /* ================= BARRIO: 1,000 nuevos ================= */
    CREATE TABLE #dist (rn INT PRIMARY KEY, id INT);
    INSERT INTO #dist
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_distrito), codigo_distrito FROM dbo.Distrito;
    DECLARE @cd INT = (SELECT COUNT(*) FROM #dist);

    INSERT INTO dbo.Barrio (codigo_distrito, nombre)
    SELECT d.id, CONCAT(N'Barrio ', n.n)
    FROM #n n
    JOIN #dist d ON d.rn = n.n % @cd + 1
    WHERE n.n <= 1000;

    /* ================= CLIENTE: 1,200 ================= */
    CREATE TABLE #bar (rn INT PRIMARY KEY, id INT);
    INSERT INTO #bar
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_barrio), codigo_barrio FROM dbo.Barrio;
    DECLARE @cb INT = (SELECT COUNT(*) FROM #bar);

    CREATE TABLE #act (rn INT PRIMARY KEY, cod VARCHAR(6));
    INSERT INTO #act
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_actividad_economica), codigo_actividad_economica
    FROM dbo.Actividad_Economica WHERE estado = 'A';
    DECLARE @ca INT = (SELECT COUNT(*) FROM #act);

    INSERT INTO dbo.Cliente
        (nombre, codigo_tipo_identificacion, numero_identificacion, hash_identificacion,
         codigo_barrio, direccion, profesion, codigo_actividad_economica,
         correo, telefono, fecha_registro, estado)
    SELECT
        CASE WHEN t.tipo = '02'
             THEN CONCAT(e.v, N' ', a1.v, N' S.A.')
             ELSE CONCAT(nm.v, N' ', a1.v, N' ', a2.v) END,
        t.tipo,
        ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), i.ident),
        HASHBYTES('SHA2_256', i.ident),
        b.id,
        CONVERT(VARCHAR(250), CONCAT('Dataset: Calle ', n.n % 40 + 1, ', casa ', n.n)),
        CASE WHEN t.tipo = '02' OR n.n % 4 = 0 THEN NULL
             ELSE CHOOSE(n.n % 6 + 1, 'Contador', 'Ingeniero', 'Docente', 'Abogado', 'Comerciante', 'Médico') END,
        ac.cod,
        ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), c.correo),
        ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), c.telefono),
        DATEADD(MINUTE, -(n.n % 1440), DATEADD(DAY, -(n.n % 700 + 1), GETDATE())),
        CASE WHEN n.n % 15 = 0 THEN 'I' ELSE 'A' END
    FROM #n n
    CROSS APPLY (SELECT tipo = CONVERT(CHAR(2),
                   CASE WHEN n.n % 10 < 6 THEN '01'
                        WHEN n.n % 10 < 8 THEN '02'
                        WHEN n.n % 10 = 8 THEN '03'
                        ELSE '04' END)) t
    CROSS APPLY (SELECT ident = CONVERT(VARCHAR(12),
                   CASE t.tipo
                        WHEN '01' THEN 100000000   + n.n * 7919   -- 9 dígitos
                        WHEN '02' THEN 3101000000  + n.n * 7919   -- 10 dígitos
                        WHEN '03' THEN 15500000000 + n.n * 7919   -- 11 dígitos
                        ELSE           4000000000  + n.n * 7919   -- 10 dígitos
                   END)) i
    CROSS APPLY (SELECT correo   = CONVERT(VARCHAR(150), CONCAT('cliente', RIGHT('0000' + CAST(n.n AS VARCHAR(5)), 4), '@propi.test')),
                        telefono = CONVERT(VARCHAR(20),  CONCAT('8', RIGHT('0000000' + CAST(1000000 + n.n * 131 % 9000000 AS VARCHAR(10)), 7)))) c
    JOIN #nom nm ON nm.rn = n.n % 20 + 1
    JOIN #ape a1 ON a1.rn = (n.n / 20) % 20 + 1
    JOIN #ape a2 ON a2.rn = (n.n * 3) % 20 + 1
    JOIN #emp e  ON e.rn  = n.n % 8 + 1
    JOIN #bar b  ON b.rn  = n.n % @cb + 1
    JOIN #act ac ON ac.rn = n.n % @ca + 1
    WHERE n.n <= 1200;

    /* ================= PRODUCTO_SERVICIO: 1,200 ================= */
    CREATE TABLE #uni (rn INT PRIMARY KEY, id VARCHAR(10));
    INSERT INTO #uni
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_unidad_medida), codigo_unidad_medida FROM dbo.Unidad_Medida;
    DECLARE @cu INT = (SELECT COUNT(*) FROM #uni);

    CREATE TABLE #timp (rn INT PRIMARY KEY, id INT);
    INSERT INTO #timp
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_tipo_impuesto), codigo_tipo_impuesto
    FROM dbo.Tipo_Impuesto WHERE estado = 'A';
    DECLARE @ct INT = (SELECT COUNT(*) FROM #timp);

    INSERT INTO dbo.Producto_Servicio
        (codigo_CABYS, descripcion, codigo_unidad_medida, precio, codigo_tipo_impuesto, estado)
    SELECT CONVERT(CHAR(13), 7211100000000 + n.n),
           CONVERT(VARCHAR(200),
               CONCAT(CHOOSE(n.n % 6 + 1, 'Venta de lote ', 'Comisión por intermediación ',
                             'Alquiler de local comercial ', 'Avalúo de propiedad ',
                             'Asesoría inmobiliaria ', 'Administración de propiedad '),
                      'ref. ', n.n)),
           u.id,
           CAST(50000 + (n.n * 7919 % 30000000) AS DECIMAL(18,2)),
           ti.id,
           CASE WHEN n.n % 20 = 0 THEN 'I' ELSE 'A' END
    FROM #n n
    JOIN #uni u   ON u.rn  = n.n % @cu + 1
    JOIN #timp ti ON ti.rn = n.n % @ct + 1
    WHERE n.n <= 1200;

    /* ================= FACTURA: 1,500 (totales en 0 por ahora) ================= */
    CREATE TABLE #cli (rn INT PRIMARY KEY, id INT);
    INSERT INTO #cli
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_cliente), codigo_cliente
    FROM dbo.Cliente WHERE estado = 'A';
    DECLARE @cc INT = (SELECT COUNT(*) FROM #cli);

    INSERT INTO dbo.Factura
        (codigo_cliente, fecha, cod_condicion_venta, codigo_medio_pago, codigo_moneda, tipo_cambio, observaciones)
    SELECT c.id,
           DATEADD(MINUTE, -(n.n * 17 % 1440), DATEADD(DAY, -(30 + n.n % 700), GETDATE())),
           CASE WHEN n.n % 3 = 0 THEN '02' ELSE '01' END,
           CHOOSE(n.n % 6 + 1, '01', '02', '03', '04', '06', '99'),
           CASE WHEN n.n % 10 = 0 THEN 'USD' ELSE 'CRC' END,
           CAST(CASE WHEN n.n % 10 = 0 THEN 515 + n.n % 20 ELSE 1 END AS DECIMAL(12,4)),
           CONVERT(VARCHAR(500), CONCAT('Factura de dataset ', n.n))
    FROM #n n
    JOIN #cli c ON c.rn = n.n % @cc + 1
    WHERE n.n <= 1500;

    /* ================= FACTURA_DETALLE: 1 a 3 líneas por factura ================= */
    CREATE TABLE #prod (rn INT PRIMARY KEY, id INT, precio DECIMAL(18,2), pct DECIMAL(5,2));
    INSERT INTO #prod
    SELECT ROW_NUMBER() OVER (ORDER BY ps.codigo_producto), ps.codigo_producto, ps.precio, ti.porcentaje
    FROM dbo.Producto_Servicio ps
    JOIN dbo.Tipo_Impuesto ti ON ti.codigo_tipo_impuesto = ps.codigo_tipo_impuesto
    WHERE ps.estado = 'A';
    DECLARE @cp INT = (SELECT COUNT(*) FROM #prod);

    INSERT INTO dbo.Factura_Detalle
        (num_factura, numero_linea, codigo_producto, cantidad, precio_unitario, impuesto, monto_linea)
    SELECT f.num_factura,
           l.n,
           p.id,
           q.cant,
           p.precio,
           CAST(ROUND(q.cant * p.precio * p.pct / 100.0, 2) AS DECIMAL(18,2)),
           CAST(q.cant * p.precio AS DECIMAL(18,2))
    FROM dbo.Factura f
    CROSS JOIN (VALUES (1), (2), (3)) l(n)
    CROSS APPLY (SELECT cant = CAST(1 + ((f.num_factura + l.n) % 4) AS DECIMAL(18,3))) q
    JOIN #prod p ON p.rn = (f.num_factura * 7 + l.n * 13) % @cp + 1
    WHERE l.n <= 1 + (f.num_factura % 3)
      AND NOT EXISTS (SELECT 1 FROM dbo.Factura_Detalle d WHERE d.num_factura = f.num_factura);

    /* Totales de cada factura calculados desde su detalle */
    UPDATE f
    SET f.subtotal        = t.subtotal,
        f.total_impuestos = t.impuestos,
        f.monto_total     = t.subtotal + t.impuestos
    FROM dbo.Factura f
    JOIN (SELECT num_factura,
                 SUM(monto_linea) AS subtotal,
                 SUM(impuesto)    AS impuestos
          FROM dbo.Factura_Detalle
          GROUP BY num_factura) t ON t.num_factura = f.num_factura;

    /* ================= NOTA_CREDITO_DEBITO: 1,000 ================= */
    CREATE TABLE #fac (rn INT PRIMARY KEY, num_factura INT, fecha DATETIME, monto_total DECIMAL(18,2));
    INSERT INTO #fac
    SELECT ROW_NUMBER() OVER (ORDER BY num_factura), num_factura, fecha, monto_total
    FROM dbo.Factura WHERE monto_total > 0;
    DECLARE @cf INT = (SELECT COUNT(*) FROM #fac);

    INSERT INTO dbo.Nota_Credito_Debito (fecha, num_factura, tipo, motivo, monto)
    SELECT DATEADD(DAY, n.n % 20, f.fecha),
           f.num_factura,
           CASE WHEN n.n % 4 = 0 THEN 'D' ELSE 'C' END,
           CONVERT(VARCHAR(500), m.v),
           CAST(ROUND(f.monto_total * (1 + n.n % 10) / 20.0, 2) AS DECIMAL(18,2))
    FROM #n n
    JOIN #fac f    ON f.rn = n.n % @cf + 1
    JOIN #motivo m ON m.rn = n.n % 6 + 1
    WHERE n.n <= 1000;

    /* ================= BITACORA_ACCESO: 1,000 ================= */
    INSERT INTO dbo.Bitacora_Acceso (usuario, terminal, direccion_ip, fecha_ingreso, fecha_salida, fecha_registro)
    SELECT CHOOSE(n.n % 3 + 1, 'usr_admin', 'usr_digitador', 'usr_consulta'),
           CONCAT('PC-PROPI-', RIGHT('00' + CAST(n.n % 25 + 1 AS VARCHAR(3)), 2)),
           CONCAT('192.168.1.', n.n % 250 + 1),
           x.ing,
           DATEADD(MINUTE, 5 + n.n % 235, x.ing),
           x.ing
    FROM #n n
    CROSS APPLY (SELECT ing = DATEADD(MINUTE, -(n.n * 53 % 1440), DATEADD(DAY, -(n.n % 60 + 1), GETDATE()))) x
    WHERE n.n <= 1000;

    COMMIT TRANSACTION;
    CLOSE SYMMETRIC KEY sk_propi_clientes;

    /* ---------- Encender triggers otra vez ---------- */
    ENABLE TRIGGER ALL ON dbo.Barrio;
    ENABLE TRIGGER ALL ON dbo.Cliente;
    ENABLE TRIGGER ALL ON dbo.Producto_Servicio;
    ENABLE TRIGGER ALL ON dbo.Factura;
    ENABLE TRIGGER ALL ON dbo.Factura_Detalle;
    ENABLE TRIGGER ALL ON dbo.Nota_Credito_Debito;
    ENABLE TRIGGER ALL ON dbo.Bitacora_Acceso;

    /* ================= BITACORA_AUDITORIA: ~1,100 filas reales =================
       Con los triggers encendidos, estas modificaciones generan filas
       de tipo U con el antes y el después en JSON. */
    EXEC sp_set_session_context N'id_sesion', 2001;

    UPDATE dbo.Cliente
    SET direccion = CONVERT(VARCHAR(250), CONCAT('Actualizada: ', ISNULL(direccion, '')))
    WHERE codigo_cliente IN (SELECT TOP (600) codigo_cliente FROM dbo.Cliente ORDER BY codigo_cliente);

    UPDATE dbo.Producto_Servicio
    SET descripcion = CONVERT(VARCHAR(200), CONCAT(descripcion, ' (actualizado)'))
    WHERE codigo_producto IN (SELECT TOP (500) codigo_producto FROM dbo.Producto_Servicio ORDER BY codigo_producto);

    DROP TABLE IF EXISTS #n, #nom, #ape, #emp, #motivo, #dist, #bar, #act, #uni, #timp, #cli, #prod, #fac;
    PRINT N'Dataset cargado correctamente.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes')
        CLOSE SYMMETRIC KEY sk_propi_clientes;

    /* Pase lo que pase, dejar los triggers encendidos */
    ENABLE TRIGGER ALL ON dbo.Barrio;
    ENABLE TRIGGER ALL ON dbo.Cliente;
    ENABLE TRIGGER ALL ON dbo.Producto_Servicio;
    ENABLE TRIGGER ALL ON dbo.Factura;
    ENABLE TRIGGER ALL ON dbo.Factura_Detalle;
    ENABLE TRIGGER ALL ON dbo.Nota_Credito_Debito;
    ENABLE TRIGGER ALL ON dbo.Bitacora_Acceso;

    THROW;
END CATCH
GO

/* =====================================================================
   VERIFICACIÓN: filas por tabla
   ===================================================================== */
SELECT t.name AS tabla, SUM(p.row_count) AS filas
FROM sys.tables t
JOIN sys.dm_db_partition_stats p
  ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY filas DESC, t.name;

/* Los totales de cada factura deben cuadrar con su detalle (debe dar 0 filas) */
SELECT f.num_factura
FROM dbo.Factura f
JOIN (SELECT num_factura, SUM(monto_linea) AS s, SUM(impuesto) AS i
      FROM dbo.Factura_Detalle GROUP BY num_factura) d ON d.num_factura = f.num_factura
WHERE f.subtotal <> d.s OR f.total_impuestos <> d.i OR f.monto_total <> d.s + d.i;

/* Los datos sensibles se leen descifrados (así los verá el frontend) */
OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;
SELECT TOP (5) codigo_cliente, nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono
FROM dbo.Cliente
ORDER BY codigo_cliente DESC;
CLOSE SYMMETRIC KEY sk_propi_clientes;
GO
