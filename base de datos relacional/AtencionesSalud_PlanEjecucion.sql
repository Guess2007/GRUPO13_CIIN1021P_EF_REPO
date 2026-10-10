USE AtencionesSalud;
GO

DBCC FREEPROCCACHE;   -- limpiar plan cacheado para que la medicion sea comparable
DBCC DROPCLEANBUFFERS; -- forzar lectura desde disco, no desde cache de datos
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* =============================================================================
   PASO 1 - LINEA BASE (sin indice sobre TipoSeguroId)
   Anotar en el informe: tipo de operador, "logical reads" y "elapsed time".
   ============================================================================= */
SELECT ts.Nombre AS TipoSeguro,
       COUNT(*)          AS Registros,
       SUM(a.Atendidos)  AS TotalAtendidos,
       SUM(a.Atenciones) AS TotalAtenciones
FROM dbo.Atencion a
JOIN dbo.TipoSeguro ts ON ts.TipoSeguroId = a.TipoSeguroId
WHERE ts.Nombre = 'S.I.S'
  AND a.Fecha BETWEEN '2023-01-01' AND '2023-01-31'
GROUP BY ts.Nombre;
GO

/* =============================================================================
   PASO 2 - CREAR EL INDICE
   Se agrega TipoSeguroId (el filtro) junto con Fecha (el segundo filtro) y se
   incluyen Atendidos/Atenciones para que el motor no necesite volver a la
   tabla base (index-only / covering index) al calcular los SUM().
   ============================================================================= */
CREATE NONCLUSTERED INDEX IX_Atencion_TipoSeguro_Fecha
    ON dbo.Atencion (TipoSeguroId, Fecha)
    INCLUDE (Atendidos, Atenciones);
GO

/* =============================================================================
   PASO 3 - MISMA CONSULTA CON EL INDICE NUEVO
   Debe verse "Index Seek" sobre IX_Atencion_TipoSeguro_Fecha en el plan, y
   menos "logical reads" que en el Paso 1.
   ============================================================================= */
DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
GO

SELECT ts.Nombre AS TipoSeguro,
       COUNT(*)          AS Registros,
       SUM(a.Atendidos)  AS TotalAtendidos,
       SUM(a.Atenciones) AS TotalAtenciones
FROM dbo.Atencion a
JOIN dbo.TipoSeguro ts ON ts.TipoSeguroId = a.TipoSeguroId
WHERE ts.Nombre = 'S.I.S'
  AND a.Fecha BETWEEN '2023-01-01' AND '2023-01-31'
GROUP BY ts.Nombre;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =============================================================================
   PASO 4 - CONFIRMAR EL PLAN DE FORMA PROGRAMATICA (opcional)
   Alternativa a mirar el plan grafico: sys.dm_exec_query_stats guarda las
   estadisticas de ejecucion reales de las consultas ya cacheadas.
   ============================================================================= */
SELECT TOP 5
       qs.execution_count,
       qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
       qs.total_elapsed_time  / qs.execution_count AS avg_elapsed_micros,
       SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
           ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
             - qs.statement_start_offset)/2) + 1) AS texto_consulta
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.text LIKE '%TotalAtendidos%'
ORDER BY qs.last_execution_time DESC;
