/* =============================================================================
   AtencionesSalud - Dominio ATENCIONES DE SALUD
   1.2.  PROCEDIMIENTOS
   Estos son los procedimientos que CONECTAN los datos ya insertados en
   dbo.stg_Atenciones (via AtencionesSalud_inserts_atenciones_muestra.sql o
   BULK INSERT) con las tablas reales del modelo (dimensiones + hechos):

     1) sp_CargarDimensiones  -> puebla Red, Microred, Provincia, Distrito,
        CategoriaEstablecimiento, Etnia, TipoSeguro, Ups y Establecimiento
        a partir de lo que haya en stg_Atenciones.
     2) sp_CargarAtenciones   -> valida cada fila de stg_Atenciones y, si
        pasa las reglas de negocio, la inserta en la tabla de hechos
        dbo.Atencion, enlazandola con las dimensiones que acaba de poblar
        sp_CargarDimensiones.

   Requiere: AtencionesSalud_atenciones_1_tablas.sql ya ejecutado, y datos ya
   cargados en dbo.stg_Atenciones (INSERT o BULK INSERT).
   ============================================================================= */

USE AtencionesSalud;
GO

CREATE PROCEDURE dbo.sp_CargarDimensiones
    @FilasNuevasEstablecimiento INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;  -- necesitamos decidir nosotros mismos si se revierte todo o solo una parte
    DECLARE @Inicio DATETIME2(0) = SYSDATETIME();
    DECLARE @ErrorMsg NVARCHAR(4000);

    SET @FilasNuevasEstablecimiento = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Red (Nombre)
        SELECT DISTINCT s.RED
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Red r WHERE r.Nombre = s.RED);

        INSERT INTO dbo.Provincia (Nombre)
        SELECT DISTINCT s.PROVINCIA
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Provincia p WHERE p.Nombre = s.PROVINCIA);

        INSERT INTO dbo.CategoriaEstablecimiento (Codigo)
        SELECT DISTINCT s.CATEGORIA
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.CategoriaEstablecimiento c WHERE c.Codigo = s.CATEGORIA);

        INSERT INTO dbo.Etnia (Nombre)
        SELECT DISTINCT s.ETNIA
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Etnia e WHERE e.Nombre = s.ETNIA);

        INSERT INTO dbo.TipoSeguro (Nombre)
        SELECT DISTINCT s.TIPO_SEGURO
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.TipoSeguro t WHERE t.Nombre = s.TIPO_SEGURO);

        INSERT INTO dbo.Ups (Nombre)
        SELECT DISTINCT s.UPS
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Ups u WHERE u.Nombre = s.UPS);

        INSERT INTO dbo.Microred (RedId, Nombre)
        SELECT DISTINCT r.RedId, s.MICRORED
        FROM dbo.stg_Atenciones s
        JOIN dbo.Red r ON r.Nombre = s.RED
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Microred m WHERE m.RedId = r.RedId AND m.Nombre = s.MICRORED);

        INSERT INTO dbo.Distrito (ProvinciaId, Nombre)
        SELECT DISTINCT p.ProvinciaId, s.DISTRITO
        FROM dbo.stg_Atenciones s
        JOIN dbo.Provincia p ON p.Nombre = s.PROVINCIA
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Distrito d WHERE d.ProvinciaId = p.ProvinciaId AND d.Nombre = s.DISTRITO);

        -- Punto de control: de aqui en adelante, si algo falla, solo se deshace este bloque.
        SAVE TRANSACTION PuntoEstablecimiento;

        BEGIN TRY
            INSERT INTO dbo.Establecimiento (CodigoUnico, Nombre, CategoriaId, MicroredId, DistritoId)
            SELECT DISTINCT s.CODIGO_UNICO, s.NOMBRE_ESTACLECIMIENTO, c.CategoriaId, m.MicroredId, d.DistritoId
            FROM dbo.stg_Atenciones s
            JOIN dbo.CategoriaEstablecimiento c ON c.Codigo = s.CATEGORIA
            JOIN dbo.Red r        ON r.Nombre = s.RED
            JOIN dbo.Microred m   ON m.RedId = r.RedId AND m.Nombre = s.MICRORED
            JOIN dbo.Provincia p  ON p.Nombre = s.PROVINCIA
            JOIN dbo.Distrito d   ON d.ProvinciaId = p.ProvinciaId AND d.Nombre = s.DISTRITO
            WHERE NOT EXISTS (SELECT 1 FROM dbo.Establecimiento e WHERE e.CodigoUnico = s.CODIGO_UNICO);

            SET @FilasNuevasEstablecimiento = @@ROWCOUNT;
        END TRY
        BEGIN CATCH
            SET @ErrorMsg = ERROR_MESSAGE();
            ROLLBACK TRANSACTION PuntoEstablecimiento;  -- deshace solo Establecimiento; el resto sigue en pie
            SET @FilasNuevasEstablecimiento = 0;

            INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, Estado, MensajeError)
            VALUES ('sp_CargarDimensiones:Establecimiento', @Inicio, SYSDATETIME(), 0, 'ERROR_PARCIAL', @ErrorMsg);
        END CATCH

        COMMIT TRANSACTION;

        INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, Estado, MensajeError)
        VALUES ('sp_CargarDimensiones', @Inicio, SYSDATETIME(), @FilasNuevasEstablecimiento, 'OK', NULL);
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ErrorMsg = ERROR_MESSAGE();
        INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, Estado, MensajeError)
        VALUES ('sp_CargarDimensiones', @Inicio, SYSDATETIME(), 0, 'ERROR', @ErrorMsg);

        THROW;
    END CATCH
