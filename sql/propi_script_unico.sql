-- base de datos, tablas, seguridad y procedimientos
USE master;
GO
IF DB_ID(N'PropiDB') IS NOT NULL
BEGIN
    ALTER DATABASE PropiDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PropiDB;
END
GO
CREATE DATABASE PropiDB;
GO

ALTER DATABASE PropiDB SET RECOVERY FULL;
GO
USE PropiDB;
GO

CREATE TABLE dbo.Tipo_Identificacion (
    codigo_tipo_identificacion CHAR(2)     NOT NULL CONSTRAINT PK_Tipo_Identificacion PRIMARY KEY,
    descripcion                VARCHAR(50) NOT NULL CONSTRAINT UQ_Tipo_Identificacion_Descripcion UNIQUE,
    estado                     CHAR(1)     NOT NULL CONSTRAINT DF_Tipo_Identificacion_Estado DEFAULT 'A'
                                           CONSTRAINT CK_Tipo_Identificacion_Estado CHECK (estado IN ('A','I'))
);
GO

CREATE TABLE dbo.Provincia (
    codigo_provincia TINYINT     NOT NULL CONSTRAINT PK_Provincia PRIMARY KEY,
    nombre           VARCHAR(30) NOT NULL CONSTRAINT UQ_Provincia_Nombre UNIQUE
);
GO

CREATE TABLE dbo.Canton (
    codigo_canton    SMALLINT    NOT NULL CONSTRAINT PK_Canton PRIMARY KEY,
    codigo_provincia TINYINT     NOT NULL CONSTRAINT FK_Canton_Provincia REFERENCES dbo.Provincia(codigo_provincia),
    nombre           VARCHAR(50) NOT NULL
);
GO

CREATE TABLE dbo.Distrito (
    codigo_distrito INT         NOT NULL CONSTRAINT PK_Distrito PRIMARY KEY,
    codigo_canton   SMALLINT    NOT NULL CONSTRAINT FK_Distrito_Canton REFERENCES dbo.Canton(codigo_canton),
    nombre          VARCHAR(50) NOT NULL
);
GO

CREATE TABLE dbo.Barrio (
    codigo_barrio   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Barrio PRIMARY KEY,
    codigo_distrito INT          NOT NULL CONSTRAINT FK_Barrio_Distrito REFERENCES dbo.Distrito(codigo_distrito),
    nombre          VARCHAR(100) NOT NULL,
    CONSTRAINT UQ_Barrio_Distrito_Nombre UNIQUE (codigo_distrito, nombre)
);
GO

CREATE TABLE dbo.Actividad_Economica (
    codigo_actividad_economica VARCHAR(6)   NOT NULL CONSTRAINT PK_Actividad_Economica PRIMARY KEY,
    descripcion                VARCHAR(200) NOT NULL,
    estado                     CHAR(1)      NOT NULL CONSTRAINT DF_Actividad_Economica_Estado DEFAULT 'A'
                                            CONSTRAINT CK_Actividad_Economica_Estado CHECK (estado IN ('A','I'))
);
GO

CREATE TABLE dbo.Unidad_Medida (
    codigo_unidad_medida VARCHAR(10) NOT NULL CONSTRAINT PK_Unidad_Medida PRIMARY KEY,
    descripcion          VARCHAR(50) NOT NULL
);
GO

CREATE TABLE dbo.Condicion_Venta (
    cod_condicion_venta CHAR(2)     NOT NULL CONSTRAINT PK_Condicion_Venta PRIMARY KEY,
    descripcion         VARCHAR(30) NOT NULL
);
GO

CREATE TABLE dbo.Medio_Pago (
    codigo_medio_pago CHAR(2)     NOT NULL CONSTRAINT PK_Medio_Pago PRIMARY KEY,
    descripcion       VARCHAR(30) NOT NULL
);
GO

CREATE TABLE dbo.Moneda (
    codigo_moneda CHAR(3)     NOT NULL CONSTRAINT PK_Moneda PRIMARY KEY,
    descripcion   VARCHAR(30) NOT NULL
);
GO

CREATE TABLE dbo.Tipo_Impuesto (
    codigo_tipo_impuesto INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Tipo_Impuesto PRIMARY KEY,
    codigo_impuesto      CHAR(2)      NOT NULL,
    descripcion          VARCHAR(100) NOT NULL,
    porcentaje           DECIMAL(5,2) NOT NULL CONSTRAINT CK_Tipo_Impuesto_Porcentaje CHECK (porcentaje BETWEEN 0 AND 100),
    tarifa               CHAR(2)      NOT NULL,
    estado               CHAR(1)      NOT NULL CONSTRAINT DF_Tipo_Impuesto_Estado DEFAULT 'A'
                                      CONSTRAINT CK_Tipo_Impuesto_Estado CHECK (estado IN ('A','I')),
    CONSTRAINT UQ_Tipo_Impuesto_Codigo_Tarifa UNIQUE (codigo_impuesto, tarifa)
);
GO

CREATE TABLE dbo.Cliente (
    codigo_cliente             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cliente PRIMARY KEY,
    nombre                     VARCHAR(150)   NOT NULL,
    codigo_tipo_identificacion CHAR(2)        NOT NULL CONSTRAINT FK_Cliente_Tipo_Identificacion REFERENCES dbo.Tipo_Identificacion(codigo_tipo_identificacion),
    numero_identificacion      VARBINARY(512) NOT NULL,
    hash_identificacion        VARBINARY(32)  NOT NULL CONSTRAINT UQ_Cliente_Identificacion UNIQUE,
    codigo_barrio              INT            NOT NULL CONSTRAINT FK_Cliente_Barrio REFERENCES dbo.Barrio(codigo_barrio),
    direccion                  VARCHAR(250)   NULL,
    profesion                  VARCHAR(100)   NULL,
    codigo_actividad_economica VARCHAR(6)     NOT NULL CONSTRAINT FK_Cliente_Actividad_Economica REFERENCES dbo.Actividad_Economica(codigo_actividad_economica),
    correo                     VARBINARY(512) NOT NULL,
    telefono                   VARBINARY(512) NOT NULL,
    fecha_registro             DATETIME       NOT NULL CONSTRAINT DF_Cliente_Fecha_Registro DEFAULT GETDATE(),
    estado                     CHAR(1)        NOT NULL CONSTRAINT DF_Cliente_Estado DEFAULT 'A'
                                              CONSTRAINT CK_Cliente_Estado CHECK (estado IN ('A','I'))
);
GO

CREATE TABLE dbo.Producto_Servicio (
    codigo_producto      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Producto_Servicio PRIMARY KEY,
    codigo_CABYS         CHAR(13)      NOT NULL CONSTRAINT CK_Producto_Servicio_CABYS CHECK (codigo_CABYS NOT LIKE '%[^0-9]%'),
    descripcion          VARCHAR(200)  NOT NULL,
    codigo_unidad_medida VARCHAR(10)   NOT NULL CONSTRAINT FK_Producto_Servicio_Unidad_Medida REFERENCES dbo.Unidad_Medida(codigo_unidad_medida),
    precio               DECIMAL(18,2) NOT NULL CONSTRAINT CK_Producto_Servicio_Precio CHECK (precio >= 0),
    codigo_tipo_impuesto INT           NOT NULL CONSTRAINT FK_Producto_Servicio_Tipo_Impuesto REFERENCES dbo.Tipo_Impuesto(codigo_tipo_impuesto),
    estado               CHAR(1)       NOT NULL CONSTRAINT DF_Producto_Servicio_Estado DEFAULT 'A'
                                       CONSTRAINT CK_Producto_Servicio_Estado CHECK (estado IN ('A','I'))
);
GO

CREATE TABLE dbo.Factura (
    num_factura         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Factura PRIMARY KEY,
    codigo_cliente      INT           NOT NULL CONSTRAINT FK_Factura_Cliente REFERENCES dbo.Cliente(codigo_cliente),
    fecha               DATETIME      NOT NULL CONSTRAINT DF_Factura_Fecha DEFAULT GETDATE(),
    cod_condicion_venta CHAR(2)       NOT NULL CONSTRAINT FK_Factura_Condicion_Venta REFERENCES dbo.Condicion_Venta(cod_condicion_venta),
    codigo_medio_pago   CHAR(2)       NOT NULL CONSTRAINT FK_Factura_Medio_Pago REFERENCES dbo.Medio_Pago(codigo_medio_pago),
    codigo_moneda       CHAR(3)       NOT NULL CONSTRAINT FK_Factura_Moneda REFERENCES dbo.Moneda(codigo_moneda),
    tipo_cambio         DECIMAL(12,4) NOT NULL CONSTRAINT DF_Factura_Tipo_Cambio DEFAULT 1
                                      CONSTRAINT CK_Factura_Tipo_Cambio CHECK (tipo_cambio > 0),
    observaciones       VARCHAR(500)  NULL,
    subtotal            DECIMAL(18,2) NOT NULL CONSTRAINT DF_Factura_Subtotal DEFAULT 0 CONSTRAINT CK_Factura_Subtotal CHECK (subtotal >= 0),
    total_impuestos     DECIMAL(18,2) NOT NULL CONSTRAINT DF_Factura_Total_Impuestos DEFAULT 0 CONSTRAINT CK_Factura_Total_Impuestos CHECK (total_impuestos >= 0),
    monto_total         DECIMAL(18,2) NOT NULL CONSTRAINT DF_Factura_Monto_Total DEFAULT 0,
    CONSTRAINT CK_Factura_Monto_Total CHECK (monto_total = subtotal + total_impuestos)
);
GO

CREATE TABLE dbo.Factura_Detalle (
    num_factura     INT           NOT NULL CONSTRAINT FK_Factura_Detalle_Factura REFERENCES dbo.Factura(num_factura),
    numero_linea    SMALLINT      NOT NULL,
    codigo_producto INT           NOT NULL CONSTRAINT FK_Factura_Detalle_Producto REFERENCES dbo.Producto_Servicio(codigo_producto),
    cantidad        DECIMAL(18,3) NOT NULL CONSTRAINT CK_Factura_Detalle_Cantidad CHECK (cantidad > 0),
    precio_unitario DECIMAL(18,2) NOT NULL CONSTRAINT CK_Factura_Detalle_Precio CHECK (precio_unitario >= 0),
    impuesto        DECIMAL(18,2) NOT NULL CONSTRAINT DF_Factura_Detalle_Impuesto DEFAULT 0,
    monto_linea     DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_Factura_Detalle PRIMARY KEY (num_factura, numero_linea)
);
GO

