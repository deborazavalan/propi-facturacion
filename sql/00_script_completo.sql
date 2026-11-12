/* =====================================================================
   PropiDB - Script completo (punto de control)
   Parte 1: base de datos, tablas, catálogos, cifrado, roles y usuarios (Daniela)
   Parte 2: procedimientos almacenados de la aplicación y sus permisos (Débora)
   Ejecutar completo (Ctrl+A, F5). OJO: borra y vuelve a crear PropiDB.
   Después ejecutar, en este orden: triggers_auditoria, dataset_propi,
   reportes_propi y permisos_roles.
   ===================================================================== */
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
--necesario para respaldos de log (REQ 013) y replicación (REQ 014)
ALTER DATABASE PropiDB SET RECOVERY FULL;
GO
USE PropiDB;
GO

--catalagos
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
    codigo_moneda CHAR(3)     NOT NULL CONSTRAINT PK_Moneda PRIMARY KEY,   -- ISO 4217: CRC, USD
    descripcion   VARCHAR(30) NOT NULL
);
GO

--tablas
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
    numero_identificacion      VARBINARY(512) NOT NULL, --para el cifrado
    hash_identificacion        VARBINARY(32)  NOT NULL CONSTRAINT UQ_Cliente_Identificacion UNIQUE,
    codigo_barrio              INT            NOT NULL CONSTRAINT FK_Cliente_Barrio REFERENCES dbo.Barrio(codigo_barrio),
    direccion                  VARCHAR(250)   NULL,       
    profesion                  VARCHAR(100)   NULL,
    codigo_actividad_economica VARCHAR(6)     NOT NULL CONSTRAINT FK_Cliente_Actividad_Economica REFERENCES dbo.Actividad_Economica(codigo_actividad_economica),
    correo                     VARBINARY(512) NOT NULL,   -- cifrado
    telefono                   VARBINARY(512) NOT NULL,   -- cifrado
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
    tipo        CHAR(1)       NOT NULL CONSTRAINT CK_Nota_Credito_Debito_Tipo CHECK (tipo IN ('C','D')),  -- C crédito / D débito
    motivo      VARCHAR(500)  NOT NULL,
    monto       DECIMAL(18,2) NOT NULL CONSTRAINT CK_Nota_Credito_Debito_Monto CHECK (monto > 0)
);
GO

--bitacoras
CREATE TABLE dbo.Bitacora_Acceso (
    codigo_acceso  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Bitacora_Acceso PRIMARY KEY,
    usuario        VARCHAR(128) NOT NULL,
    terminal       VARCHAR(128) NOT NULL,
    direccion_ip   VARCHAR(45)  NULL,        -- 45 que admite IPv6
    fecha_ingreso  DATETIME     NOT NULL,
    fecha_salida   DATETIME     NULL,
    fecha_registro DATETIME     NOT NULL CONSTRAINT DF_Bitacora_Acceso_Fecha_Registro DEFAULT GETDATE()
);
GO

--REQ 005
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

--(adelanto de REQ 006)
 
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Propi_MasterKey_2026!';
GO
CREATE CERTIFICATE cert_propi_clientes
    WITH SUBJECT = 'Cifrado de datos sensibles de Cliente';
GO
CREATE SYMMETRIC KEY sk_propi_clientes
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE cert_propi_clientes;
GO

--triggers
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

--factura
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
   --7. logins usuarios y roles (REQ 003 / REQ 004)
  -- Los permisos (REQ 008)
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
CREATE ROLE rol_administrador;   --Acceso total
CREATE ROLE rol_digitador;       --Clientes, facturas y notas de crédito/débito
CREATE ROLE rol_consulta;        --reportes
GO
ALTER ROLE rol_administrador ADD MEMBER usr_admin;
ALTER ROLE rol_digitador     ADD MEMBER usr_digitador;
ALTER ROLE rol_consulta      ADD MEMBER usr_consulta;
GO

--datos catalogo
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

--Códigos CABYS(son ejemplos)
INSERT INTO dbo.Producto_Servicio (codigo_CABYS, descripcion, codigo_unidad_medida, precio, codigo_tipo_impuesto) VALUES
('7211100000000','Venta de lote residencial','Unid', 25000000.00, 4),
('7212100000000','Comisión por intermediación inmobiliaria','Sp', 1500000.00, 1),
('7211200000000','Alquiler de local comercial (mensual)','Os', 450000.00, 1);
GO

--pruebas

-- Simula lo que hará la app después del login
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

--Factura con detalle
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

--encriptado 
 SELECT * FROM dbo.Cliente
--Ver clientes desencriptados(asi se vera el frontend)
SELECT codigo_cliente,
       nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono,
       estado
FROM dbo.Cliente;

CLOSE SYMMETRIC KEY sk_propi_clientes;

--bitácora
SELECT fec_registro, ind_accion, RTRIM(cod_usuario) AS cod_usuario, cod_sesion_usuario,
       cod_tabla, cod_llave, des_datos
