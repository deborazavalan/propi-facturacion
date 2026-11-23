/* =====================================================================
   PropiDB - REQ 014, paso 5b: CONMUTACIÓN DE REGRESO, parte en PT
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERPT   (vuelve a ser la primaria)
   Requisito: haber corrido replicacion_5a_regreso_en_sj.sql.

   Qué hace:
   1. Aplica la cola del registro de SJ con RECOVERY: PropiDB queda
      ONLINE y con escritura otra vez en PT.
   2. Protege la llave maestra con la llave de este servidor.
   3. Vuelve a habilitar el respaldo del trasvase (PT -> SJ cada 10 s).
   4. Verifica: filas de prueba, cantidades, descifrado y RTO medido.
   ===================================================================== */
SET NOEXEC OFF;
GO
USE master;
GO
PRINT N'Instancia actual: ' + @@SERVERNAME;
IF @@SERVERNAME NOT LIKE N'%\SQLSERVERPT'
BEGIN
    RAISERROR(N'Este script va en SQLSERVERPT. Están conectadas a otra instancia; no se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO
IF DATABASEPROPERTYEX(N'PropiDB', 'Status') <> 'RESTORING'
BEGIN
    RAISERROR(N'PropiDB no está en RESTORING aquí. No se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------- 1. Aplicar la cola de SJ y poner en línea ---------- */
DECLARE @k NVARCHAR(MAX) = N'';
SELECT @k += N'KILL ' + CONVERT(NVARCHAR(10), s.session_id) + N'; '
FROM sys.dm_exec_sessions s
WHERE s.session_id <> @@SPID
  AND (s.database_id = DB_ID(N'PropiDB')
       OR s.session_id IN (SELECT request_session_id FROM sys.dm_tran_locks
                           WHERE resource_database_id = DB_ID(N'PropiDB')));
EXEC (@k);
GO
RESTORE LOG PropiDB
    FROM DISK = N'C:\SQLBackups\PropiDB_tail_sj.trn'
    WITH RECOVERY;
GO
ALTER DATABASE PropiDB SET MULTI_USER;
GO

/* ---------- 2. Llave maestra protegida por este servidor ---------- */
USE PropiDB;
GO
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Propi_MasterKey_2026!';
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
CLOSE MASTER KEY;
GO

/* ---------- 3. Reanudar el trasvase PT -> SJ ---------- */
EXEC msdb.dbo.sp_update_job @job_name = N'LSBackup_PropiDB', @enabled = 1;
GO

/* =====================================================================
   VERIFICACIÓN
   ===================================================================== */
/* 1. ONLINE, con escritura, MULTI_USER */
SELECT name, state_desc, is_read_only, user_access_desc
FROM sys.databases WHERE name = N'PropiDB';

/* 2. Las dos filas de prueba (la de PT y la de SJ). La de SJ trae el
      RTO de esta conmutación de regreso */
SELECT id, momento, instancia AS escrita_en, nota,
       @@SERVERNAME AS ahora_en,
       CASE WHEN id = (SELECT MAX(id) FROM dbo.Prueba_REQ014)
            THEN DATEDIFF(SECOND, momento, SYSDATETIME()) END AS rto_segundos
FROM dbo.Prueba_REQ014
ORDER BY id;

/* 3. Mismas cantidades */
SELECT (SELECT COUNT(*) FROM dbo.Cliente)            AS clientes,
       (SELECT COUNT(*) FROM dbo.Factura)            AS facturas,
       (SELECT COUNT(*) FROM dbo.Bitacora_Auditoria) AS filas_auditoria;

/* 4. Descifrado sin contraseña */
OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;
SELECT TOP (3) codigo_cliente, nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono
FROM dbo.Cliente
ORDER BY codigo_cliente DESC;
CLOSE SYMMETRIC KEY sk_propi_clientes;
GO
USE master;
GO

/* 5. El trasvase vuelve a respaldar (esperar 20 s) */
WAITFOR DELAY '00:00:20';
SELECT primary_database, last_backup_file, last_backup_date,
       DATEDIFF(SECOND, last_backup_date, GETDATE()) AS segundos_desde_ultimo
FROM msdb.dbo.log_shipping_monitor_primary
WHERE primary_database = N'PropiDB';
GO

SET NOEXEC OFF;
GO