CREATE TABLE dbo.Nota_Credito_Debito (
    numero_nota INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Nota_Credito_Debito PRIMARY KEY,
    fecha       DATETIME      NOT NULL CONSTRAINT DF_Nota_Credito_Debito_Fecha DEFAULT GETDATE(),
    num_factura INT           NOT NULL CONSTRAINT FK_Nota_Credito_Debito_Factura REFERENCES dbo.Factura(num_factura),
    tipo        CHAR(1)       NOT NULL CONSTRAINT CK_Nota_Credito_Debito_Tipo CHECK (tipo IN ('C','D')),
    motivo      VARCHAR(500)  NOT NULL,
    monto       DECIMAL(18,2) NOT NULL CONSTRAINT CK_Nota_Credito_Debito_Monto CHECK (monto > 0)
);
GO

CREATE TABLE dbo.Bitacora_Acceso (
    codigo_acceso  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Bitacora_Acceso PRIMARY KEY,
    usuario        VARCHAR(128) NOT NULL,
    terminal       VARCHAR(128) NOT NULL,
    direccion_ip   VARCHAR(45)  NULL,
    fecha_ingreso  DATETIME     NOT NULL,
    fecha_salida   DATETIME     NULL,
    fecha_registro DATETIME     NOT NULL CONSTRAINT DF_Bitacora_Acceso_Fecha_Registro DEFAULT GETDATE()
);
GO

CREATE TABLE dbo.Bitacora_Auditoria (
    fec_registro       DATETIME      NOT NULL CONSTRAINT DF_Bitacora_Auditoria_Fec DEFAULT GETDATE(),
    cod_guid           VARCHAR(255)  NOT NULL CONSTRAINT DF_Bitacora_Auditoria_Guid DEFAULT CONVERT(VARCHAR(255), NEWID()),
    ind_accion         CHAR(1)       NOT NULL CONSTRAINT CK_Bitacora_Auditoria_Accion CHECK (ind_accion IN ('I','D','U')),
    cod_usuario        CHAR(128)     NOT NULL,
    cod_sesion_usuario INT           NULL,
    cod_tabla          VARCHAR(255)  NOT NULL,
    cod_llave          VARCHAR(2000) NULL,
    des_datos          VARCHAR(MAX)  NULL,
    CONSTRAINT PK_Bitacora_Auditoria PRIMARY KEY NONCLUSTERED (cod_guid)
);
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Propi_MasterKey_2026!';
GO
CREATE CERTIFICATE cert_propi_clientes
    WITH SUBJECT = 'Cifrado de datos sensibles de Cliente';
GO
CREATE SYMMETRIC KEY sk_propi_clientes
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE cert_propi_clientes;
GO

CREATE TRIGGER dbo.trg_Cliente_Insert ON dbo.Cliente
AFTER INSERT
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario, cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           'I',
           SUSER_SNAME(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N'id_sesion')), @@SPID),
           'Cliente',
           CONCAT('codigo_cliente=', i.codigo_cliente),
           (SELECT * FROM inserted x WHERE x.codigo_cliente = i.codigo_cliente
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i;
END
GO

CREATE TRIGGER dbo.trg_Cliente_Delete ON dbo.Cliente
AFTER DELETE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario, cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           'D',
           SUSER_SNAME(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N'id_sesion')), @@SPID),
           'Cliente',
           CONCAT('codigo_cliente=', d.codigo_cliente),
           (SELECT * FROM deleted x WHERE x.codigo_cliente = d.codigo_cliente
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM deleted d;
END
GO

CREATE TRIGGER dbo.trg_Cliente_Update ON dbo.Cliente
AFTER UPDATE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario, cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           'U',
           SUSER_SNAME(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N'id_sesion')), @@SPID),
           'Cliente',
           CONCAT('codigo_cliente=', i.codigo_cliente),
           (SELECT JSON_QUERY((SELECT * FROM deleted  x WHERE x.codigo_cliente = d.codigo_cliente
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS antes,
                   JSON_QUERY((SELECT * FROM inserted x WHERE x.codigo_cliente = i.codigo_cliente
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS despues
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    JOIN deleted  d ON d.codigo_cliente = i.codigo_cliente;
END
GO

CREATE TRIGGER dbo.trg_Factura_Insert ON dbo.Factura
AFTER INSERT
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario, cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           'I',
           SUSER_SNAME(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N'id_sesion')), @@SPID),
           'Factura',
           CONCAT('num_factura=', i.num_factura),
           (SELECT * FROM inserted x WHERE x.num_factura = i.num_factura
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i;
END
GO

CREATE TRIGGER dbo.trg_Factura_Delete ON dbo.Factura
AFTER DELETE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario, cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           'D',
           SUSER_SNAME(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N'id_sesion')), @@SPID),
           'Factura',
           CONCAT('num_factura=', d.num_factura),
           (SELECT * FROM deleted x WHERE x.num_factura = d.num_factura
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM deleted d;
END
GO

CREATE TRIGGER dbo.trg_Factura_Update ON dbo.Factura
AFTER UPDATE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario, cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           'U',
           SUSER_SNAME(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N'id_sesion')), @@SPID),
           'Factura',
           CONCAT('num_factura=', i.num_factura),
           (SELECT JSON_QUERY((SELECT * FROM deleted  x WHERE x.num_factura = d.num_factura
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS antes,
                   JSON_QUERY((SELECT * FROM inserted x WHERE x.num_factura = i.num_factura
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS despues
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    JOIN deleted  d ON d.num_factura = i.num_factura;
END
GO

USE master;
GO
IF SUSER_ID(N'usr_admin')     IS NOT NULL DROP LOGIN usr_admin;
IF SUSER_ID(N'usr_digitador') IS NOT NULL DROP LOGIN usr_digitador;
IF SUSER_ID(N'usr_consulta')  IS NOT NULL DROP LOGIN usr_consulta;
GO
CREATE LOGIN usr_admin     WITH PASSWORD = 'Adm!n_Propi2026', DEFAULT_DATABASE = PropiDB, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE LOGIN usr_digitador WITH PASSWORD = 'D!gita_Propi2026', DEFAULT_DATABASE = PropiDB, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE LOGIN usr_consulta  WITH PASSWORD = 'C0nsulta_Propi2026!', DEFAULT_DATABASE = PropiDB, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO

USE PropiDB;

CREATE USER usr_admin     FOR LOGIN usr_admin;
CREATE USER usr_digitador FOR LOGIN usr_digitador;
CREATE USER usr_consulta  FOR LOGIN usr_consulta;
GO
CREATE ROLE rol_administrador;
CREATE ROLE rol_digitador;
CREATE ROLE rol_consulta;
GO
ALTER ROLE rol_administrador ADD MEMBER usr_admin;
ALTER ROLE rol_digitador     ADD MEMBER usr_digitador;
ALTER ROLE rol_consulta      ADD MEMBER usr_consulta;
GO

INSERT INTO dbo.Tipo_Identificacion (codigo_tipo_identificacion, descripcion) VALUES
('01','Cédula física'), ('02','Cédula jurídica'), ('03','DIMEX'), ('04','NITE');

INSERT INTO dbo.Provincia (codigo_provincia, nombre) VALUES
(1,'San José'), (2,'Alajuela'), (3,'Cartago'), (4,'Heredia'),
(5,'Guanacaste'), (6,'Puntarenas'), (7,'Limón');

INSERT INTO dbo.Canton (codigo_canton, codigo_provincia, nombre) VALUES
(101,1,'San José'), (301,3,'Cartago'), (302,3,'Paraíso'), (305,3,'Turrialba');

INSERT INTO dbo.Distrito (codigo_distrito, codigo_canton, nombre) VALUES
(10101,101,'Carmen'), (30101,301,'Oriental'), (30102,301,'Occidental'),
(30201,302,'Paraíso'), (30202,302,'Santiago'), (30203,302,'Orosi'), (30501,305,'Turrialba');

INSERT INTO dbo.Barrio (codigo_distrito, nombre) VALUES
(10101,'Centro'), (30101,'Centro'), (30102,'Centro'),
(30201,'Centro'), (30202,'Centro'), (30203,'Centro'), (30501,'Centro');

INSERT INTO dbo.Actividad_Economica (codigo_actividad_economica, descripcion) VALUES
('6810','Actividades inmobiliarias realizadas con bienes propios o arrendados'),
('6820','Actividades inmobiliarias realizadas a cambio de una retribución o por contrata'),
('4100','Construcción de edificios'),
('6920','Actividades de contabilidad y auditoría'),
('8620','Actividades de médicos y odontólogos');

INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion) VALUES
('Unid','Unidad'), ('Sp','Servicios profesionales'), ('m2','Metro cuadrado'), ('Os','Otro tipo de servicio');

INSERT INTO dbo.Condicion_Venta (cod_condicion_venta, descripcion) VALUES
('01','Contado'), ('02','Crédito');

INSERT INTO dbo.Medio_Pago (codigo_medio_pago, descripcion) VALUES
('01','Efectivo'), ('02','Tarjeta'), ('03','Cheque'),
('04','Transferencia'), ('06','SINPE Móvil'), ('99','Otros');

INSERT INTO dbo.Moneda (codigo_moneda, descripcion) VALUES
('CRC','Colón costarricense'), ('USD','Dólar estadounidense');

INSERT INTO dbo.Tipo_Impuesto (codigo_impuesto, descripcion, porcentaje, tarifa) VALUES
('01','IVA tarifa general', 13.00, '08'),
('01','IVA tarifa reducida 4%', 4.00, '04'),
('01','IVA tarifa reducida 1%', 1.00, '02'),
('01','IVA tarifa 0%', 0.00, '01');

INSERT INTO dbo.Producto_Servicio (codigo_CABYS, descripcion, codigo_unidad_medida, precio, codigo_tipo_impuesto) VALUES
('7211100000000','Venta de lote residencial','Unid', 25000000.00, 4),
('7212100000000','Comisión por intermediación inmobiliaria','Sp', 1500000.00, 1),
('7211200000000','Alquiler de local comercial (mensual)','Os', 450000.00, 1);
GO

EXEC sp_set_session_context N'id_sesion', 1001;

OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

INSERT INTO dbo.Cliente (nombre, codigo_tipo_identificacion, numero_identificacion, hash_identificacion,
                         codigo_barrio, profesion, codigo_actividad_economica, correo, telefono)
VALUES
('María Fernández Solano', '01',
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), '302340567'), HASHBYTES('SHA2_256', '302340567'),
  4, 'Contadora', '6920',
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), 'maria.fernandez@correo.com'),
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), '8888-1234')),
('Inversiones Orosi S.A.', '02',
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), '3101456789'), HASHBYTES('SHA2_256', '3101456789'),
  6, NULL, '6810',
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), 'info@inversionesorosi.cr'),
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), '2533-9876')),
('Cliente de Prueba Borrado', '01',
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), '111110000'), HASHBYTES('SHA2_256', '111110000'),
  1, 'Estudiante', '6820',
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), 'prueba@correo.com'),
  ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), '7000-0000'));

