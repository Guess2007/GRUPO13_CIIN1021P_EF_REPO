USE master;
GO

DECLARE @RutaBackup NVARCHAR(200) = N'C:\Backups\AtencionesSalud\';

ALTER DATABASE AtencionesSalud SET RECOVERY SIMPLE;
GO

/* -----------------------------------------------------------------------------
   2) RESPALDO FULL (semanal, ejemplo: domingo 01:00 a. m.)
   Incluye CHECKSUM (detecta paginas dañadas) y COMPRESSION (menos espacio/E-S).
   ----------------------------------------------------------------------------- */
BACKUP DATABASE AtencionesSalud
TO DISK = N'C:\Backups\AtencionesSalud\AtencionesSalud_FULL_20260101_0100.bak'
WITH INIT, CHECKSUM, COMPRESSION,
     NAME = N'AtencionesSalud-Full',
     DESCRIPTION = N'Respaldo completo semanal';
GO

-- Verificar que el archivo de respaldo generado es legible y no esta corrupto.
RESTORE VERIFYONLY
FROM DISK = N'C:\Backups\AtencionesSalud\AtencionesSalud_FULL_20260101_0100.bak'
WITH CHECKSUM;
GO

/* -----------------------------------------------------------------------------
   3) RESPALDO DIFFERENTIAL (diario, de lunes a sabado, 01:00 a. m.)
   Guarda solo los datos modificados desde el ultimo FULL: la carga diaria del
   CSV es incremental (nuevas filas de establecimientos/atenciones), asi que un
   diferencial es pequeño en comparacion a repetir un FULL cada dia.
   ----------------------------------------------------------------------------- */
BACKUP DATABASE AtencionesSalud
TO DISK = N'C:\Backups\AtencionesSalud\AtencionesSalud_DIFF_20260102_0100.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM, COMPRESSION,
     NAME = N'AtencionesSalud-Diferencial',
     DESCRIPTION = N'Respaldo diferencial diario';
GO

/* -----------------------------------------------------------------------------
   4) RETENCION (ejemplo con el procedimiento nativo de mantenimiento)
   FULL: 8 semanas. DIFERENCIAL: 2 semanas. Ajustar segun politica interna y
   segun el articulo 11 (conservar evidencia sin acumular datos innecesarios).
   ----------------------------------------------------------------------------- */
-- EXEC master.dbo.xp_delete_file 0, N'C:\Backups\AtencionesSalud\', N'bak', '2026-01-01T00:00:00', 1;

/* =============================================================================
   5) SECUENCIA DE RESTAURACION (FULL -> DIFFERENTIAL -> RECOVERY)
   Un diferencial NO se puede aplicar solo: siempre se restaura sobre el FULL
   del que partio, con NORECOVERY en todos los pasos intermedios y RECOVERY
   solo en el ultimo, para dejar la base en linea al final.
   ============================================================================= */

-- 5.1 Poner la base en modo restauracion exclusiva (opcional pero recomendado)
ALTER DATABASE AtencionesSalud SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

-- 5.2 Restaurar el FULL mas reciente, dejando la base "a medias" (NORECOVERY)
RESTORE DATABASE AtencionesSalud
FROM DISK = N'C:\Backups\AtencionesSalud\AtencionesSalud_FULL_20260101_0100.bak'
WITH NORECOVERY, CHECKSUM,
     REPLACE;   -- REPLACE solo si se restaura sobre una base ya existente
GO

-- 5.3 Restaurar el DIFERENCIAL mas reciente posterior a ese FULL
RESTORE DATABASE AtencionesSalud
FROM DISK = N'C:\Backups\AtencionesSalud\AtencionesSalud_DIFF_20260102_0100.bak'
WITH RECOVERY, CHECKSUM;
GO

-- 5.4 Volver a modo multiusuario
ALTER DATABASE AtencionesSalud SET MULTI_USER;
GO

/* -----------------------------------------------------------------------------
   6) VERIFICACION POST-RESTAURACION (evidencia de la prueba de restauracion)
   Documentar el resultado de estas 3 consultas en cada simulacro de
   restauracion, junto con fecha, responsable y duracion (ver plantilla en
   Informe_Seguridad_Cumplimiento.md).
   ----------------------------------------------------------------------------- */
USE AtencionesSalud;
GO

DBCC CHECKDB (N'AtencionesSalud') WITH NO_INFOMSGS;

SELECT (SELECT COUNT(*) FROM dbo.Atencion)       AS FilasAtencion,
       (SELECT COUNT(*) FROM dbo.Establecimiento) AS FilasEstablecimiento,
       (SELECT MAX(LogId) FROM dbo.LogCargaETL)    AS UltimoLogCarga;

SELECT database_name, backup_start_date, backup_finish_date, type, is_copy_only
FROM msdb.dbo.backupset
WHERE database_name = 'AtencionesSalud'
ORDER BY backup_start_date DESC;
