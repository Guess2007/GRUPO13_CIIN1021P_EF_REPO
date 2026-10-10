/* =============================================================================
   AtencionesSalud - Dominio REEMBOLSOS
   1.2.  PROCEDIMIENTOS
   Requiere haber ejecutado antes AtencionesSalud_reembolsos_1_tablas.sql.
   ============================================================================= */

USE AtencionesSalud;
GO

CREATE PROCEDURE reembolsos.sp_CargarReembolsos
    @FilasInsertadas  INT OUTPUT,
    @FilasDescartadas INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Inicio DATETIME2(0) = SYSDATETIME();

    SET @FilasInsertadas  = 0;
    SET @FilasDescartadas = 0;

    BEGIN TRY
        -- 1) Descartar filas basura (pie de pagina del export, vienen todas en blanco)
        DELETE FROM reembolsos.stg_Reembolsos WHERE LTRIM(RTRIM(Periodo)) = '';
        SET @FilasDescartadas = @@ROWCOUNT;

        -- 2) Poblar catalogos (idempotente: solo lo que no exista todavia)
        INSERT INTO dbo.Region (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.Region))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Region r WHERE r.Nombre = LTRIM(RTRIM(s.Region)));

        INSERT INTO reembolsos.Sede (RegionId, Nombre)
        SELECT DISTINCT r.RegionId, LTRIM(RTRIM(s.Sede))
        FROM reembolsos.stg_Reembolsos s
        JOIN dbo.Region r ON r.Nombre = LTRIM(RTRIM(s.Region))
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.Sede x WHERE x.RegionId = r.RegionId AND x.Nombre = LTRIM(RTRIM(s.Sede)));

        INSERT INTO reembolsos.TipoAtencion (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.TipoDeAtencion))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.TipoAtencion x WHERE x.Nombre = LTRIM(RTRIM(s.TipoDeAtencion)));

        INSERT INTO reembolsos.MedioSolicitud (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.MedioDeSolicitud))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.MedioSolicitud x WHERE x.Nombre = LTRIM(RTRIM(s.MedioDeSolicitud)));

        INSERT INTO reembolsos.TipoSolicitante (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.Solicitante))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.TipoSolicitante x WHERE x.Nombre = LTRIM(RTRIM(s.Solicitante)));

        INSERT INTO reembolsos.CondicionAsegurado (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.CondicionDelAsegurado))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.CondicionAsegurado x WHERE x.Nombre = LTRIM(RTRIM(s.CondicionDelAsegurado)));

        INSERT INTO reembolsos.Parentesco (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.Parentesco))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.Parentesco x WHERE x.Nombre = LTRIM(RTRIM(s.Parentesco)));

        INSERT INTO reembolsos.SituacionAsegurado (Nombre)
        SELECT DISTINCT LTRIM(RTRIM(s.Situacion))
        FROM reembolsos.stg_Reembolsos s
        WHERE NOT EXISTS (SELECT 1 FROM reembolsos.SituacionAsegurado x WHERE x.Nombre = LTRIM(RTRIM(s.Situacion)));

        -- 3) Cargar la tabla de hechos, limpiando el monto ("S/ 1,225,889.22" -> 1225889.22)
        BEGIN TRANSACTION;

        INSERT INTO reembolsos.Reembolso
               (Periodo, SedeId, TipoAtencionId, MedioSolicitudId, TipoSolicitanteId,
                CondicionAseguradoId, ParentescoId, SituacionAseguradoId,
                NumeroAsegurados, SolicitudesReembolso, MontoPagado)
        SELECT CONVERT(DATE, s.Periodo, 103),
               sd.SedeId, ta.TipoAtencionId, ms.MedioSolicitudId, tso.TipoSolicitanteId,
               ca.CondicionAseguradoId, pa.ParentescoId, si.SituacionAseguradoId,
               CAST(LTRIM(RTRIM(s.NumeroDeAsegurados)) AS INT),
               CAST(LTRIM(RTRIM(s.SolicitudesDeReembolso)) AS INT),
               CAST(REPLACE(REPLACE(LTRIM(RTRIM(s.MontoPagado)), 'S/', ''), ',', '') AS DECIMAL(12,2))
        FROM reembolsos.stg_Reembolsos s
        JOIN dbo.Region r                      ON r.Nombre = LTRIM(RTRIM(s.Region))
        JOIN reembolsos.Sede sd                ON sd.RegionId = r.RegionId AND sd.Nombre = LTRIM(RTRIM(s.Sede))
        JOIN reembolsos.TipoAtencion ta         ON ta.Nombre = LTRIM(RTRIM(s.TipoDeAtencion))
        JOIN reembolsos.MedioSolicitud ms       ON ms.Nombre = LTRIM(RTRIM(s.MedioDeSolicitud))
        JOIN reembolsos.TipoSolicitante tso     ON tso.Nombre = LTRIM(RTRIM(s.Solicitante))
        JOIN reembolsos.CondicionAsegurado ca   ON ca.Nombre = LTRIM(RTRIM(s.CondicionDelAsegurado))
        JOIN reembolsos.Parentesco pa           ON pa.Nombre = LTRIM(RTRIM(s.Parentesco))
        JOIN reembolsos.SituacionAsegurado si   ON si.Nombre = LTRIM(RTRIM(s.Situacion))
        WHERE NOT EXISTS (
              SELECT 1 FROM reembolsos.Reembolso x
              WHERE x.Periodo = CONVERT(DATE, s.Periodo, 103) AND x.SedeId = sd.SedeId
                AND x.TipoAtencionId = ta.TipoAtencionId AND x.MedioSolicitudId = ms.MedioSolicitudId
                AND x.TipoSolicitanteId = tso.TipoSolicitanteId AND x.CondicionAseguradoId = ca.CondicionAseguradoId
                AND x.ParentescoId = pa.ParentescoId AND x.SituacionAseguradoId = si.SituacionAseguradoId
        );

        SET @FilasInsertadas = @@ROWCOUNT;

        COMMIT TRANSACTION;

        INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, FilasRechazadas, Estado, MensajeError)
        VALUES ('reembolsos.sp_CargarReembolsos', @Inicio, SYSDATETIME(), @FilasInsertadas, @FilasDescartadas, 'OK', NULL);
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @FilasInsertadas = 0;
        INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, FilasRechazadas, Estado, MensajeError)
        VALUES ('reembolsos.sp_CargarReembolsos', @Inicio, SYSDATETIME(), 0, @FilasDescartadas, 'ERROR', ERROR_MESSAGE());

        THROW;
    END CATCH
END
GO