UPDATE dbo.Cliente SET profesion = 'Contadora pública autorizada' WHERE codigo_cliente = 1;

DELETE FROM dbo.Cliente WHERE codigo_cliente = 3;

INSERT INTO dbo.Factura (codigo_cliente, cod_condicion_venta, codigo_medio_pago, codigo_moneda, tipo_cambio, observaciones)
VALUES (2, '01', '04', 'CRC', 1, 'Comisión por venta de lote en Orosi');

INSERT INTO dbo.Factura_Detalle (num_factura, numero_linea, codigo_producto, cantidad, precio_unitario, impuesto, monto_linea)
VALUES (1, 1, 2, 1, 1500000.00, 195000.00, 1500000.00);

UPDATE f
SET f.subtotal        = t.subtotal,
    f.total_impuestos = t.impuestos,
    f.monto_total     = t.subtotal + t.impuestos
FROM dbo.Factura f
JOIN (SELECT num_factura, SUM(monto_linea) AS subtotal, SUM(impuesto) AS impuestos
      FROM dbo.Factura_Detalle GROUP BY num_factura) t
  ON t.num_factura = f.num_factura
WHERE f.num_factura = 1;

 SELECT * FROM dbo.Cliente

SELECT codigo_cliente,
       nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono,
       estado
FROM dbo.Cliente;

CLOSE SYMMETRIC KEY sk_propi_clientes;

SELECT fec_registro, ind_accion, RTRIM(cod_usuario) AS cod_usuario, cod_sesion_usuario,
       cod_tabla, cod_llave, des_datos
FROM dbo.Bitacora_Auditoria
ORDER BY fec_registro;

SELECT r.name AS rol, m.name AS usuario
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE 'rol_%';
GO

GO

USE PropiDB;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Sesion_Informacion
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ORIGINAL_LOGIN() AS nom_usuario,
           CASE WHEN IS_MEMBER(N'rol_administrador') = 1 OR IS_MEMBER(N'db_owner') = 1 THEN N'rol_administrador'
                WHEN IS_MEMBER(N'rol_digitador') = 1 THEN N'rol_digitador'
                WHEN IS_MEMBER(N'rol_consulta')  = 1 THEN N'rol_consulta'
                ELSE N'sin_rol'
           END AS nom_rol;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_BitacoraAcceso_Ingreso
    @terminal      VARCHAR(128),
    @direccion_ip  VARCHAR(45),
    @codigo_acceso INT OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Bitacora_Acceso (usuario, terminal, direccion_ip, fecha_ingreso)
        VALUES (CONVERT(VARCHAR(128), ORIGINAL_LOGIN()), LEFT(@terminal, 128), LEFT(@direccion_ip, 45), GETDATE());

        SET @codigo_acceso = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_BitacoraAcceso_Salida
    @codigo_acceso INT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.Bitacora_Acceso
           SET fecha_salida = GETDATE()
         WHERE codigo_acceso = @codigo_acceso
           AND usuario       = CONVERT(VARCHAR(128), ORIGINAL_LOGIN())
           AND fecha_salida IS NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

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

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Validar
    @nombre                     VARCHAR(150),
    @codigo_tipo_identificacion CHAR(2),
    @numero_identificacion      VARCHAR(50),
    @codigo_barrio              INT,
    @codigo_actividad_economica VARCHAR(6),
    @correo                     VARCHAR(150),
    @telefono                   VARCHAR(20),
    @estado                     CHAR(1)
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(@nombre, '') = ''
        THROW 50010, N'El nombre del cliente es obligatorio.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tipo_Identificacion WHERE codigo_tipo_identificacion = @codigo_tipo_identificacion AND estado = 'A')
        THROW 50011, N'El tipo de identificación no es válido.', 1;

    IF ISNULL(@numero_identificacion, '') = '' OR @numero_identificacion LIKE '%[^0-9]%'
        THROW 50012, N'La identificación debe contener solo dígitos, sin guiones ni espacios.', 1;
    IF (@codigo_tipo_identificacion = '01' AND LEN(@numero_identificacion) <> 9)
       OR (@codigo_tipo_identificacion = '02' AND LEN(@numero_identificacion) <> 10)
       OR (@codigo_tipo_identificacion = '03' AND LEN(@numero_identificacion) NOT IN (11, 12))
       OR (@codigo_tipo_identificacion = '04' AND LEN(@numero_identificacion) <> 10)
        THROW 50013, N'La longitud de la identificación no corresponde al tipo (física 9, jurídica 10, DIMEX 11 o 12, NITE 10).', 1;

    IF @codigo_barrio IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Barrio WHERE codigo_barrio = @codigo_barrio)
        THROW 50014, N'Seleccione un barrio válido (provincia, cantón, distrito y barrio).', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Actividad_Economica WHERE codigo_actividad_economica = @codigo_actividad_economica AND estado = 'A')
        THROW 50015, N'La actividad económica no es válida.', 1;

    IF ISNULL(@correo, '') = '' OR @correo NOT LIKE '_%@_%._%' OR @correo LIKE '% %'
        THROW 50016, N'El correo electrónico no es válido.', 1;

    IF ISNULL(@telefono, '') = '' OR @telefono LIKE '%[^0-9+ -]%' OR LEN(@telefono) < 8
        THROW 50017, N'El teléfono no es válido (mínimo 8 dígitos; se permiten +, espacio y guion).', 1;

    IF @estado IS NULL OR @estado NOT IN ('A', 'I')
        THROW 50019, N'El estado debe ser A (activo) o I (inactivo).', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Insertar
    @nombre                     VARCHAR(150),
    @codigo_tipo_identificacion CHAR(2),
    @numero_identificacion      VARCHAR(50),
    @codigo_barrio              INT,
    @direccion                  VARCHAR(250) = NULL,
    @profesion                  VARCHAR(100) = NULL,
    @codigo_actividad_economica VARCHAR(6),
    @correo                     VARCHAR(150),
    @telefono                   VARCHAR(20),
    @estado                     CHAR(1) = 'A',
    @id_sesion                  INT = NULL,
    @codigo_cliente             INT OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY

        SET @nombre                = LTRIM(RTRIM(@nombre));
        SET @numero_identificacion = LTRIM(RTRIM(@numero_identificacion));
        SET @correo                = LTRIM(RTRIM(@correo));
        SET @telefono              = LTRIM(RTRIM(@telefono));
        SET @direccion             = NULLIF(LTRIM(RTRIM(@direccion)), '');
        SET @profesion             = NULLIF(LTRIM(RTRIM(@profesion)), '');

        EXEC dbo.usp_Cliente_Validar @nombre, @codigo_tipo_identificacion, @numero_identificacion, @codigo_barrio,
                                     @codigo_actividad_economica, @correo, @telefono, @estado;

        DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @numero_identificacion);

        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE hash_identificacion = @hash)
            THROW 50018, N'Ya existe un cliente con ese número de identificación.', 1;

        INSERT INTO dbo.Cliente (nombre, codigo_tipo_identificacion, numero_identificacion, hash_identificacion,
                                 codigo_barrio, direccion, profesion, codigo_actividad_economica, correo, telefono, estado)
        VALUES (@nombre, @codigo_tipo_identificacion,
                ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), @numero_identificacion), @hash,
                @codigo_barrio, @direccion, @profesion, @codigo_actividad_economica,
                ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), @correo),
                ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), @telefono),
                @estado);

        SET @codigo_cliente = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;
        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes') CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Actualizar
    @codigo_cliente             INT,
    @nombre                     VARCHAR(150),
    @codigo_tipo_identificacion CHAR(2),
    @numero_identificacion      VARCHAR(50),
    @codigo_barrio              INT,
    @direccion                  VARCHAR(250) = NULL,
    @profesion                  VARCHAR(100) = NULL,
    @codigo_actividad_economica VARCHAR(6),
    @correo                     VARCHAR(150),
    @telefono                   VARCHAR(20),
    @estado                     CHAR(1),
    @id_sesion                  INT = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @nombre                = LTRIM(RTRIM(@nombre));
        SET @numero_identificacion = LTRIM(RTRIM(@numero_identificacion));
        SET @correo                = LTRIM(RTRIM(@correo));
        SET @telefono              = LTRIM(RTRIM(@telefono));
        SET @direccion             = NULLIF(LTRIM(RTRIM(@direccion)), '');
        SET @profesion             = NULLIF(LTRIM(RTRIM(@profesion)), '');

        EXEC dbo.usp_Cliente_Validar @nombre, @codigo_tipo_identificacion, @numero_identificacion, @codigo_barrio,
                                     @codigo_actividad_economica, @correo, @telefono, @estado;

        DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @numero_identificacion);

        EXEC sp_set_session_context N'id_sesion', @id_sesion;
        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE hash_identificacion = @hash AND codigo_cliente <> @codigo_cliente)
            THROW 50018, N'Ya existe otro cliente con ese número de identificación.', 1;

        UPDATE dbo.Cliente
           SET nombre                     = @nombre,
               codigo_tipo_identificacion = @codigo_tipo_identificacion,
               numero_identificacion      = ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), @numero_identificacion),
               hash_identificacion        = @hash,
               codigo_barrio              = @codigo_barrio,
               direccion                  = @direccion,
               profesion                  = @profesion,
               codigo_actividad_economica = @codigo_actividad_economica,
               correo                     = ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), @correo),
               telefono                   = ENCRYPTBYKEY(KEY_GUID('sk_propi_clientes'), @telefono),
               estado                     = @estado
         WHERE codigo_cliente = @codigo_cliente;

        IF @@ROWCOUNT = 0
            THROW 50020, N'El cliente no existe.', 1;

        COMMIT TRANSACTION;
        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes') CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Eliminar
    @codigo_cliente INT,
    @id_sesion      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;

        DELETE FROM dbo.Cliente WHERE codigo_cliente = @codigo_cliente;

        IF @@ROWCOUNT = 0
            THROW 50020, N'El cliente no existe.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Obtener
    @codigo_cliente INT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        SELECT c.codigo_cliente, c.nombre, c.codigo_tipo_identificacion,
               CONVERT(VARCHAR(50),  DECRYPTBYKEY(c.numero_identificacion)) AS numero_identificacion,
               p.codigo_provincia, ca.codigo_canton, d.codigo_distrito, c.codigo_barrio,
               c.direccion, c.profesion, c.codigo_actividad_economica,
               CONVERT(VARCHAR(150), DECRYPTBYKEY(c.correo))   AS correo,
               CONVERT(VARCHAR(20),  DECRYPTBYKEY(c.telefono)) AS telefono,
               c.fecha_registro, c.estado
          FROM dbo.Cliente  c
          JOIN dbo.Barrio   b  ON b.codigo_barrio     = c.codigo_barrio
          JOIN dbo.Distrito d  ON d.codigo_distrito   = b.codigo_distrito
          JOIN dbo.Canton   ca ON ca.codigo_canton    = d.codigo_canton
          JOIN dbo.Provincia p ON p.codigo_provincia  = ca.codigo_provincia
         WHERE c.codigo_cliente = @codigo_cliente;

        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes') CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cliente_Listar
    @texto  VARCHAR(100) = NULL,
    @estado CHAR(1)      = NULL,
    @max    INT          = 500
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @texto = NULLIF(LTRIM(RTRIM(@texto)), '');
        DECLARE @hash VARBINARY(32) = CASE WHEN @texto IS NULL THEN NULL ELSE HASHBYTES('SHA2_256', @texto) END;

        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        SELECT TOP (@max)
               c.codigo_cliente, c.nombre,
               ti.descripcion AS tipo_identificacion,
               CONVERT(VARCHAR(50),  DECRYPTBYKEY(c.numero_identificacion)) AS numero_identificacion,
               p.nombre AS provincia, ca.nombre AS canton, d.nombre AS distrito, b.nombre AS barrio,
               ae.descripcion AS actividad_economica,
               CONVERT(VARCHAR(150), DECRYPTBYKEY(c.correo))   AS correo,
               CONVERT(VARCHAR(20),  DECRYPTBYKEY(c.telefono)) AS telefono,
               c.estado
          FROM dbo.Cliente c
          JOIN dbo.Tipo_Identificacion  ti ON ti.codigo_tipo_identificacion = c.codigo_tipo_identificacion
          JOIN dbo.Barrio               b  ON b.codigo_barrio               = c.codigo_barrio
          JOIN dbo.Distrito             d  ON d.codigo_distrito             = b.codigo_distrito
          JOIN dbo.Canton               ca ON ca.codigo_canton              = d.codigo_canton
          JOIN dbo.Provincia            p  ON p.codigo_provincia            = ca.codigo_provincia
          JOIN dbo.Actividad_Economica  ae ON ae.codigo_actividad_economica = c.codigo_actividad_economica
         WHERE (@estado IS NULL OR c.estado = @estado)
           AND (@texto IS NULL OR c.nombre LIKE '%' + @texto + '%' OR c.hash_identificacion = @hash)
         ORDER BY c.nombre;

        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes') CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_TipoImpuesto_Validar
    @codigo_impuesto CHAR(2),
    @descripcion     VARCHAR(100),
    @porcentaje      DECIMAL(5,2),
    @tarifa          CHAR(2),
    @estado          CHAR(1)