END
GO

/* -----------------------------------------------------------------------------
   dbo.sp_CargarAtenciones
   Proposito:
     Validar dbo.stg_Atenciones fila por regla de negocio, registrar en
     dbo.LogErroresValidacion las que no cumplen, e insertar en la tabla de
     hechos dbo.Atencion unicamente las filas validas y que aun no existan
     (para poder reejecutar el procedimiento sin duplicar). Requiere haber
     corrido antes dbo.sp_CargarDimensiones.
   Parametros:
     @FilasInsertadas OUTPUT INT - filas nuevas insertadas en dbo.Atencion.
     @FilasRechazadas OUTPUT INT - filas de staging que incumplieron alguna regla.
   Reglas validadas:
     - SEXO debe ser 'F' o 'M'.
     - EDAD_REG coherente con TIPO_EDAD (dias 0-364, meses 0-11, años -1 a 99).
     - CODIGO_UNICO debe existir en dbo.Establecimiento (evita huerfanos).
     - ATENDIDOS y ATENCIONES no negativos, y ATENCIONES >= ATENDIDOS.
   Transaccion:
     Se usa SET XACT_ABORT ON: a diferencia de sp_CargarDimensiones (que hace
     rollback parcial con SAVEPOINT), aqui se opta por todo-o-nada, porque el
     INSERT hacia Atencion es una sola sentencia atomica y no tiene sentido
     dejarla a medias. Cualquier error revierte automaticamente toda la
     transaccion antes de llegar al CATCH.
   Comportamiento ante excepciones:
     - Las filas rechazadas se registran ANTES de abrir la transaccion, por lo
       que el detalle de validacion persiste aunque la carga posterior falle.
     - Si el INSERT hacia dbo.Atencion falla (por ejemplo, un trigger de
       integridad lo bloquea por periodo cerrado), XACT_ABORT deshace la
       transaccion, el CATCH registra el error en dbo.LogCargaETL con estado
       'ERROR' y relanza la excepcion con THROW.
   ----------------------------------------------------------------------------- */