FROM dbo.Bitacora_Auditoria
ORDER BY fec_registro;

-- Verificar usuarios y roles
SELECT r.name AS rol, m.name AS usuario
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE 'rol_%';
GO

GO

USE PropiDB;
GO

-- =====================================================================
-- PARTE DE DÉBORA (Persona B) - punto de control 1
-- Aquí están los procedimientos almacenados que usa la aplicación web.
-- La app solo llama a estos SP, nunca ejecuta SQL directo.
-- Se corre después del script de Daniela (necesita sus tablas, la llave
-- de cifrado, los triggers y los roles).
-- Se puede correr varias veces porque usa CREATE OR ALTER.
--
-- Cosas que se repiten en casi todos los SP:
--   * SET XACT_ABORT ON -> si hay un error se cancela toda la transacción
--   * BEGIN TRY / CATCH -> si algo falla se hace ROLLBACK y se avisa a la app con THROW
--   * errores propios 50010 en adelante -> la app muestra el mensaje tal cual
--   * @id_sesion -> el codigo_acceso del ingreso, para ligarlo con la auditoría
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. SESIÓN Y BITÁCORA DE ACCESOS (REQ 003)
-- ---------------------------------------------------------------------

-- Devuelve quién entró y con qué rol.
-- La app la llama apenas el login funciona, así sabe qué mostrarle a la persona.
-- Si no está en ningún rol devuelve 'sin_rol' y la app no lo deja pasar.
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

-- Registra el ingreso en Bitacora_Acceso y devuelve el codigo_acceso (OUTPUT).
-- El usuario sale de ORIGINAL_LOGIN(), no lo manda la app, así nadie puede poner otro nombre.
-- Va con EXECUTE AS OWNER porque los usuarios no tienen permiso directo sobre la tabla.
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

        -- LEFT por si la terminal o la ip vienen más largas que la columna
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

-- Pone la fecha de salida cuando la persona cierra sesión (o por inactividad).
-- Solo cierra accesos del mismo usuario que los abrió y que todavía no tienen salida.
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


-- ---------------------------------------------------------------------
-- 2. CATÁLOGOS (para las listas desplegables del formulario)
-- Todos devuelven (codigo, nombre).
-- @padre se usa para la cascada: cantón depende de provincia,
-- distrito de cantón y barrio de distrito.
-- ---------------------------------------------------------------------
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
            -- el nombre lleva el código adelante para que sea más fácil ubicarla
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


-- ---------------------------------------------------------------------
-- 3. CLIENTES
-- identificación, correo y teléfono se guardan cifrados con la llave
-- sk_propi_clientes (la de Daniela).
-- Como cifrado no se puede buscar ni comparar, también se guarda un hash
-- SHA-256 de la identificación (hash_identificacion). Con ese hash se busca
-- y se evita que se repita un cliente, sin descifrar nada.
-- ---------------------------------------------------------------------

-- Validaciones que comparten insertar y actualizar.
-- Es de uso interno, por eso no se le da permiso a ningún rol.
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

    -- validaciones de la cédula: solo números y la longitud que corresponde a cada tipo
    IF ISNULL(@numero_identificacion, '') = '' OR @numero_identificacion LIKE '%[^0-9]%'
        THROW 50012, N'La identificación debe contener solo dígitos, sin guiones ni espacios.', 1;
    IF (@codigo_tipo_identificacion = '01' AND LEN(@numero_identificacion) <> 9)
       OR (@codigo_tipo_identificacion = '02' AND LEN(@numero_identificacion) <> 10)
       OR (@codigo_tipo_identificacion = '03' AND LEN(@numero_identificacion) NOT IN (11, 12))
       OR (@codigo_tipo_identificacion = '04' AND LEN(@numero_identificacion) <> 10)
        THROW 50013, N'La longitud de la identificación no corresponde al tipo (física 9, jurídica 10, DIMEX 11 o 12, NITE 10).', 1;

    -- se revisa que el barrio y la actividad existan para dar un mensaje claro
    -- (si no, saldría el error de llave foránea, que no se entiende)
    IF @codigo_barrio IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Barrio WHERE codigo_barrio = @codigo_barrio)
        THROW 50014, N'Seleccione un barrio válido (provincia, cantón, distrito y barrio).', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Actividad_Economica WHERE codigo_actividad_economica = @codigo_actividad_economica AND estado = 'A')
        THROW 50015, N'La actividad económica no es válida.', 1;

    -- correo: algo@algo.algo y sin espacios
    IF ISNULL(@correo, '') = '' OR @correo NOT LIKE '_%@_%._%' OR @correo LIKE '% %'
        THROW 50016, N'El correo electrónico no es válido.', 1;

    -- teléfono: mínimo 8 caracteres y solo números, +, espacio o guion
    IF ISNULL(@telefono, '') = '' OR @telefono LIKE '%[^0-9+ -]%' OR LEN(@telefono) < 8
        THROW 50017, N'El teléfono no es válido (mínimo 8 dígitos; se permiten +, espacio y guion).', 1;

    IF @estado IS NULL OR @estado NOT IN ('A', 'I')
        THROW 50019, N'El estado debe ser A (activo) o I (inactivo).', 1;