AS
BEGIN
    SET NOCOUNT ON;
    IF ISNULL(@codigo_impuesto, '') = '' OR @codigo_impuesto LIKE '%[^0-9]%' OR LEN(@codigo_impuesto) <> 2
        THROW 50030, N'El código de impuesto debe tener 2 dígitos (por ejemplo 01).', 1;
    IF ISNULL(@descripcion, '') = ''
        THROW 50031, N'La descripción es obligatoria.', 1;
    IF @porcentaje IS NULL OR @porcentaje < 0 OR @porcentaje > 100
        THROW 50032, N'El porcentaje debe estar entre 0 y 100.', 1;
    IF ISNULL(@tarifa, '') = '' OR @tarifa LIKE '%[^0-9]%' OR LEN(@tarifa) <> 2
        THROW 50033, N'El código de tarifa debe tener 2 dígitos (por ejemplo 08).', 1;
    IF @estado IS NULL OR @estado NOT IN ('A', 'I')
        THROW 50034, N'El estado debe ser A (activo) o I (inactivo).', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_TipoImpuesto_Insertar
    @codigo_impuesto      CHAR(2),
    @descripcion          VARCHAR(100),
    @porcentaje           DECIMAL(5,2),
    @tarifa               CHAR(2),
    @estado               CHAR(1) = 'A',
    @id_sesion            INT = NULL,
    @codigo_tipo_impuesto INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @descripcion = LTRIM(RTRIM(@descripcion));

        EXEC dbo.usp_TipoImpuesto_Validar @codigo_impuesto, @descripcion, @porcentaje, @tarifa, @estado;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Tipo_Impuesto WHERE codigo_impuesto = @codigo_impuesto AND tarifa = @tarifa)
            THROW 50035, N'Ya existe un impuesto con ese código y tarifa.', 1;

        INSERT INTO dbo.Tipo_Impuesto (codigo_impuesto, descripcion, porcentaje, tarifa, estado)
        VALUES (@codigo_impuesto, @descripcion, @porcentaje, @tarifa, @estado);

        SET @codigo_tipo_impuesto = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_TipoImpuesto_Actualizar
    @codigo_tipo_impuesto INT,
    @codigo_impuesto      CHAR(2),
    @descripcion          VARCHAR(100),
    @porcentaje           DECIMAL(5,2),
    @tarifa               CHAR(2),
    @estado               CHAR(1),
    @id_sesion            INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @descripcion = LTRIM(RTRIM(@descripcion));

        EXEC dbo.usp_TipoImpuesto_Validar @codigo_impuesto, @descripcion, @porcentaje, @tarifa, @estado;
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM dbo.Tipo_Impuesto
                    WHERE codigo_impuesto = @codigo_impuesto AND tarifa = @tarifa
                      AND codigo_tipo_impuesto <> @codigo_tipo_impuesto)
            THROW 50035, N'Ya existe otro impuesto con ese código y tarifa.', 1;

        UPDATE dbo.Tipo_Impuesto
           SET codigo_impuesto = @codigo_impuesto,
               descripcion     = @descripcion,
               porcentaje      = @porcentaje,
               tarifa          = @tarifa,
               estado          = @estado
         WHERE codigo_tipo_impuesto = @codigo_tipo_impuesto;

        IF @@ROWCOUNT = 0
            THROW 50036, N'El tipo de impuesto no existe.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_TipoImpuesto_Eliminar
    @codigo_tipo_impuesto INT,
    @id_sesion            INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        BEGIN TRANSACTION;

        DELETE FROM dbo.Tipo_Impuesto WHERE codigo_tipo_impuesto = @codigo_tipo_impuesto;

        IF @@ROWCOUNT = 0
            THROW 50036, N'El tipo de impuesto no existe.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_TipoImpuesto_Obtener
    @codigo_tipo_impuesto INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT codigo_tipo_impuesto, codigo_impuesto, descripcion, porcentaje, tarifa, estado
          FROM dbo.Tipo_Impuesto
         WHERE codigo_tipo_impuesto = @codigo_tipo_impuesto;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_TipoImpuesto_Listar
    @texto  VARCHAR(100) = NULL,
    @estado CHAR(1)      = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @texto = NULLIF(LTRIM(RTRIM(@texto)), '');

        SELECT codigo_tipo_impuesto, codigo_impuesto, descripcion, porcentaje, tarifa, estado
          FROM dbo.Tipo_Impuesto
         WHERE (@estado IS NULL OR estado = @estado)
           AND (@texto IS NULL OR descripcion LIKE '%' + @texto + '%'
                               OR codigo_impuesto = @texto OR tarifa = @texto)
         ORDER BY codigo_impuesto, tarifa;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO

GRANT EXECUTE ON dbo.usp_Sesion_Informacion     TO rol_administrador, rol_digitador, rol_consulta;
GRANT EXECUTE ON dbo.usp_BitacoraAcceso_Ingreso TO rol_administrador, rol_digitador, rol_consulta;
GRANT EXECUTE ON dbo.usp_BitacoraAcceso_Salida  TO rol_administrador, rol_digitador, rol_consulta;

GRANT EXECUTE ON dbo.usp_Catalogo_Listar        TO rol_administrador, rol_digitador;

GRANT EXECUTE ON dbo.usp_Cliente_Insertar       TO rol_administrador, rol_digitador;
GRANT EXECUTE ON dbo.usp_Cliente_Actualizar     TO rol_administrador, rol_digitador;
GRANT EXECUTE ON dbo.usp_Cliente_Obtener        TO rol_administrador, rol_digitador;
GRANT EXECUTE ON dbo.usp_Cliente_Listar         TO rol_administrador, rol_digitador;
GRANT EXECUTE ON dbo.usp_Cliente_Eliminar       TO rol_administrador;

GRANT EXECUTE ON dbo.usp_TipoImpuesto_Insertar   TO rol_administrador;
GRANT EXECUTE ON dbo.usp_TipoImpuesto_Actualizar TO rol_administrador;
GRANT EXECUTE ON dbo.usp_TipoImpuesto_Eliminar   TO rol_administrador;
GRANT EXECUTE ON dbo.usp_TipoImpuesto_Obtener    TO rol_administrador, rol_digitador;
GRANT EXECUTE ON dbo.usp_TipoImpuesto_Listar     TO rol_administrador, rol_digitador;

GRANT VIEW DEFINITION ON SYMMETRIC KEY::sk_propi_clientes TO rol_administrador, rol_digitador;
GRANT CONTROL ON CERTIFICATE::cert_propi_clientes         TO rol_administrador, rol_digitador;
GO

-- triggers de auditoria
USE PropiDB;
GO
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#pk') IS NOT NULL DROP TABLE #pk;

SELECT t.name AS tabla, c.name AS columna, ic.key_ordinal AS orden
INTO #pk
FROM sys.tables t
JOIN sys.indexes i        ON i.object_id = t.object_id AND i.is_primary_key = 1
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE SCHEMA_NAME(t.schema_id) = N'dbo';

