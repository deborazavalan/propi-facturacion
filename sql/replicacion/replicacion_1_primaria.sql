/* =====================================================================
   PropiDB - REQ 014, paso 1: dejar lista la instancia PRIMARIA
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERPT   (la primaria)
   NO ejecutar en SQLEXPRESS (ahí está la base original).

   Qué hace:
   1. Restaura PropiDB desde C:\SQLBackups\PropiDB_full.bak
      (el respaldo que ya hicieron).
   2. Deja el modelo de recuperación en FULL (necesario para el trasvase
      de registros).
   3. Protege la llave maestra de la base también con la llave maestra
      del servidor, para que los procedimientos abran la llave de cifrado
      sin pedir contraseña.
   4. Crea los 3 logins (admin, digitador, consulta) y los enlaza con los
      usuarios que vienen dentro de la base.
   5. Verifica que todo funcione, incluido el descifrado.

   Si PropiDB ya existe en esta instancia, el script se detiene sin
   tocar nada.
   ===================================================================== */
SET NOEXEC OFF;
GO
USE master;
GO
PRINT N'Instancia actual: ' + @@SERVERNAME;
GO
IF DB_ID(N'PropiDB') IS NOT NULL
BEGIN
    DECLARE @srv NVARCHAR(128) = @@SERVERNAME;
    RAISERROR(N'PropiDB ya existe en %s. El script se detiene para no sobrescribirla.', 16, 1, @srv);
    SET NOEXEC ON;
END
GO

/* ---------- 1. Restaurar (usa las carpetas por defecto de esta instancia) ---------- */
DECLARE @d NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultDataPath'));
DECLARE @l NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultLogPath'));
DECLARE @sql NVARCHAR(MAX) =
    N'RESTORE DATABASE PropiDB FROM DISK = N''C:\SQLBackups\PropiDB_full.bak'' '
  + N'WITH MOVE N''PropiDB''     TO N''' + @d + N'PropiDB.mdf'', '
  + N'     MOVE N''PropiDB_log'' TO N''' + @l + N'PropiDB_log.ldf'', '
  + N'RECOVERY, STATS = 10;';
EXEC sys.sp_executesql @sql;
GO

/* ---------- 2. Modelo de recuperación FULL ---------- */
ALTER DATABASE PropiDB SET RECOVERY FULL;
GO

/* ---------- 3. Llave maestra de la base protegida por el servidor ---------- */
USE PropiDB;
GO
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Propi_MasterKey_2026!';
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
CLOSE MASTER KEY;
GO

/* ---------- 4. Logins y enlace con los usuarios de la base ---------- */
USE master;
GO
IF SUSER_ID(N'usr_admin') IS NULL
    CREATE LOGIN usr_admin WITH PASSWORD = 'Adm!n_Propi2026', DEFAULT_DATABASE = PropiDB,
        CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF SUSER_ID(N'usr_digitador') IS NULL
    CREATE LOGIN usr_digitador WITH PASSWORD = 'D!gita_Propi2026', DEFAULT_DATABASE = PropiDB,
        CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF SUSER_ID(N'usr_consulta') IS NULL
    CREATE LOGIN usr_consulta WITH PASSWORD = 'C0nsulta_Propi2026!', DEFAULT_DATABASE = PropiDB,
        CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO
USE PropiDB;
GO
ALTER USER usr_admin     WITH LOGIN = usr_admin;
ALTER USER usr_digitador WITH LOGIN = usr_digitador;
ALTER USER usr_consulta  WITH LOGIN = usr_consulta;
GO

/* =====================================================================
   VERIFICACIÓN
   ===================================================================== */

/* 1. La base debe estar ONLINE y en FULL */
SELECT name, state_desc, recovery_model_desc FROM sys.databases WHERE name = N'PropiDB';

/* 2. Usuarios sin login (debe dar 0 filas) */
SELECT dp.name AS usuario_sin_login
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.type = 'S'
  AND dp.authentication_type_desc = 'INSTANCE'
  AND sp.sid IS NULL
  AND dp.name NOT IN (N'dbo', N'guest', N'INFORMATION_SCHEMA', N'sys');

/* 3. Filas de las tablas principales */
SELECT (SELECT COUNT(*) FROM dbo.Cliente)            AS clientes,
       (SELECT COUNT(*) FROM dbo.Factura)            AS facturas,
       (SELECT COUNT(*) FROM dbo.Bitacora_Auditoria) AS filas_auditoria;

/* 4. El descifrado debe mostrar identificación, correo y teléfono legibles,
      sin escribir ninguna contraseña */
OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;
SELECT TOP (3) codigo_cliente, nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono
FROM dbo.Cliente
ORDER BY codigo_cliente DESC;
CLOSE SYMMETRIC KEY sk_propi_clientes;
GO

SET NOEXEC OFF;
GO