CREATE PROCEDURE dbo.sp_CargarAtenciones
    @FilasInsertadas INT OUTPUT,
    @FilasRechazadas INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- todo o nada: ante cualquier error se deshace toda la carga
    DECLARE @Inicio DATETIME2(0) = SYSDATETIME();

    SET @FilasInsertadas = 0;
    SET @FilasRechazadas = 0;

    BEGIN TRY
        -- 1) Detectar y registrar filas invalidas (fuera de cualquier transaccion:
        --    queremos conservar este detalle aunque el paso 2 falle y se revierta).
        INSERT INTO dbo.LogErroresValidacion (Proceso, StgId, Campo, ValorOriginal, Motivo)
        SELECT 'sp_CargarAtenciones', s.StgId, 'SEXO', s.SEXO, 'Valor fuera de dominio (F/M)'
        FROM dbo.stg_Atenciones s
        WHERE s.SEXO NOT IN ('F', 'M')
        UNION ALL
        SELECT 'sp_CargarAtenciones', s.StgId, 'EDAD_REG/TIPO_EDAD',
               CONCAT(s.EDAD_REG, '/', s.TIPO_EDAD), 'Edad fuera de rango para el tipo de edad'
        FROM dbo.stg_Atenciones s
        WHERE NOT (
                (s.TIPO_EDAD = 'D' AND s.EDAD_REG BETWEEN 0 AND 364) OR
                (s.TIPO_EDAD = 'M' AND s.EDAD_REG BETWEEN 0 AND 11)  OR
                (s.TIPO_EDAD = 'A' AND s.EDAD_REG BETWEEN -1 AND 99)
              )
        UNION ALL
        SELECT 'sp_CargarAtenciones', s.StgId, 'CODIGO_UNICO',
               CAST(s.CODIGO_UNICO AS VARCHAR(20)), 'El establecimiento no existe en dbo.Establecimiento'
        FROM dbo.stg_Atenciones s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Establecimiento e WHERE e.CodigoUnico = s.CODIGO_UNICO)
        UNION ALL
        SELECT 'sp_CargarAtenciones', s.StgId, 'ATENDIDOS/ATENCIONES',
               CONCAT(s.ATENDIDOS, '/', s.ATENCIONES), 'Valores negativos o atenciones menor que atendidos'
        FROM dbo.stg_Atenciones s
        WHERE s.ATENDIDOS < 0 OR s.ATENCIONES < 0 OR s.ATENCIONES < s.ATENDIDOS;

        SET @FilasRechazadas = @@ROWCOUNT;

        -- 2) Cargar unicamente las filas validas y que todavia no existan en Atencion.
        BEGIN TRANSACTION;

        INSERT INTO dbo.Atencion
               (Fecha, CodigoUnico, UpsId, EtniaId, TipoSeguroId, Sexo, EdadReg, TipoEdad, Atendidos, Atenciones, FechaCorte)
        SELECT DATEFROMPARTS(s.ANIO, s.MES, s.DIA), s.CODIGO_UNICO, u.UpsId, et.EtniaId, ts.TipoSeguroId,
               s.SEXO, s.EDAD_REG, s.TIPO_EDAD, s.ATENDIDOS, s.ATENCIONES, CONVERT(DATE, s.FECHA_CORTE, 112)
        FROM dbo.stg_Atenciones s
        JOIN dbo.Establecimiento e  ON e.CodigoUnico = s.CODIGO_UNICO
        JOIN dbo.Ups u              ON u.Nombre = s.UPS
        JOIN dbo.Etnia et           ON et.Nombre = s.ETNIA
        JOIN dbo.TipoSeguro ts      ON ts.Nombre = s.TIPO_SEGURO
        WHERE s.SEXO IN ('F', 'M')
          AND ( (s.TIPO_EDAD = 'D' AND s.EDAD_REG BETWEEN 0 AND 364) OR
                (s.TIPO_EDAD = 'M' AND s.EDAD_REG BETWEEN 0 AND 11)  OR
                (s.TIPO_EDAD = 'A' AND s.EDAD_REG BETWEEN -1 AND 99) )
          AND s.ATENDIDOS >= 0 AND s.ATENCIONES >= 0 AND s.ATENCIONES >= s.ATENDIDOS
          AND NOT EXISTS (
                SELECT 1 FROM dbo.Atencion a
                WHERE a.CodigoUnico = s.CODIGO_UNICO
                  AND a.Fecha = DATEFROMPARTS(s.ANIO, s.MES, s.DIA)
                  AND a.UpsId = u.UpsId AND a.EtniaId = et.EtniaId AND a.TipoSeguroId = ts.TipoSeguroId
                  AND a.Sexo = s.SEXO AND a.EdadReg = s.EDAD_REG AND a.TipoEdad = s.TIPO_EDAD
              );

        SET @FilasInsertadas = @@ROWCOUNT;

        COMMIT TRANSACTION;

        INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, FilasRechazadas, Estado, MensajeError)
        VALUES ('sp_CargarAtenciones', @Inicio, SYSDATETIME(), @FilasInsertadas, @FilasRechazadas, 'OK', NULL);
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @FilasInsertadas = 0;
        INSERT INTO dbo.LogCargaETL (Proceso, FechaInicio, FechaFin, FilasInsertadas, FilasRechazadas, Estado, MensajeError)
        VALUES ('sp_CargarAtenciones', @Inicio, SYSDATETIME(), 0, @FilasRechazadas, 'ERROR', ERROR_MESSAGE());

        THROW;
    END CATCH
END
GO

/* =============================================================================
   EJECUCION - conecta lo cargado en stg_Atenciones con el modelo real
   Correr esto DESPUES de haber insertado filas en dbo.stg_Atenciones
   (AtencionesSalud_inserts_atenciones_muestra.sql o BULK INSERT).
   ============================================================================= */

DECLARE @EstablecimientosNuevos INT;
EXEC dbo.sp_CargarDimensiones @FilasNuevasEstablecimiento = @EstablecimientosNuevos OUTPUT;
PRINT CONCAT('Establecimientos nuevos: ', @EstablecimientosNuevos);
GO

DECLARE @FilasInsertadas INT, @FilasRechazadas INT;
EXEC dbo.sp_CargarAtenciones @FilasInsertadas = @FilasInsertadas OUTPUT, @FilasRechazadas = @FilasRechazadas OUTPUT;
PRINT CONCAT('Atenciones insertadas: ', @FilasInsertadas, ' | Rechazadas: ', @FilasRechazadas);
GO

-- Verificacion: confirmar que los datos de stg_Atenciones ya quedaron conectados
SELECT (SELECT COUNT(*) FROM dbo.stg_Atenciones) AS FilasEnStaging,
       (SELECT COUNT(*) FROM dbo.Atencion)       AS FilasEnTablaDeHechos,
       (SELECT COUNT(*) FROM dbo.Establecimiento) AS EstablecimientosTotales;

SELECT TOP 10 * FROM dbo.LogCargaETL ORDER BY LogId DESC;
SELECT TOP 10 * FROM dbo.LogErroresValidacion ORDER BY ErrorId DESC;