SELECT t.name AS tabla_sin_pk_no_se_crea_trigger
FROM sys.tables t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
  AND t.name <> N'Bitacora_Auditoria'
  AND NOT EXISTS (SELECT 1 FROM #pk p WHERE p.tabla = t.name);

DECLARE @tpl_i NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER dbo.{TRG} ON dbo.{TQ}
AFTER INSERT
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario,
         cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           ''I'',
           ORIGINAL_LOGIN(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N''id_sesion'')), @@SPID),
           ''{T}'',
           {KEY_I},
           (SELECT * FROM inserted x WHERE {ON_X_I}
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i;
END';

DECLARE @tpl_d NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER dbo.{TRG} ON dbo.{TQ}
AFTER DELETE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario,
         cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           ''D'',
           ORIGINAL_LOGIN(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N''id_sesion'')), @@SPID),
           ''{T}'',
           {KEY_D},
           (SELECT * FROM deleted x WHERE {ON_X_D}
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM deleted d;
END';

DECLARE @tpl_u NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER dbo.{TRG} ON dbo.{TQ}
AFTER UPDATE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario,
         cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           ''U'',
           ORIGINAL_LOGIN(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N''id_sesion'')), @@SPID),
           ''{T}'',
           {KEY_I},
           (SELECT JSON_QUERY((SELECT * FROM deleted y WHERE {ON_Y_I}
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS antes,
                   JSON_QUERY((SELECT * FROM inserted x WHERE {ON_X_I}
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS despues
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    JOIN deleted d ON {ON_D_I};
END';

DECLARE @tabla SYSNAME,
        @sql   NVARCHAR(MAX),
        @key_i NVARCHAR(MAX), @key_d  NVARCHAR(MAX),
        @on_x_i NVARCHAR(MAX), @on_y_i NVARCHAR(MAX),
        @on_x_d NVARCHAR(MAX), @on_d_i NVARCHAR(MAX);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT tabla
    FROM #pk
    WHERE tabla <> N'Bitacora_Auditoria'
    ORDER BY tabla;

OPEN cur;
FETCH NEXT FROM cur INTO @tabla;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT

        @key_i = N'CONCAT(' + (STRING_AGG(CONVERT(NVARCHAR(MAX),
                    N'''' + CASE WHEN orden > 1 THEN N', ' ELSE N'' END + columna
                    + N'='', i.' + QUOTENAME(columna)), N', ')
                    WITHIN GROUP (ORDER BY orden)) + N')',
        @key_d = N'CONCAT(' + (STRING_AGG(CONVERT(NVARCHAR(MAX),
                    N'''' + CASE WHEN orden > 1 THEN N', ' ELSE N'' END + columna
                    + N'='', d.' + QUOTENAME(columna)), N', ')
                    WITHIN GROUP (ORDER BY orden)) + N')',

        @on_x_i = STRING_AGG(CONVERT(NVARCHAR(MAX), N'x.' + QUOTENAME(columna) + N' = i.' + QUOTENAME(columna)), N' AND '),
        @on_y_i = STRING_AGG(CONVERT(NVARCHAR(MAX), N'y.' + QUOTENAME(columna) + N' = i.' + QUOTENAME(columna)), N' AND '),
        @on_x_d = STRING_AGG(CONVERT(NVARCHAR(MAX), N'x.' + QUOTENAME(columna) + N' = d.' + QUOTENAME(columna)), N' AND '),
        @on_d_i = STRING_AGG(CONVERT(NVARCHAR(MAX), N'd.' + QUOTENAME(columna) + N' = i.' + QUOTENAME(columna)), N' AND ')
    FROM #pk
    WHERE tabla = @tabla;

    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tpl_i,
                N'{TRG}',  QUOTENAME(N'trg_' + @tabla + N'_Insert')),
                N'{TQ}',   QUOTENAME(@tabla)),
                N'{T}',    @tabla),
                N'{KEY_I}', @key_i),
                N'{ON_X_I}', @on_x_i);
    EXEC sys.sp_executesql @sql;

    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tpl_d,
                N'{TRG}',  QUOTENAME(N'trg_' + @tabla + N'_Delete')),
                N'{TQ}',   QUOTENAME(@tabla)),
                N'{T}',    @tabla),
                N'{KEY_D}', @key_d),
                N'{ON_X_D}', @on_x_d);
    EXEC sys.sp_executesql @sql;

    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tpl_u,
                N'{TRG}',  QUOTENAME(N'trg_' + @tabla + N'_Update')),
                N'{TQ}',   QUOTENAME(@tabla)),
                N'{T}',    @tabla),
                N'{KEY_I}', @key_i),
                N'{ON_X_I}', @on_x_i),
                N'{ON_Y_I}', @on_y_i);
    SET @sql = REPLACE(@sql, N'{ON_D_I}', @on_d_i);
    EXEC sys.sp_executesql @sql;

    PRINT N'Triggers creados para: ' + @tabla;
    FETCH NEXT FROM cur INTO @tabla;
END

CLOSE cur;
DEALLOCATE cur;
DROP TABLE #pk;
GO

SELECT OBJECT_NAME(parent_id) AS tabla,
       COUNT(*)               AS cantidad_triggers,
       STRING_AGG(name, N', ') AS triggers
FROM sys.triggers
WHERE parent_class = 1
GROUP BY parent_id
ORDER BY tabla;

SELECT t.name AS tabla_incompleta
FROM sys.tables t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
  AND t.name <> N'Bitacora_Auditoria'
  AND (SELECT COUNT(*) FROM sys.triggers tr WHERE tr.parent_id = t.object_id) <> 3;
GO

EXEC sp_set_session_context N'id_sesion', 1001;

INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion)
VALUES ('TRG', 'Prueba de trigger');

UPDATE dbo.Unidad_Medida
SET descripcion = 'Prueba de trigger modificada'
WHERE codigo_unidad_medida = 'TRG';

DELETE FROM dbo.Unidad_Medida
WHERE codigo_unidad_medida = 'TRG';

SELECT TOP (3) fec_registro, ind_accion, RTRIM(cod_usuario) AS cod_usuario,
       cod_sesion_usuario, cod_tabla, cod_llave, des_datos
FROM dbo.Bitacora_Auditoria
WHERE cod_tabla = 'Unidad_Medida'
ORDER BY fec_registro DESC;
GO

-- datos de prueba
USE PropiDB;
GO
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM dbo.Cliente WHERE direccion LIKE N'Dataset:%')
    THROW 50100, N'El dataset ya fue cargado. No se vuelve a cargar para no duplicar datos.', 1;