END
GO

-- Crea un cliente. Devuelve el codigo_cliente nuevo por el OUTPUT.
-- con EXECUTE AS OWNER la llave y el certificado los abre el dueño (dbo), así el digitador
-- no necesita permisos sobre ellos (permisos_roles.sql se los quita)
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
        -- quito espacios sobrantes; los campos opcionales vacíos pasan a NULL
        SET @nombre                = LTRIM(RTRIM(@nombre));
        SET @numero_identificacion = LTRIM(RTRIM(@numero_identificacion));
        SET @correo                = LTRIM(RTRIM(@correo));
        SET @telefono              = LTRIM(RTRIM(@telefono));
        SET @direccion             = NULLIF(LTRIM(RTRIM(@direccion)), '');
        SET @profesion             = NULLIF(LTRIM(RTRIM(@profesion)), '');

        EXEC dbo.usp_Cliente_Validar @nombre, @codigo_tipo_identificacion, @numero_identificacion, @codigo_barrio,
                                     @codigo_actividad_economica, @correo, @telefono, @estado;

        -- huella de la identificación para buscar y evitar repetidos
        DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256', @numero_identificacion);

        -- se deja el id de sesión para que los triggers lo guarden en la auditoría
        EXEC sp_set_session_context N'id_sesion', @id_sesion;

        -- hay que abrir la llave para poder cifrar
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
        -- si falló con la llave abierta, se cierra
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes') CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

-- Modifica un cliente. Es igual que insertar, pero al revisar el hash
-- se ignora el mismo cliente (para que pueda guardar sin cambiar su cédula).
-- (EXECUTE AS OWNER: ver nota en usp_Cliente_Insertar)
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

        -- que la cédula no sea de otro cliente
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

        -- si no tocó ninguna fila es porque ese cliente no existe
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

-- Borra un cliente. No necesita la llave porque no toca datos cifrados.
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
        THROW;   -- con facturas relacionadas llega el error 547 (FK) y la app sugiere inactivar
    END CATCH
END
GO

-- Un cliente completo y descifrado, para cargar el formulario de edición.
-- Además de los nombres devuelve los códigos de provincia, cantón y distrito,
-- porque el formulario los necesita para rellenar la cascada.
-- (EXECUTE AS OWNER: ver nota en usp_Cliente_Insertar)
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

-- Lista de clientes para la tabla de la pantalla (ya descifrados).
-- @texto busca por nombre (parcial) o por identificación (exacta, comparando el hash).
-- @estado filtra activos o inactivos; si va NULL trae todos.
-- (EXECUTE AS OWNER: ver nota en usp_Cliente_Insertar)
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


-- ---------------------------------------------------------------------
-- 4. TIPOS DE IMPUESTO
-- Mismo patrón que clientes pero sin cifrado.
-- codigo_tipo_impuesto es IDENTITY; lo que no puede repetirse es la
-- combinación codigo_impuesto + tarifa (UNIQUE de la tabla).
-- ---------------------------------------------------------------------

-- Validaciones compartidas por insertar y actualizar (uso interno)
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

        -- se revisa antes para dar un mensaje claro y no el error del UNIQUE
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

        -- que la combinación código + tarifa no sea de otro impuesto
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
        THROW;   -- si algún producto lo usa llega el error 547 (FK)
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

-- Lista para la tabla de la pantalla. @texto busca en la descripción,
-- en el código de impuesto o en la tarifa.
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


-- ---------------------------------------------------------------------
-- 5. PERMISOS
-- Los roles solo reciben EXECUTE sobre los SP, no sobre las tablas.
-- Funciona porque los SP y las tablas son del mismo dueño (dbo), entonces
-- SQL Server no revisa permisos sobre las tablas (encadenamiento de propiedad).
--
-- Administrador: todo.
-- Digitador: crea y edita clientes, pero no elimina; los impuestos solo los ve.
-- Consulta: solo entra (sesión y bitácora), no tiene acceso al CRUD.
-- usp_Cliente_Validar y usp_TipoImpuesto_Validar no se otorgan porque son internos.
-- ---------------------------------------------------------------------
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

-- Para descifrar, SQL Server pide permiso para abrir la llave simétrica
-- (VIEW DEFINITION) y para usar el certificado que la protege (CONTROL).
-- Como los SP de clientes ya usan EXECUTE AS OWNER, permisos_roles.sql se los quita
-- después al digitador; aquí solo quedan para el administrador al crear los SP.
GRANT VIEW DEFINITION ON SYMMETRIC KEY::sk_propi_clientes TO rol_administrador, rol_digitador;
GRANT CONTROL ON CERTIFICATE::cert_propi_clientes         TO rol_administrador, rol_digitador;
GO
