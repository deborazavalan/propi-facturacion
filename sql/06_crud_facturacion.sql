/* =====================================================================
   PropiDB - REQ 002: procedimientos de Producto, Nota de crédito/débito,
   Factura y Detalle de factura (Persona B)
   ---------------------------------------------------------------------
   Todos validan, usan TRY/CATCH y transacción, y fijan el id de sesión
   para que los triggers de auditoría sepan quién hizo el cambio.
   Los permisos por rol los aplica 04_permisos_roles.sql (se vuelve a
   correr después de este script):
     usp_Producto_Listar / Obtener : administrador y digitador
     usp_Producto_Insertar / Actualizar / Eliminar : solo administrador
     usp_Factura_*, usp_FacturaDetalle_*, usp_Nota_* : digitador sin Eliminar
   Errores propios: 501xx producto, 502xx nota, 503xx factura.
   ===================================================================== */
USE PropiDB;
GO

-- [solo_actualizacion] catálogos nuevos para los formularios (ya incluidos en 00_script_completo.sql)
CREATE OR ALTER PROCEDURE dbo.usp_Catalogo_Listar
    @catalogo VARCHAR(30),
    @padre    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @catalogo = 'tipo_identificacion'
            SELECT CONVERT(VARCHAR(10), codigo_tipo_identificacion) AS codigo, descripcion AS nombre
              FROM dbo.Tipo_Identificacion WHERE estado = 'A' ORDER BY codigo_tipo_identificacion;
        ELSE IF @catalogo = 'provincia'
            SELECT CONVERT(VARCHAR(10), codigo_provincia) AS codigo, nombre
              FROM dbo.Provincia ORDER BY codigo_provincia;
        ELSE IF @catalogo = 'canton'
            SELECT CONVERT(VARCHAR(10), codigo_canton) AS codigo, nombre
              FROM dbo.Canton WHERE codigo_provincia = @padre ORDER BY nombre;
        ELSE IF @catalogo = 'distrito'
            SELECT CONVERT(VARCHAR(10), codigo_distrito) AS codigo, nombre
              FROM dbo.Distrito WHERE codigo_canton = @padre ORDER BY nombre;
        ELSE IF @catalogo = 'barrio'
            SELECT CONVERT(VARCHAR(10), codigo_barrio) AS codigo, nombre
              FROM dbo.Barrio WHERE codigo_distrito = @padre ORDER BY nombre;
        ELSE IF @catalogo = 'actividad_economica'
            SELECT codigo_actividad_economica AS codigo,
                   CONVERT(VARCHAR(200), codigo_actividad_economica + ' - ' + descripcion) AS nombre
              FROM dbo.Actividad_Economica WHERE estado = 'A' ORDER BY codigo_actividad_economica;
        ELSE IF @catalogo = 'condicion_venta'
            SELECT CONVERT(VARCHAR(10), cod_condicion_venta) AS codigo, descripcion AS nombre
              FROM dbo.Condicion_Venta ORDER BY cod_condicion_venta;
        ELSE IF @catalogo = 'medio_pago'
            SELECT CONVERT(VARCHAR(10), codigo_medio_pago) AS codigo, descripcion AS nombre
              FROM dbo.Medio_Pago ORDER BY codigo_medio_pago;
        ELSE IF @catalogo = 'moneda'
            SELECT CONVERT(VARCHAR(10), codigo_moneda) AS codigo,
                   CONVERT(VARCHAR(50), codigo_moneda + ' - ' + descripcion) AS nombre
              FROM dbo.Moneda ORDER BY codigo_moneda;
        ELSE IF @catalogo = 'unidad_medida'
            SELECT codigo_unidad_medida AS codigo,
                   CONVERT(VARCHAR(70), codigo_unidad_medida + ' - ' + descripcion) AS nombre
              FROM dbo.Unidad_Medida ORDER BY codigo_unidad_medida;
        ELSE IF @catalogo = 'tipo_impuesto'
            SELECT CONVERT(VARCHAR(10), codigo_tipo_impuesto) AS codigo,
                   CONVERT(VARCHAR(150), codigo_impuesto + '/' + tarifa + ' - ' + descripcion
                           + ' (' + CONVERT(VARCHAR(10), CONVERT(DECIMAL(5,2), porcentaje)) + ' %)') AS nombre
              FROM dbo.Tipo_Impuesto WHERE estado = 'A' ORDER BY codigo_impuesto, tarifa;
        ELSE
            THROW 50040, N'El catálogo solicitado no existe.', 1;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO
-- [fin_solo_actualizacion]

/* ---------------------------------------------------------------------
   PRODUCTO / SERVICIO
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Producto_Validar
    @codigo_CABYS         CHAR(13),
    @descripcion          VARCHAR(200),
    @codigo_unidad_medida VARCHAR(10),
    @precio               DECIMAL(18,2),
    @codigo_tipo_impuesto INT,
    @estado               CHAR(1)
AS
BEGIN
    SET NOCOUNT ON;
    IF @codigo_CABYS IS NULL OR LEN(@codigo_CABYS) <> 13 OR @codigo_CABYS LIKE '%[^0-9]%'
        THROW 50101, N'El código CABYS debe tener exactamente 13 dígitos.', 1;
    IF ISNULL(@descripcion, '') = ''
        THROW 50102, N'La descripción es obligatoria.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Unidad_Medida WHERE codigo_unidad_medida = @codigo_unidad_medida)
        THROW 50103, N'La unidad de medida no existe.', 1;
    IF @precio IS NULL OR @precio < 0
        THROW 50104, N'El precio no puede ser negativo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Tipo_Impuesto WHERE codigo_tipo_impuesto = @codigo_tipo_impuesto)
        THROW 50105, N'El tipo de impuesto no existe.', 1;
    IF @estado IS NULL OR @estado NOT IN ('A', 'I')
        THROW 50106, N'El estado debe ser A (activo) o I (inactivo).', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_Insertar
    @codigo_CABYS         CHAR(13),
    @descripcion          VARCHAR(200),
    @codigo_unidad_medida VARCHAR(10),
    @precio               DECIMAL(18,2),
    @codigo_tipo_impuesto INT,
    @estado               CHAR(1) = 'A',
    @id_sesion            INT = NULL,
    @codigo_producto      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @descripcion = LTRIM(RTRIM(@descripcion));
        EXEC dbo.usp_Producto_Validar @codigo_CABYS, @descripcion, @codigo_unidad_medida, @precio, @codigo_tipo_impuesto, @estado;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        INSERT INTO dbo.Producto_Servicio (codigo_CABYS, descripcion, codigo_unidad_medida, precio, codigo_tipo_impuesto, estado)
        VALUES (@codigo_CABYS, @descripcion, @codigo_unidad_medida, @precio, @codigo_tipo_impuesto, @estado);
        SET @codigo_producto = CONVERT(INT, SCOPE_IDENTITY());
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_Actualizar
    @codigo_producto      INT,
    @codigo_CABYS         CHAR(13),
    @descripcion          VARCHAR(200),
    @codigo_unidad_medida VARCHAR(10),
    @precio               DECIMAL(18,2),
    @codigo_tipo_impuesto INT,
    @estado               CHAR(1),
    @id_sesion            INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @descripcion = LTRIM(RTRIM(@descripcion));
        EXEC dbo.usp_Producto_Validar @codigo_CABYS, @descripcion, @codigo_unidad_medida, @precio, @codigo_tipo_impuesto, @estado;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        UPDATE dbo.Producto_Servicio
           SET codigo_CABYS = @codigo_CABYS, descripcion = @descripcion,
               codigo_unidad_medida = @codigo_unidad_medida, precio = @precio,
               codigo_tipo_impuesto = @codigo_tipo_impuesto, estado = @estado
         WHERE codigo_producto = @codigo_producto;
        IF @@ROWCOUNT = 0
            THROW 50107, N'El producto no existe.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_Eliminar
    @codigo_producto INT,
    @id_sesion       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context N'id_sesion', @id_sesion;
        BEGIN TRANSACTION;
        DELETE FROM dbo.Producto_Servicio WHERE codigo_producto = @codigo_producto;
        IF @@ROWCOUNT = 0
            THROW 50107, N'El producto no existe.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- si ya se facturó llega el error 547 (FK)
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Producto_Obtener
    @codigo_producto INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT codigo_producto, codigo_CABYS, descripcion, codigo_unidad_medida, precio, codigo_tipo_impuesto, estado
          FROM dbo.Producto_Servicio
         WHERE codigo_producto = @codigo_producto;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- @texto busca en la descripción o en el CABYS exacto; devuelve hasta 500 filas
CREATE OR ALTER PROCEDURE dbo.usp_Producto_Listar
    @texto  VARCHAR(100) = NULL,
    @estado CHAR(1)      = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @texto = NULLIF(LTRIM(RTRIM(@texto)), '');

        SELECT TOP (500)
               p.codigo_producto, p.codigo_CABYS, p.descripcion, p.codigo_unidad_medida, p.precio,
               p.codigo_tipo_impuesto, ti.porcentaje, p.estado
          FROM dbo.Producto_Servicio p
          JOIN dbo.Tipo_Impuesto ti ON ti.codigo_tipo_impuesto = p.codigo_tipo_impuesto
         WHERE (@estado IS NULL OR p.estado = @estado)
           AND (@texto IS NULL OR p.descripcion LIKE '%' + @texto + '%' OR p.codigo_CABYS = @texto)
         ORDER BY p.descripcion;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   NOTA DE CRÉDITO / DÉBITO
   Regla: las notas de crédito de una factura no pueden sumar más que
   el total de esa factura.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Nota_Validar
    @numero_nota INT,          -- NULL al insertar
    @num_factura INT,
    @tipo        CHAR(1),
    @motivo      VARCHAR(500),
    @monto       DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @total_factura DECIMAL(18,2);

    SELECT @total_factura = monto_total FROM dbo.Factura WHERE num_factura = @num_factura;
    IF @total_factura IS NULL
        THROW 50201, N'La factura indicada no existe.', 1;
    IF @tipo IS NULL OR @tipo NOT IN ('C', 'D')
        THROW 50202, N'El tipo debe ser C (crédito) o D (débito).', 1;
    IF ISNULL(@motivo, '') = ''
        THROW 50203, N'El motivo es obligatorio.', 1;
    IF @monto IS NULL OR @monto <= 0
        THROW 50204, N'El monto debe ser mayor a 0.', 1;

    IF @tipo = 'C'
       AND @monto + ISNULL((SELECT SUM(monto) FROM dbo.Nota_Credito_Debito
                             WHERE num_factura = @num_factura AND tipo = 'C'
                               AND numero_nota <> ISNULL(@numero_nota, 0)), 0) > @total_factura
        THROW 50205, N'Las notas de crédito no pueden superar el total de la factura.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Nota_Insertar
    @num_factura INT,
    @tipo        CHAR(1),
    @motivo      VARCHAR(500),
    @monto       DECIMAL(18,2),
    @id_sesion   INT = NULL,
    @numero_nota INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @motivo = LTRIM(RTRIM(@motivo));
        EXEC dbo.usp_Nota_Validar NULL, @num_factura, @tipo, @motivo, @monto;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        INSERT INTO dbo.Nota_Credito_Debito (num_factura, tipo, motivo, monto)
        VALUES (@num_factura, @tipo, @motivo, @monto);
        SET @numero_nota = CONVERT(INT, SCOPE_IDENTITY());
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Nota_Actualizar
    @numero_nota INT,
    @num_factura INT,
    @tipo        CHAR(1),
    @motivo      VARCHAR(500),
    @monto       DECIMAL(18,2),
    @id_sesion   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @motivo = LTRIM(RTRIM(@motivo));
        EXEC dbo.usp_Nota_Validar @numero_nota, @num_factura, @tipo, @motivo, @monto;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        UPDATE dbo.Nota_Credito_Debito
           SET num_factura = @num_factura, tipo = @tipo, motivo = @motivo, monto = @monto
         WHERE numero_nota = @numero_nota;
        IF @@ROWCOUNT = 0
            THROW 50206, N'La nota no existe.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Nota_Eliminar
    @numero_nota INT,
    @id_sesion   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context N'id_sesion', @id_sesion;
        BEGIN TRANSACTION;
        DELETE FROM dbo.Nota_Credito_Debito WHERE numero_nota = @numero_nota;
        IF @@ROWCOUNT = 0
            THROW 50206, N'La nota no existe.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Nota_Obtener
    @numero_nota INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT numero_nota, fecha, num_factura, tipo, motivo, monto
          FROM dbo.Nota_Credito_Debito
         WHERE numero_nota = @numero_nota;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- @texto: número de nota, número de factura o parte del nombre del cliente; @tipo: C, D o NULL (todas)
CREATE OR ALTER PROCEDURE dbo.usp_Nota_Listar
    @texto VARCHAR(100) = NULL,
    @tipo  CHAR(1)      = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @texto = NULLIF(LTRIM(RTRIM(@texto)), '');
        DECLARE @numero INT = TRY_CONVERT(INT, @texto);

        SELECT TOP (500)
               n.numero_nota, n.fecha, n.num_factura, c.nombre AS cliente, n.tipo, n.motivo, n.monto
          FROM dbo.Nota_Credito_Debito n
          JOIN dbo.Factura f ON f.num_factura = n.num_factura
          JOIN dbo.Cliente c ON c.codigo_cliente = f.codigo_cliente
         WHERE (@tipo IS NULL OR n.tipo = @tipo)
           AND (@texto IS NULL OR n.numero_nota = @numero OR n.num_factura = @numero
                               OR c.nombre LIKE '%' + @texto + '%')
         ORDER BY n.fecha DESC, n.numero_nota DESC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   FACTURA y DETALLE
   El precio y el impuesto de cada línea los calcula la base a partir del
   producto (el usuario solo indica producto y cantidad). Los totales del
   encabezado siempre se recalculan desde el detalle, dentro de la misma
   transacción.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Factura_Validar
    @codigo_cliente      INT,
    @cod_condicion_venta CHAR(2),
    @codigo_medio_pago   CHAR(2),
    @codigo_moneda       CHAR(3),
    @tipo_cambio         DECIMAL(12,4)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE codigo_cliente = @codigo_cliente AND estado = 'A')
        THROW 50301, N'El cliente no existe o está inactivo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Condicion_Venta WHERE cod_condicion_venta = @cod_condicion_venta)
        THROW 50302, N'La condición de venta no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Medio_Pago WHERE codigo_medio_pago = @codigo_medio_pago)
        THROW 50303, N'El medio de pago no existe.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Moneda WHERE codigo_moneda = @codigo_moneda)
        THROW 50304, N'La moneda no existe.', 1;
    IF @tipo_cambio IS NULL OR @tipo_cambio <= 0
        THROW 50305, N'El tipo de cambio debe ser mayor a 0.', 1;
END
GO

-- Interno: recalcula subtotal, impuestos y total de una factura desde su detalle
CREATE OR ALTER PROCEDURE dbo.usp_Factura_RecalcularTotales
    @num_factura INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE f
       SET f.subtotal        = ISNULL(t.subtotal, 0),
           f.total_impuestos = ISNULL(t.impuestos, 0),
           f.monto_total     = ISNULL(t.subtotal, 0) + ISNULL(t.impuestos, 0)
      FROM dbo.Factura f
      OUTER APPLY (SELECT SUM(d.monto_linea) AS subtotal, SUM(d.impuesto) AS impuestos
                     FROM dbo.Factura_Detalle d WHERE d.num_factura = f.num_factura) t
     WHERE f.num_factura = @num_factura;
END
GO

-- @lineas es un JSON: [{"codigo_producto":1,"cantidad":2}, ...] (mínimo una línea)
CREATE OR ALTER PROCEDURE dbo.usp_Factura_Insertar
    @codigo_cliente      INT,
    @cod_condicion_venta CHAR(2),
    @codigo_medio_pago   CHAR(2),
    @codigo_moneda       CHAR(3),
    @tipo_cambio         DECIMAL(12,4) = 1,
    @observaciones       VARCHAR(500)  = NULL,
    @lineas              NVARCHAR(MAX),
    @id_sesion           INT = NULL,
    @num_factura         INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @observaciones = NULLIF(LTRIM(RTRIM(@observaciones)), '');
        EXEC dbo.usp_Factura_Validar @codigo_cliente, @cod_condicion_venta, @codigo_medio_pago, @codigo_moneda, @tipo_cambio;

        IF ISJSON(@lineas) <> 1
            THROW 50306, N'Las líneas de la factura no tienen un formato válido.', 1;

        DECLARE @l TABLE (numero_linea SMALLINT IDENTITY(1,1) PRIMARY KEY, codigo_producto INT NULL, cantidad DECIMAL(18,3) NULL);
        INSERT INTO @l (codigo_producto, cantidad)
        SELECT x.codigo_producto, x.cantidad
          FROM OPENJSON(@lineas) j
         CROSS APPLY OPENJSON(j.[value]) WITH (codigo_producto INT '$.codigo_producto', cantidad DECIMAL(18,3) '$.cantidad') x
         ORDER BY CAST(j.[key] AS INT);

        IF NOT EXISTS (SELECT 1 FROM @l)
            THROW 50307, N'La factura debe tener al menos una línea.', 1;
        IF (SELECT COUNT(*) FROM @l) > 200
            THROW 50308, N'Una factura admite como máximo 200 líneas.', 1;
        IF EXISTS (SELECT 1 FROM @l WHERE codigo_producto IS NULL OR cantidad IS NULL OR cantidad <= 0)
            THROW 50309, N'Cada línea necesita un producto y una cantidad mayor a 0.', 1;
        IF EXISTS (SELECT 1 FROM @l l LEFT JOIN dbo.Producto_Servicio p ON p.codigo_producto = l.codigo_producto
                    WHERE p.codigo_producto IS NULL OR p.estado <> 'A')
            THROW 50310, N'Alguno de los productos no existe o está inactivo.', 1;

        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;

        INSERT INTO dbo.Factura (codigo_cliente, cod_condicion_venta, codigo_medio_pago, codigo_moneda, tipo_cambio, observaciones)
        VALUES (@codigo_cliente, @cod_condicion_venta, @codigo_medio_pago, @codigo_moneda, @tipo_cambio, @observaciones);
        SET @num_factura = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.Factura_Detalle (num_factura, numero_linea, codigo_producto, cantidad, precio_unitario, impuesto, monto_linea)
        SELECT @num_factura, l.numero_linea, l.codigo_producto, l.cantidad, p.precio,
               CAST(ROUND(l.cantidad * p.precio * ti.porcentaje / 100.0, 2) AS DECIMAL(18,2)),
               CAST(ROUND(l.cantidad * p.precio, 2) AS DECIMAL(18,2))
          FROM @l l
          JOIN dbo.Producto_Servicio p ON p.codigo_producto = l.codigo_producto
          JOIN dbo.Tipo_Impuesto ti    ON ti.codigo_tipo_impuesto = p.codigo_tipo_impuesto;

        EXEC dbo.usp_Factura_RecalcularTotales @num_factura;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Cambia solo el encabezado; las líneas se manejan con usp_FacturaDetalle_*
CREATE OR ALTER PROCEDURE dbo.usp_Factura_Actualizar
    @num_factura         INT,
    @codigo_cliente      INT,
    @cod_condicion_venta CHAR(2),
    @codigo_medio_pago   CHAR(2),
    @codigo_moneda       CHAR(3),
    @tipo_cambio         DECIMAL(12,4),
    @observaciones       VARCHAR(500) = NULL,
    @id_sesion           INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @observaciones = NULLIF(LTRIM(RTRIM(@observaciones)), '');
        EXEC dbo.usp_Factura_Validar @codigo_cliente, @cod_condicion_venta, @codigo_medio_pago, @codigo_moneda, @tipo_cambio;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        UPDATE dbo.Factura
           SET codigo_cliente = @codigo_cliente, cod_condicion_venta = @cod_condicion_venta,
               codigo_medio_pago = @codigo_medio_pago, codigo_moneda = @codigo_moneda,
               tipo_cambio = @tipo_cambio, observaciones = @observaciones
         WHERE num_factura = @num_factura;
        IF @@ROWCOUNT = 0
            THROW 50311, N'La factura no existe.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Borra el detalle y el encabezado; si la factura tiene notas llega el error 547 (FK) y no se borra nada
CREATE OR ALTER PROCEDURE dbo.usp_Factura_Eliminar
    @num_factura INT,
    @id_sesion   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context N'id_sesion', @id_sesion;
        BEGIN TRANSACTION;
        DELETE FROM dbo.Factura_Detalle WHERE num_factura = @num_factura;
        DELETE FROM dbo.Factura WHERE num_factura = @num_factura;
        IF @@ROWCOUNT = 0
            THROW 50311, N'La factura no existe.', 1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Devuelve dos resultados: 1) encabezado, 2) líneas
CREATE OR ALTER PROCEDURE dbo.usp_Factura_Obtener
    @num_factura INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT f.num_factura, f.fecha, f.codigo_cliente, c.nombre AS cliente, f.cod_condicion_venta,
               f.codigo_medio_pago, f.codigo_moneda, f.tipo_cambio, f.observaciones,
               f.subtotal, f.total_impuestos, f.monto_total
          FROM dbo.Factura f
          JOIN dbo.Cliente c ON c.codigo_cliente = f.codigo_cliente
         WHERE f.num_factura = @num_factura;

        SELECT d.numero_linea, d.codigo_producto, p.descripcion AS producto, d.cantidad,
               d.precio_unitario, d.impuesto, d.monto_linea
          FROM dbo.Factura_Detalle d
          JOIN dbo.Producto_Servicio p ON p.codigo_producto = d.codigo_producto
         WHERE d.num_factura = @num_factura
         ORDER BY d.numero_linea;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

-- @texto: número de factura o parte del nombre del cliente; hasta 500 filas, las más recientes primero
CREATE OR ALTER PROCEDURE dbo.usp_Factura_Listar
    @texto VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @texto = NULLIF(LTRIM(RTRIM(@texto)), '');
        DECLARE @numero INT = TRY_CONVERT(INT, @texto);

        SELECT TOP (500)
               f.num_factura, f.fecha, c.nombre AS cliente, f.codigo_moneda,
               f.subtotal, f.total_impuestos, f.monto_total
          FROM dbo.Factura f
          JOIN dbo.Cliente c ON c.codigo_cliente = f.codigo_cliente
         WHERE @texto IS NULL OR f.num_factura = @numero OR c.nombre LIKE '%' + @texto + '%'
         ORDER BY f.fecha DESC, f.num_factura DESC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_FacturaDetalle_Insertar
    @num_factura     INT,
    @codigo_producto INT,
    @cantidad        DECIMAL(18,3),
    @id_sesion       INT = NULL,
    @numero_linea    SMALLINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @cantidad IS NULL OR @cantidad <= 0
            THROW 50312, N'La cantidad debe ser mayor a 0.', 1;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;

        -- se bloquea la factura para que dos usuarios no tomen el mismo número de línea
        IF NOT EXISTS (SELECT 1 FROM dbo.Factura WITH (UPDLOCK, HOLDLOCK) WHERE num_factura = @num_factura)
            THROW 50311, N'La factura no existe.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Producto_Servicio WHERE codigo_producto = @codigo_producto AND estado = 'A')
            THROW 50310, N'El producto no existe o está inactivo.', 1;

        SELECT @numero_linea = CONVERT(SMALLINT, ISNULL(MAX(numero_linea), 0) + 1)
          FROM dbo.Factura_Detalle WHERE num_factura = @num_factura;

        INSERT INTO dbo.Factura_Detalle (num_factura, numero_linea, codigo_producto, cantidad, precio_unitario, impuesto, monto_linea)
        SELECT @num_factura, @numero_linea, p.codigo_producto, @cantidad, p.precio,
               CAST(ROUND(@cantidad * p.precio * ti.porcentaje / 100.0, 2) AS DECIMAL(18,2)),
               CAST(ROUND(@cantidad * p.precio, 2) AS DECIMAL(18,2))
          FROM dbo.Producto_Servicio p
          JOIN dbo.Tipo_Impuesto ti ON ti.codigo_tipo_impuesto = p.codigo_tipo_impuesto
         WHERE p.codigo_producto = @codigo_producto;

        EXEC dbo.usp_Factura_RecalcularTotales @num_factura;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Cambia la cantidad de una línea; mantiene el precio con que se facturó y recalcula el impuesto
CREATE OR ALTER PROCEDURE dbo.usp_FacturaDetalle_Actualizar
    @num_factura  INT,
    @numero_linea SMALLINT,
    @cantidad     DECIMAL(18,3),
    @id_sesion    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @cantidad IS NULL OR @cantidad <= 0
            THROW 50312, N'La cantidad debe ser mayor a 0.', 1;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        UPDATE d
           SET d.cantidad    = @cantidad,
               d.impuesto    = CAST(ROUND(@cantidad * d.precio_unitario * ti.porcentaje / 100.0, 2) AS DECIMAL(18,2)),
               d.monto_linea = CAST(ROUND(@cantidad * d.precio_unitario, 2) AS DECIMAL(18,2))
          FROM dbo.Factura_Detalle d
          JOIN dbo.Producto_Servicio p ON p.codigo_producto = d.codigo_producto
          JOIN dbo.Tipo_Impuesto ti    ON ti.codigo_tipo_impuesto = p.codigo_tipo_impuesto
         WHERE d.num_factura = @num_factura AND d.numero_linea = @numero_linea;
        IF @@ROWCOUNT = 0
            THROW 50313, N'La línea no existe.', 1;

        EXEC dbo.usp_Factura_RecalcularTotales @num_factura;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Una factura no puede quedar sin líneas: para quitar la última hay que eliminar la factura
CREATE OR ALTER PROCEDURE dbo.usp_FacturaDetalle_Eliminar
    @num_factura  INT,
    @numero_linea SMALLINT,
    @id_sesion    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;
        IF (SELECT COUNT(*) FROM dbo.Factura_Detalle WITH (UPDLOCK, HOLDLOCK) WHERE num_factura = @num_factura) <= 1
            THROW 50314, N'La factura debe conservar al menos una línea.', 1;

        DELETE FROM dbo.Factura_Detalle WHERE num_factura = @num_factura AND numero_linea = @numero_linea;
        IF @@ROWCOUNT = 0
            THROW 50313, N'La línea no existe.', 1;

        EXEC dbo.usp_Factura_RecalcularTotales @num_factura;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