BEGIN TRY

    DISABLE TRIGGER ALL ON dbo.Barrio;
    DISABLE TRIGGER ALL ON dbo.Cliente;
    DISABLE TRIGGER ALL ON dbo.Producto_Servicio;
    DISABLE TRIGGER ALL ON dbo.Factura;
    DISABLE TRIGGER ALL ON dbo.Factura_Detalle;
    DISABLE TRIGGER ALL ON dbo.Nota_Credito_Debito;
    DISABLE TRIGGER ALL ON dbo.Bitacora_Acceso;

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

    OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

    BEGIN TRANSACTION;

    CREATE TABLE #dist (rn INT PRIMARY KEY, id INT);
    INSERT INTO #dist
    SELECT ROW_NUMBER() OVER (ORDER BY codigo_distrito), codigo_distrito FROM dbo.Distrito;
    DECLARE @cd INT = (SELECT COUNT(*) FROM #dist);

    INSERT INTO dbo.Barrio (codigo_distrito, nombre)
    SELECT d.id, CONCAT(N'Barrio ', n.n)
    FROM #n n
    JOIN #dist d ON d.rn = n.n % @cd + 1
    WHERE n.n <= 1000;

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
                        WHEN '01' THEN 100000000   + n.n * 7919
                        WHEN '02' THEN 3101000000  + n.n * 7919
                        WHEN '03' THEN 15500000000 + n.n * 7919
                        ELSE           4000000000  + n.n * 7919
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

    ENABLE TRIGGER ALL ON dbo.Barrio;
    ENABLE TRIGGER ALL ON dbo.Cliente;
    ENABLE TRIGGER ALL ON dbo.Producto_Servicio;
    ENABLE TRIGGER ALL ON dbo.Factura;
    ENABLE TRIGGER ALL ON dbo.Factura_Detalle;
    ENABLE TRIGGER ALL ON dbo.Nota_Credito_Debito;
    ENABLE TRIGGER ALL ON dbo.Bitacora_Acceso;

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

SELECT t.name AS tabla, SUM(p.row_count) AS filas
FROM sys.tables t
JOIN sys.dm_db_partition_stats p
  ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY filas DESC, t.name;

SELECT f.num_factura
FROM dbo.Factura f
JOIN (SELECT num_factura, SUM(monto_linea) AS s, SUM(impuesto) AS i
      FROM dbo.Factura_Detalle GROUP BY num_factura) d ON d.num_factura = f.num_factura
WHERE f.subtotal <> d.s OR f.total_impuestos <> d.i OR f.monto_total <> d.s + d.i;

OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;
SELECT TOP (5) codigo_cliente, nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono
FROM dbo.Cliente
ORDER BY codigo_cliente DESC;
CLOSE SYMMETRIC KEY sk_propi_clientes;
GO

-- reportes
USE PropiDB;
GO

IF (SELECT snapshot_isolation_state FROM sys.databases WHERE name = N'PropiDB') = 0
    ALTER DATABASE PropiDB SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Clientes
    @fecha_desde DATE,
    @fecha_hasta DATE,
    @estado      CHAR(1) = 'T'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

    BEGIN TRY
        IF @fecha_desde IS NULL OR @fecha_hasta IS NULL
            THROW 50050, N'Las fechas desde y hasta son obligatorias.', 1;
        IF @fecha_desde > @fecha_hasta
            THROW 50051, N'La fecha desde no puede ser mayor que la fecha hasta.', 1;

        SET @estado = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@estado)), ''), 'T'));
        IF @estado NOT IN ('A', 'I', 'T')
            THROW 50052, N'El estado debe ser A (activo), I (inactivo) o T (todos).', 1;

        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        BEGIN TRANSACTION;

        SELECT c.nombre,
               CONVERT(VARCHAR(50),  DECRYPTBYKEY(c.numero_identificacion)) AS numero_identificacion,
               ae.descripcion                                               AS actividad_economica,
               CONVERT(VARCHAR(150), DECRYPTBYKEY(c.correo))                AS correo,
               CONVERT(VARCHAR(20),  DECRYPTBYKEY(c.telefono))              AS telefono
        FROM dbo.Cliente c
        JOIN dbo.Actividad_Economica ae
          ON ae.codigo_actividad_economica = c.codigo_actividad_economica
        WHERE c.fecha_registro >= @fecha_desde
          AND c.fecha_registro <  DATEADD(DAY, 1, @fecha_hasta)
          AND (@estado = 'T' OR c.estado = @estado)
        ORDER BY c.nombre
        OPTION (RECOMPILE);

        COMMIT TRANSACTION;
        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes')
            CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Facturas
    @fecha_desde DATE,
    @fecha_hasta DATE
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

    BEGIN TRY
        IF @fecha_desde IS NULL OR @fecha_hasta IS NULL
            THROW 50053, N'Las fechas desde y hasta son obligatorias.', 1;
        IF @fecha_desde > @fecha_hasta
            THROW 50054, N'La fecha desde no puede ser mayor que la fecha hasta.', 1;

        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        BEGIN TRANSACTION;

        SELECT c.nombre                                                     AS nombre_cliente,
               CONVERT(VARCHAR(50), DECRYPTBYKEY(c.numero_identificacion))  AS numero_identificacion,
               ae.descripcion                                               AS actividad_economica,
               f.num_factura,
               f.fecha,
               f.subtotal,
               f.total_impuestos,
               f.monto_total                                                AS total_factura
        FROM dbo.Factura f
        JOIN dbo.Cliente c
          ON c.codigo_cliente = f.codigo_cliente
        JOIN dbo.Actividad_Economica ae
          ON ae.codigo_actividad_economica = c.codigo_actividad_economica
        WHERE f.fecha >= @fecha_desde
          AND f.fecha <  DATEADD(DAY, 1, @fecha_hasta)
        ORDER BY f.fecha, f.num_factura;

        COMMIT TRANSACTION;
        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes')
            CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Auditoria
    @fecha_desde DATE,
    @fecha_hasta DATE,
    @usuario     VARCHAR(128) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

    BEGIN TRY
        IF @fecha_desde IS NULL OR @fecha_hasta IS NULL
            THROW 50055, N'Las fechas desde y hasta son obligatorias.', 1;
        IF @fecha_desde > @fecha_hasta
            THROW 50056, N'La fecha desde no puede ser mayor que la fecha hasta.', 1;

        SET @usuario = NULLIF(LTRIM(RTRIM(@usuario)), '');

        BEGIN TRANSACTION;

        SELECT b.fec_registro                                       AS fecha_registro,
               CASE b.ind_accion WHEN 'I' THEN N'Inserción'
                                 WHEN 'D' THEN N'Borrado'
                                 WHEN 'U' THEN N'Modificación' END  AS accion,
               RTRIM(b.cod_usuario)                                 AS nombre_usuario,
               b.cod_tabla                                          AS tabla_afectada,
               b.cod_llave                                          AS llave_registro,
               CASE WHEN b.ind_accion <> 'U' THEN b.des_datos END   AS datos_afectados,
               CASE WHEN b.ind_accion = 'U' AND ISJSON(b.des_datos) = 1
                    THEN JSON_QUERY(b.des_datos, '$.antes') END     AS datos_antes,
               CASE WHEN b.ind_accion = 'U' AND ISJSON(b.des_datos) = 1
                    THEN JSON_QUERY(b.des_datos, '$.despues') END   AS datos_despues
        FROM dbo.Bitacora_Auditoria b
        WHERE b.fec_registro >= @fecha_desde
          AND b.fec_registro <  DATEADD(DAY, 1, @fecha_hasta)
          AND (@usuario IS NULL OR b.cod_usuario = @usuario)
        ORDER BY b.fec_registro
        OPTION (RECOMPILE);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Seguridad
    @usuario SYSNAME = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

    BEGIN TRY
        SET @usuario = NULLIF(LTRIM(RTRIM(@usuario)), '');

        IF @usuario IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @usuario AND type IN ('S', 'U'))
            THROW 50057, N'El usuario indicado no existe en la base de datos.', 1;

        BEGIN TRANSACTION;

        SELECT u.name AS nombre_usuario,
               r.name AS rol,
               o.name AS nombre_objeto,
               CASE o.type WHEN 'U'  THEN N'Tabla'
                           WHEN 'V'  THEN N'Vista'
                           WHEN 'P'  THEN N'Procedimiento'
                           WHEN 'FN' THEN N'Función'
                           ELSE o.type_desc END AS tipo_objeto,
               CASE dp.permission_name WHEN 'SELECT'  THEN N'Selección'
                                       WHEN 'INSERT'  THEN N'Inserción'
                                       WHEN 'DELETE'  THEN N'Borrado'
                                       WHEN 'UPDATE'  THEN N'Modificación'
                                       WHEN 'EXECUTE' THEN N'Execute'
                                       ELSE dp.permission_name END AS tipo_permiso,
               dp.state_desc AS estado
        FROM sys.database_principals u
        JOIN sys.database_role_members rm
          ON rm.member_principal_id = u.principal_id
        JOIN sys.database_principals r
          ON r.principal_id = rm.role_principal_id
        JOIN sys.database_permissions dp
          ON dp.grantee_principal_id = r.principal_id
         AND dp.class IN (1, 3)
        JOIN sys.objects o
          ON (dp.class = 1 AND o.object_id = dp.major_id AND dp.minor_id = 0)
          OR (dp.class = 3 AND o.schema_id = dp.major_id)
        WHERE u.type IN ('S', 'U')
          AND r.type = 'R'
          AND o.is_ms_shipped = 0
          AND dp.permission_name IN ('SELECT', 'INSERT', 'DELETE', 'UPDATE', 'EXECUTE')
          AND (   (dp.permission_name IN ('SELECT', 'INSERT', 'DELETE', 'UPDATE') AND o.type IN ('U', 'V'))
               OR (dp.permission_name = 'EXECUTE' AND o.type IN ('P', 'FN')))
          AND (@usuario IS NULL OR u.name = @usuario)
        ORDER BY u.name, r.name, o.name, dp.permission_name
        OPTION (RECOMPILE);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

SELECT name, snapshot_isolation_state_desc FROM sys.databases WHERE name = N'PropiDB';

EXEC dbo.usp_Reporte_Clientes   @fecha_desde = '2024-01-01', @fecha_hasta = '2026-12-31', @estado = 'T';
EXEC dbo.usp_Reporte_Clientes   @fecha_desde = '2024-01-01', @fecha_hasta = '2026-12-31', @estado = 'I';
EXEC dbo.usp_Reporte_Facturas   @fecha_desde = '2025-01-01', @fecha_hasta = '2026-12-31';
EXEC dbo.usp_Reporte_Auditoria  @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31', @usuario = NULL;
EXEC dbo.usp_Reporte_Seguridad  @usuario = NULL;
EXEC dbo.usp_Reporte_Seguridad  @usuario = 'usr_digitador';

BEGIN TRY
    EXEC dbo.usp_Reporte_Clientes @fecha_desde = '2026-12-31', @fecha_hasta = '2026-01-01', @estado = 'T';
    PRINT N'FALLO: no detectó fechas invertidas';
END TRY
BEGIN CATCH
    PRINT N'OK validación de fechas -> ' + ERROR_MESSAGE();
END CATCH

BEGIN TRY
    EXEC dbo.usp_Reporte_Clientes @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31', @estado = 'X';
    PRINT N'FALLO: no detectó el estado inválido';
END TRY
BEGIN CATCH
    PRINT N'OK validación de estado -> ' + ERROR_MESSAGE();
END CATCH

EXECUTE AS USER = N'usr_consulta';
BEGIN TRY
    EXEC dbo.usp_Reporte_Clientes @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31', @estado = 'T';
    PRINT N'OK consulta ejecuta el reporte de clientes';
END TRY
BEGIN CATCH
    PRINT N'FALLO consulta/clientes: ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_consulta';
BEGIN TRY
    EXEC dbo.usp_Reporte_Auditoria @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31';
    PRINT N'FALLO: consulta pudo ver la auditoría';
END TRY
BEGIN CATCH
    PRINT N'OK consulta sin acceso a la auditoría -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    EXEC dbo.usp_Reporte_Seguridad;
    PRINT N'FALLO: el digitador pudo ver la seguridad';
END TRY
BEGIN CATCH
    PRINT N'OK digitador sin acceso al reporte de seguridad -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_admin';
BEGIN TRY
    EXEC dbo.usp_Reporte_Seguridad @usuario = 'usr_consulta';
    PRINT N'OK administrador ejecuta el reporte de seguridad';
END TRY
BEGIN CATCH
    PRINT N'FALLO admin/seguridad: ' + ERROR_MESSAGE();
END CATCH
REVERT;
GO

-- procedimientos de producto, nota, factura y detalle
USE PropiDB;
GO

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
        THROW;
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

CREATE OR ALTER PROCEDURE dbo.usp_Nota_Validar
    @numero_nota INT,
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

-- permisos por rol
USE PropiDB;
GO
SET NOCOUNT ON;

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'REVOKE EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name)
             + N' FROM rol_administrador, rol_digitador, rol_consulta;' + CHAR(10)
FROM sys.procedures;

SELECT @sql += N'REVOKE SELECT, INSERT, UPDATE, DELETE ON ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name)
             + N' FROM rol_administrador, rol_digitador, rol_consulta;' + CHAR(10)
FROM sys.tables;

EXEC sys.sp_executesql @sql;

REVOKE SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo
    FROM rol_administrador, rol_digitador, rol_consulta;
GO

GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO rol_administrador;
GRANT VIEW DEFINITION ON SYMMETRIC KEY::sk_propi_clientes  TO rol_administrador;
GRANT CONTROL         ON CERTIFICATE::cert_propi_clientes  TO rol_administrador;
GRANT VIEW DEFINITION TO rol_administrador;
GO

DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rol_digitador, rol_consulta;
GO

DENY INSERT, UPDATE, DELETE ON dbo.Bitacora_Auditoria TO rol_administrador, rol_digitador, rol_consulta;
DENY INSERT, UPDATE, DELETE ON dbo.Bitacora_Acceso    TO rol_administrador, rol_digitador, rol_consulta;
GO

DECLARE @mapa_grant TABLE (rol SYSNAME, incluir NVARCHAR(100), excluir NVARCHAR(100) NULL);

