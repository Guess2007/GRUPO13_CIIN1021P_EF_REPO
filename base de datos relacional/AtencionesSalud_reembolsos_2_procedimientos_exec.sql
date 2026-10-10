USE AtencionesSalud;
GO

DECLARE @FilasInsertadas INT, @FilasDescartadas INT;

EXEC reembolsos.sp_CargarReembolsos
    @FilasInsertadas  = @FilasInsertadas  OUTPUT,
    @FilasDescartadas = @FilasDescartadas OUTPUT;

PRINT CONCAT('Reembolsos insertados: ', @FilasInsertadas, ' | Filas descartadas (vacías): ', @FilasDescartadas);
GO

-- Verificación
SELECT (SELECT COUNT(*) FROM reembolsos.stg_Reembolsos) AS FilasEnStaging,
       (SELECT COUNT(*) FROM reembolsos.Reembolso)      AS FilasEnTablaDeHechos;

SELECT TOP 10 * FROM dbo.LogCargaETL WHERE Proceso = 'reembolsos.sp_CargarReembolsos' ORDER BY LogId DESC;