INSERT INTO @mapa_grant (rol, incluir, excluir) VALUES

  (N'rol_digitador', N'usp[_]Sesion[_]%',          NULL),
  (N'rol_digitador', N'usp[_]BitacoraAcceso[_]%',  NULL),
  (N'rol_consulta',  N'usp[_]Sesion[_]%',          NULL),
  (N'rol_consulta',  N'usp[_]BitacoraAcceso[_]%',  NULL),

  (N'rol_digitador', N'usp[_]Catalogo[_]%',        NULL),
  (N'rol_digitador', N'usp[_]Cliente[_]%',         N'%[_]Eliminar'),
  (N'rol_digitador', N'usp[_]Factura%',            N'%[_]Eliminar'),
  (N'rol_digitador', N'usp[_]Nota%',               N'%[_]Eliminar'),

  (N'rol_digitador', N'usp[_]Producto[_]Listar',     NULL),
  (N'rol_digitador', N'usp[_]Producto[_]Obtener',    NULL),
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Listar',  NULL),
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Obtener', NULL),

  (N'rol_consulta',  N'usp[_]Reporte[_]Clientes',  NULL),
  (N'rol_consulta',  N'usp[_]Reporte[_]Facturas',  NULL);

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'GRANT EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(p.schema_id)) + N'.' + QUOTENAME(p.name)
             + N' TO ' + QUOTENAME(m.rol) + N';' + CHAR(10)
FROM sys.procedures p
JOIN @mapa_grant m
  ON p.name LIKE m.incluir
 AND (m.excluir IS NULL OR p.name NOT LIKE m.excluir);

EXEC sys.sp_executesql @sql;

SET @sql = N'';
SELECT @sql += N'REVOKE EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name)
             + N' FROM rol_digitador, rol_consulta;' + CHAR(10)
FROM sys.procedures
WHERE name LIKE N'%[_]Validar';
EXEC sys.sp_executesql @sql;
GO

DECLARE @mapa_deny TABLE (rol SYSNAME, patron NVARCHAR(100));

INSERT INTO @mapa_deny (rol, patron) VALUES

  (N'rol_digitador', N'%[_]Eliminar'),
  (N'rol_consulta',  N'%[_]Eliminar'),

  (N'rol_consulta',  N'%[_]Insertar'),
  (N'rol_consulta',  N'%[_]Actualizar'),

  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Insertar'),
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Actualizar'),
  (N'rol_digitador', N'usp[_]Producto[_]Insertar'),
  (N'rol_digitador', N'usp[_]Producto[_]Actualizar'),

  (N'rol_digitador', N'usp[_]Reporte[_]Auditoria'),
  (N'rol_digitador', N'usp[_]Reporte[_]Seguridad'),
  (N'rol_consulta',  N'usp[_]Reporte[_]Auditoria'),
  (N'rol_consulta',  N'usp[_]Reporte[_]Seguridad');

DECLARE @sql2 NVARCHAR(MAX) = N'';
SELECT @sql2 += N'DENY EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(p.schema_id)) + N'.' + QUOTENAME(p.name)
              + N' TO ' + QUOTENAME(d.rol) + N';' + CHAR(10)
FROM sys.procedures p
JOIN @mapa_deny d ON p.name LIKE d.patron;

EXEC sys.sp_executesql @sql2;
GO

IF EXISTS (SELECT 1
           FROM sys.procedures p
           JOIN sys.sql_modules m ON m.object_id = p.object_id
           WHERE m.definition LIKE N'%OPEN SYMMETRIC KEY%'
             AND m.execute_as_principal_id IS NULL)
BEGIN
    PRINT N'ADVERTENCIA: estos procedimientos abren la llave pero no usan WITH EXECUTE AS OWNER.';
    PRINT N'Agregue esa línea entre la lista de parámetros y el AS, y vuelva a correr este script:';
    SELECT p.name AS procedimiento_sin_execute_as_owner
    FROM sys.procedures p
    JOIN sys.sql_modules m ON m.object_id = p.object_id
    WHERE m.definition LIKE N'%OPEN SYMMETRIC KEY%'
      AND m.execute_as_principal_id IS NULL;
END
ELSE
BEGIN
    REVOKE VIEW DEFINITION ON SYMMETRIC KEY::sk_propi_clientes FROM rol_digitador, rol_consulta;
    REVOKE CONTROL         ON CERTIFICATE::cert_propi_clientes FROM rol_digitador, rol_consulta;
    PRINT N'Permisos sobre la llave y el certificado quitados a digitador y consulta.';
END
GO

EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    SELECT TOP (1) * FROM dbo.Cliente;
    PRINT N'FALLO 1: el digitador pudo leer la tabla Cliente';
END TRY
BEGIN CATCH
    PRINT N'OK 1: digitador sin SELECT directo -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'tipo_identificacion';
    PRINT N'OK 2: digitador ejecuta usp_Catalogo_Listar';
END TRY
BEGIN CATCH
    PRINT N'FALLO 2: ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    EXEC dbo.usp_Cliente_Eliminar @codigo_cliente = 0;
    PRINT N'FALLO 3: el digitador pudo ejecutar usp_Cliente_Eliminar';
END TRY
BEGIN CATCH
    PRINT N'OK 3: digitador sin EXECUTE en Eliminar -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_consulta';
BEGIN TRY
    INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion) VALUES ('X', 'X');
    PRINT N'FALLO 4: consulta pudo insertar';
END TRY
BEGIN CATCH
    PRINT N'OK 4: consulta sin INSERT -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_admin';
BEGIN TRY
    INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion) VALUES ('PRM', 'Prueba permisos');
    DELETE FROM dbo.Unidad_Medida WHERE codigo_unidad_medida = 'PRM';
    PRINT N'OK 5: administrador escribe y el trigger registró en la bitácora';
END TRY
BEGIN CATCH
    PRINT N'FALLO 5: ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_admin';
BEGIN TRY
    DELETE FROM dbo.Bitacora_Auditoria;
    PRINT N'FALLO 6: el administrador pudo borrar la bitácora';
END TRY
BEGIN CATCH
    PRINT N'OK 6: bitácora protegida incluso para el administrador -> ' + ERROR_MESSAGE();
END CATCH
REVERT;
GO

SELECT r.name AS rol,
       dp.class_desc AS tipo_objeto,
       CASE dp.class
            WHEN 0  THEN DB_NAME()
            WHEN 1  THEN OBJECT_NAME(dp.major_id)
            WHEN 3  THEN SCHEMA_NAME(dp.major_id)
            WHEN 24 THEN (SELECT k.name FROM sys.symmetric_keys k WHERE k.symmetric_key_id = dp.major_id)
            WHEN 25 THEN (SELECT c.name FROM sys.certificates c   WHERE c.certificate_id  = dp.major_id)
            ELSE CONVERT(NVARCHAR(128), dp.major_id)
       END AS objeto,
       dp.permission_name AS permiso,
       dp.state_desc AS estado
FROM sys.database_permissions dp
JOIN sys.database_principals r ON r.principal_id = dp.grantee_principal_id
WHERE r.name IN (N'rol_administrador', N'rol_digitador', N'rol_consulta')
ORDER BY r.name, dp.state_desc, dp.class_desc, objeto, dp.permission_name;
GO

-- indices y planes de ejecucion (REQ 009)
USE PropiDB;
GO
USE PropiDB;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BitacoraAuditoria_fec_registro' AND object_id = OBJECT_ID(N'dbo.Bitacora_Auditoria'))
    DROP INDEX IX_BitacoraAuditoria_fec_registro ON dbo.Bitacora_Auditoria;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CIX_BitacoraAuditoria_fec_registro' AND object_id = OBJECT_ID(N'dbo.Bitacora_Auditoria'))
    DROP INDEX CIX_BitacoraAuditoria_fec_registro ON dbo.Bitacora_Auditoria;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Cliente_fecha_registro' AND object_id = OBJECT_ID(N'dbo.Cliente'))
    DROP INDEX IX_Cliente_fecha_registro ON dbo.Cliente;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Factura_fecha' AND object_id = OBJECT_ID(N'dbo.Factura'))
    DROP INDEX IX_Factura_fecha ON dbo.Factura;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Factura_codigo_cliente' AND object_id = OBJECT_ID(N'dbo.Factura'))
    DROP INDEX IX_Factura_codigo_cliente ON dbo.Factura;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Nota_num_factura' AND object_id = OBJECT_ID(N'dbo.Nota_Credito_Debito'))
    DROP INDEX IX_Nota_num_factura ON dbo.Nota_Credito_Debito;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Nota_fecha' AND object_id = OBJECT_ID(N'dbo.Nota_Credito_Debito'))
    DROP INDEX IX_Nota_fecha ON dbo.Nota_Credito_Debito;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Producto_estado_descripcion' AND object_id = OBJECT_ID(N'dbo.Producto_Servicio'))
    DROP INDEX IX_Producto_estado_descripcion ON dbo.Producto_Servicio;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Cliente_nombre' AND object_id = OBJECT_ID(N'dbo.Cliente'))
    DROP INDEX IX_Cliente_nombre ON dbo.Cliente;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Canton_provincia' AND object_id = OBJECT_ID(N'dbo.Canton'))
    DROP INDEX IX_Canton_provincia ON dbo.Canton;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Distrito_canton' AND object_id = OBJECT_ID(N'dbo.Distrito'))
    DROP INDEX IX_Distrito_canton ON dbo.Distrito;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Barrio_distrito' AND object_id = OBJECT_ID(N'dbo.Barrio'))
    DROP INDEX IX_Barrio_distrito ON dbo.Barrio;
GO

IF OBJECT_ID('tempdb..#carga_req009') IS NOT NULL DROP PROCEDURE #carga_req009;
GO
CREATE PROCEDURE #carga_req009
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @fac_mid   INT = (SELECT num_factura FROM dbo.Factura ORDER BY num_factura OFFSET 700 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @nota_mid  INT = (SELECT numero_nota FROM dbo.Nota_Credito_Debito ORDER BY numero_nota OFFSET 300 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @prod_mid  INT = (SELECT codigo_producto FROM dbo.Producto_Servicio ORDER BY codigo_producto OFFSET 600 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @cli_mid   INT = (SELECT codigo_cliente FROM dbo.Cliente ORDER BY codigo_cliente OFFSET 600 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @fac_txt   VARCHAR(100) = CONVERT(VARCHAR(20), @fac_mid);
    DECLARE @nom_txt   VARCHAR(100) = (SELECT LEFT(nombre, 5) FROM dbo.Cliente WHERE codigo_cliente = @cli_mid);
    DECLARE @prod_txt  VARCHAR(100) = (SELECT LEFT(descripcion, 5) FROM dbo.Producto_Servicio WHERE codigo_producto = @prod_mid);
    DECLARE @prov      INT = (SELECT TOP 1 codigo_provincia FROM dbo.Canton ORDER BY codigo_canton);
    DECLARE @canton    INT = (SELECT TOP 1 codigo_canton FROM dbo.Distrito ORDER BY codigo_distrito);
    DECLARE @distrito  INT = (SELECT TOP 1 codigo_distrito FROM dbo.Barrio ORDER BY codigo_barrio);
    DECLARE @sel_d DATE = DATEADD(DAY, -60,  CAST(GETDATE() AS DATE));
    DECLARE @sel_h DATE = DATEADD(DAY, -30,  CAST(GETDATE() AS DATE));
    DECLARE @amp_d DATE = DATEADD(DAY, -730, CAST(GETDATE() AS DATE));
    DECLARE @amp_h DATE = CAST(GETDATE() AS DATE);

    PRINT N'## C01 usp_Factura_Obtener (por llave primaria)';
    EXEC dbo.usp_Factura_Obtener @num_factura = @fac_mid;
    PRINT N'## C02 usp_Factura_Listar (por número de factura)';
    EXEC dbo.usp_Factura_Listar @texto = @fac_txt;
    PRINT N'## C03 usp_Factura_Listar (por nombre de cliente)';
    EXEC dbo.usp_Factura_Listar @texto = @nom_txt;
    PRINT N'## C04 usp_Factura_Listar (sin filtro, las 500 más recientes)';
    EXEC dbo.usp_Factura_Listar @texto = NULL;
    PRINT N'## C05 usp_Nota_Obtener (por llave primaria)';
    EXEC dbo.usp_Nota_Obtener @numero_nota = @nota_mid;
    PRINT N'## C06 usp_Nota_Listar (por número de factura)';
    EXEC dbo.usp_Nota_Listar @texto = @fac_txt, @tipo = NULL;
    PRINT N'## C07 usp_Nota_Listar (solo notas de crédito, las más recientes)';
    EXEC dbo.usp_Nota_Listar @texto = NULL, @tipo = 'C';
    PRINT N'## C08 usp_Producto_Obtener (por llave primaria)';
    EXEC dbo.usp_Producto_Obtener @codigo_producto = @prod_mid;
    PRINT N'## C09 usp_Producto_Listar (activos, ordenados por descripción)';
    EXEC dbo.usp_Producto_Listar @texto = NULL, @estado = 'A';
    PRINT N'## C10 usp_Producto_Listar (búsqueda por texto)';
    EXEC dbo.usp_Producto_Listar @texto = @prod_txt, @estado = NULL;
    PRINT N'## C11 usp_Cliente_Obtener (por llave primaria)';
    EXEC dbo.usp_Cliente_Obtener @codigo_cliente = @cli_mid;
    PRINT N'## C12 usp_Cliente_Listar (sin filtro, ordenado por nombre)';
    EXEC dbo.usp_Cliente_Listar @texto = NULL, @estado = NULL;
    PRINT N'## C13 usp_Catalogo_Listar cantón (por provincia)';
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'canton', @padre = @prov;
    PRINT N'## C14 usp_Catalogo_Listar distrito (por cantón)';
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'distrito', @padre = @canton;
    PRINT N'## C15 usp_Catalogo_Listar barrio (por distrito)';
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'barrio', @padre = @distrito;
    PRINT N'## C16 usp_Reporte_Clientes (rango selectivo)';
    EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @estado = 'T';
    PRINT N'## C17 usp_Reporte_Facturas (rango selectivo)';
    EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @sel_d, @fecha_hasta = @sel_h;
    PRINT N'## C18 usp_Reporte_Auditoria (rango selectivo)';
    EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @usuario = NULL;
    PRINT N'## C19 usp_Reporte_Auditoria (rango amplio)';
    EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @usuario = NULL;
    PRINT N'## C21 usp_Reporte_Clientes (rango amplio)';
    EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @estado = 'T';
    PRINT N'## C22 usp_Reporte_Facturas (rango amplio)';
    EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @amp_d, @fecha_hasta = @amp_h;
    PRINT N'## C20 usp_Reporte_Seguridad (lee el catálogo del sistema, no tablas del negocio)';
    EXEC dbo.usp_Reporte_Seguridad @usuario = NULL;
END
GO

IF OBJECT_ID('tempdb..#plan_req009') IS NOT NULL DROP PROCEDURE #plan_req009;
GO
CREATE PROCEDURE #plan_req009 @momento NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('tempdb..#pl') IS NOT NULL DROP TABLE #pl;
    ;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT DISTINCT OBJECT_NAME(ps.object_id, ps.database_id) AS proc_nombre,
           x.n.value('@PhysicalOp', 'varchar(40)') AS operador,
           x.n.value('(IndexScan/Object/@Table)[1]', 'sysname') AS tabla,
           ISNULL(x.n.value('(IndexScan/Object/@Index)[1]', 'sysname'), N'(heap)') AS indice
      INTO #pl
      FROM sys.dm_exec_procedure_stats ps
     CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) qp
     CROSS APPLY qp.query_plan.nodes('//RelOp[IndexScan]') x(n)
     WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%';
    DECLARE @p SYSNAME, @t NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT proc_nombre, STRING_AGG(CONVERT(NVARCHAR(MAX), operador + N' ' + tabla + N'.' + indice), N' | ') WITHIN GROUP (ORDER BY tabla, indice)
          FROM #pl GROUP BY proc_nombre ORDER BY proc_nombre;
    OPEN c; FETCH NEXT FROM c INTO @p, @t;
    PRINT N'>>> PLANES ' + @momento;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT N'PLAN ' + @momento + N' | ' + @p + N' | ' + LEFT(@t, 3500);
        FETCH NEXT FROM c INTO @p, @t;
    END
    CLOSE c; DEALLOCATE c;
END
GO

SET NOCOUNT ON;
CHECKPOINT;
DBCC DROPCLEANBUFFERS;
DBCC FREEPROCCACHE;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
PRINT N'>>> ANTES (1)';
EXEC #carga_req009;
PRINT N'>>> ANTES (2)';
EXEC #carga_req009;
EXEC #plan_req009 @momento = N'ANTES';
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

SELECT N'ANTES' AS momento, OBJECT_NAME(ps.object_id, ps.database_id) AS procedimiento,
       ps.last_elapsed_time / 1000.0 AS ms_ultima_ejecucion,
       ps.last_logical_reads AS lecturas_logicas, ps.last_worker_time / 1000.0 AS ms_cpu
  FROM sys.dm_exec_procedure_stats ps
 WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%'
 ORDER BY procedimiento;
GO

CREATE CLUSTERED INDEX CIX_BitacoraAuditoria_fec_registro
    ON dbo.Bitacora_Auditoria (fec_registro);

CREATE NONCLUSTERED INDEX IX_Cliente_fecha_registro
    ON dbo.Cliente (fecha_registro)
    INCLUDE (estado, nombre, codigo_actividad_economica);

CREATE NONCLUSTERED INDEX IX_Factura_fecha
    ON dbo.Factura (fecha)
    INCLUDE (codigo_cliente, subtotal, total_impuestos, monto_total);

CREATE NONCLUSTERED INDEX IX_Factura_codigo_cliente
    ON dbo.Factura (codigo_cliente)
    INCLUDE (fecha, codigo_moneda, subtotal, total_impuestos, monto_total);

CREATE NONCLUSTERED INDEX IX_Nota_num_factura
    ON dbo.Nota_Credito_Debito (num_factura)
    INCLUDE (fecha, tipo, monto);

CREATE NONCLUSTERED INDEX IX_Nota_fecha
    ON dbo.Nota_Credito_Debito (fecha DESC)
    INCLUDE (num_factura, tipo, monto);

CREATE NONCLUSTERED INDEX IX_Producto_estado_descripcion
    ON dbo.Producto_Servicio (estado, descripcion)
    INCLUDE (codigo_CABYS, codigo_unidad_medida, precio, codigo_tipo_impuesto);

CREATE NONCLUSTERED INDEX IX_Cliente_nombre
    ON dbo.Cliente (nombre)
    INCLUDE (estado);

CREATE NONCLUSTERED INDEX IX_Canton_provincia   ON dbo.Canton   (codigo_provincia) INCLUDE (nombre);
CREATE NONCLUSTERED INDEX IX_Distrito_canton    ON dbo.Distrito (codigo_canton)    INCLUDE (nombre);
CREATE NONCLUSTERED INDEX IX_Barrio_distrito    ON dbo.Barrio   (codigo_distrito)  INCLUDE (nombre);
GO

UPDATE STATISTICS dbo.Bitacora_Auditoria WITH FULLSCAN;
UPDATE STATISTICS dbo.Factura WITH FULLSCAN;
UPDATE STATISTICS dbo.Nota_Credito_Debito WITH FULLSCAN;
UPDATE STATISTICS dbo.Producto_Servicio WITH FULLSCAN;
UPDATE STATISTICS dbo.Cliente WITH FULLSCAN;
GO

SET NOCOUNT ON;
CHECKPOINT;
DBCC DROPCLEANBUFFERS;
DBCC FREEPROCCACHE;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
PRINT N'>>> DESPUÉS (1)';
EXEC #carga_req009;
PRINT N'>>> DESPUÉS (2)';
EXEC #carga_req009;
EXEC #plan_req009 @momento = N'DESPUÉS';
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

SELECT N'DESPUÉS' AS momento, OBJECT_NAME(ps.object_id, ps.database_id) AS procedimiento,
       ps.last_elapsed_time / 1000.0 AS ms_ultima_ejecucion,
       ps.last_logical_reads AS lecturas_logicas, ps.last_worker_time / 1000.0 AS ms_cpu
  FROM sys.dm_exec_procedure_stats ps
 WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%'
 ORDER BY procedimiento;
GO

;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT OBJECT_NAME(ps.object_id, ps.database_id) AS procedimiento,
       x.n.value('@PhysicalOp', 'varchar(40)')                                   AS operador,
       x.n.value('(IndexScan/Object/@Table)[1]', 'sysname')                      AS tabla,
       ISNULL(x.n.value('(IndexScan/Object/@Index)[1]', 'sysname'), N'(heap)')   AS indice
  FROM sys.dm_exec_procedure_stats ps
 CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) qp
 CROSS APPLY qp.query_plan.nodes('//RelOp[IndexScan]') x(n)
 WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%'
 ORDER BY procedimiento, tabla;
GO
