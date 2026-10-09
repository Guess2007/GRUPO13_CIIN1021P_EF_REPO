/* =============================================================================
   AtencionesSalud - Script consolidado
   Une, EN ORDEN, los 5 documentos entregados hasta ahora. Ejecutar de arriba
   hacia abajo, lote por lote (separados por GO); no saltar secciones, porque
   cada una depende de que la anterior ya se haya ejecutado (tablas antes de
   procedimientos, procedimientos antes de roles, etc.).

   Contenido:
     1) Tablas base (BD, esquema, staging y carga inicial desde el CSV)
     2) Procedimientos almacenados, triggers y funciones
     3) Roles con privilegios diferenciados (Ley 29733 / ISO 27001)
     4) Politica de respaldo FULL + DIFFERENTIAL y restauracion
     5) Analisis de plan de ejecucion e indice de rendimiento

   Nota: las rutas de archivo (BULK INSERT, BACKUP, RESTORE en las secciones
   1 y 4) son ejemplos; ajustarlas al entorno real antes de ejecutar.
   ============================================================================= */



GO

/* #############################################################################
   SECCION 1) TABLAS BASE
   Fuente original: AtencionesSalud_sqlserver.sql
   ############################################################################# */
GO

/* =====================================================================
   Base de datos: AtencionesSalud
   Origen       : Atenciones_atendidos_2023-dires.csv  (separador ';', UTF-8 con BOM)
   Motor        : SQL Server 2017 o superior
   Contenido    : 1) Tablas del modelo   2) Tabla de staging   3) Carga desde el CSV
   ===================================================================== */

IF DB_ID(N'AtencionesSalud') IS NULL
    CREATE DATABASE AtencionesSalud;
GO
USE AtencionesSalud;
GO

/* =====================================================================
   1) TABLAS DEL MODELO
   ===================================================================== */

-- ---------- Dimensiones geograficas / organizativas ----------

CREATE TABLE dbo.Red (
    RedId   SMALLINT     IDENTITY(1,1) NOT NULL,
    Nombre  NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Red        PRIMARY KEY (RedId),
    CONSTRAINT UQ_Red_Nombre UNIQUE (Nombre)
);

-- "NO PERTENECE A NINGUNA MICRORED" aparece en varias redes, por eso la microred depende de la red.
CREATE TABLE dbo.Microred (
    MicroredId INT           IDENTITY(1,1) NOT NULL,
    RedId      SMALLINT      NOT NULL,
    Nombre     NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Microred        PRIMARY KEY (MicroredId),
    CONSTRAINT UQ_Microred        UNIQUE (RedId, Nombre),
    CONSTRAINT FK_Microred_Red    FOREIGN KEY (RedId) REFERENCES dbo.Red (RedId)
);

CREATE TABLE dbo.Provincia (
    ProvinciaId SMALLINT     IDENTITY(1,1) NOT NULL,
    Nombre      NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Provincia        PRIMARY KEY (ProvinciaId),
    CONSTRAINT UQ_Provincia_Nombre UNIQUE (Nombre)
);

CREATE TABLE dbo.Distrito (
    DistritoId  INT          IDENTITY(1,1) NOT NULL,
    ProvinciaId SMALLINT     NOT NULL,
    Nombre      NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Distrito           PRIMARY KEY (DistritoId),
    CONSTRAINT UQ_Distrito           UNIQUE (ProvinciaId, Nombre),
    CONSTRAINT FK_Distrito_Provincia FOREIGN KEY (ProvinciaId) REFERENCES dbo.Provincia (ProvinciaId)
);

-- Categorias: I-1, I-2, I-3, I-4, II-1, II-2, II-E y '0' (sin categoria asignada)
CREATE TABLE dbo.CategoriaEstablecimiento (
    CategoriaId TINYINT     IDENTITY(1,1) NOT NULL,
    Codigo      VARCHAR(5)  NOT NULL,
    CONSTRAINT PK_CategoriaEstablecimiento        PRIMARY KEY (CategoriaId),
    CONSTRAINT UQ_CategoriaEstablecimiento_Codigo UNIQUE (Codigo)
);

-- CODIGO_UNICO es la clave natural; los nombres de establecimiento se repiten (18 casos), el codigo no.
CREATE TABLE dbo.Establecimiento (
    CodigoUnico   INT           NOT NULL,
    Nombre        NVARCHAR(100) NOT NULL,
    CategoriaId   TINYINT       NOT NULL,
    MicroredId    INT           NOT NULL,
    DistritoId    INT           NOT NULL,
    CONSTRAINT PK_Establecimiento           PRIMARY KEY (CodigoUnico),
    CONSTRAINT FK_Establecimiento_Categoria FOREIGN KEY (CategoriaId) REFERENCES dbo.CategoriaEstablecimiento (CategoriaId),
    CONSTRAINT FK_Establecimiento_Microred  FOREIGN KEY (MicroredId)  REFERENCES dbo.Microred (MicroredId),
    CONSTRAINT FK_Establecimiento_Distrito  FOREIGN KEY (DistritoId)  REFERENCES dbo.Distrito (DistritoId)
);

-- ---------- Catalogos ----------

CREATE TABLE dbo.TipoEdad (
    TipoEdad    CHAR(1)     NOT NULL,   -- A, M, D
    Descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_TipoEdad PRIMARY KEY (TipoEdad)
);

INSERT dbo.TipoEdad (TipoEdad, Descripcion) VALUES ('A', 'Años'), ('M', 'Meses'), ('D', 'Días');

CREATE TABLE dbo.Etnia (
    EtniaId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre  NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Etnia        PRIMARY KEY (EtniaId),
    CONSTRAINT UQ_Etnia_Nombre UNIQUE (Nombre)
);

CREATE TABLE dbo.TipoSeguro (
    TipoSeguroId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre       NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_TipoSeguro        PRIMARY KEY (TipoSeguroId),
    CONSTRAINT UQ_TipoSeguro_Nombre UNIQUE (Nombre)
);

-- UPS = Unidad Productora de Servicios (93 valores distintos en el archivo)
CREATE TABLE dbo.Ups (
    UpsId  SMALLINT      IDENTITY(1,1) NOT NULL,
    Nombre NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_Ups        PRIMARY KEY (UpsId),
    CONSTRAINT UQ_Ups_Nombre UNIQUE (Nombre)
);

-- ---------- Tabla de hechos ----------
-- Grano: una fila del CSV = combinacion de dia + establecimiento + UPS + sexo + edad + etnia + seguro.

CREATE TABLE dbo.Atencion (
    AtencionId   BIGINT   IDENTITY(1,1) NOT NULL,
    Fecha        DATE     NOT NULL,                 -- ANIO + MES + DIA
    CodigoUnico  INT      NOT NULL,
    UpsId        SMALLINT NOT NULL,
    EtniaId      TINYINT  NOT NULL,
    TipoSeguroId TINYINT  NOT NULL,
    Sexo         CHAR(1)  NOT NULL,
    EdadReg      SMALLINT NOT NULL,                 -- -1 = edad no registrada
    TipoEdad     CHAR(1)  NOT NULL,                 -- A = años, M = meses, D = días
    Atendidos    SMALLINT NOT NULL,                 -- personas atendidas
    Atenciones   SMALLINT NOT NULL,                 -- numero de atenciones
    FechaCorte   DATE     NOT NULL,                 -- fecha de corte de la extraccion
    Anio AS YEAR(Fecha)  PERSISTED,
    Mes  AS MONTH(Fecha) PERSISTED,
    CONSTRAINT PK_Atencion               PRIMARY KEY CLUSTERED (AtencionId),
    CONSTRAINT FK_Atencion_Establecim    FOREIGN KEY (CodigoUnico)  REFERENCES dbo.Establecimiento (CodigoUnico),
    CONSTRAINT FK_Atencion_Ups           FOREIGN KEY (UpsId)        REFERENCES dbo.Ups (UpsId),
    CONSTRAINT FK_Atencion_Etnia         FOREIGN KEY (EtniaId)      REFERENCES dbo.Etnia (EtniaId),
    CONSTRAINT FK_Atencion_TipoSeguro    FOREIGN KEY (TipoSeguroId) REFERENCES dbo.TipoSeguro (TipoSeguroId),
    CONSTRAINT FK_Atencion_TipoEdad      FOREIGN KEY (TipoEdad)     REFERENCES dbo.TipoEdad (TipoEdad),
    CONSTRAINT CK_Atencion_Sexo          CHECK (Sexo IN ('F', 'M')),
    CONSTRAINT CK_Atencion_EdadReg       CHECK (EdadReg >= -1),
    CONSTRAINT CK_Atencion_Atendidos     CHECK (Atendidos >= 0),
    CONSTRAINT CK_Atencion_Atenciones    CHECK (Atenciones >= 0)
);

CREATE NONCLUSTERED INDEX IX_Atencion_Fecha
    ON dbo.Atencion (Fecha) INCLUDE (Atendidos, Atenciones);
CREATE NONCLUSTERED INDEX IX_Atencion_Establecimiento
    ON dbo.Atencion (CodigoUnico, Fecha);
CREATE NONCLUSTERED INDEX IX_Atencion_Ups
    ON dbo.Atencion (UpsId);
GO

/* =====================================================================
   2) TABLA DE STAGING (mismas columnas y orden que el CSV)
   ===================================================================== */

CREATE TABLE dbo.stg_Atenciones (
    ANIO                   SMALLINT,
    MES                    TINYINT,
    DIA                    TINYINT,
    CATEGORIA              VARCHAR(10),
    RED                    NVARCHAR(100),
    MICRORED               NVARCHAR(150),
    CODIGO_UNICO           INT,
    NOMBRE_ESTACLECIMIENTO NVARCHAR(150),
    PROVINCIA              NVARCHAR(50),
    DISTRITO               NVARCHAR(50),
    EDAD_REG               SMALLINT,
    TIPO_EDAD              VARCHAR(10),
    SEXO                   VARCHAR(10),
    ETNIA                  NVARCHAR(50),
    TIPO_SEGURO            VARCHAR(20),
    UPS                    NVARCHAR(150),
    ATENDIDOS              SMALLINT,
    ATENCIONES             SMALLINT,
    FECHA_CORTE            CHAR(8)
);
GO

/* =====================================================================
   3) CARGA DESDE EL CSV
   ===================================================================== */

-- 3.1 Cargar el CSV en staging (cambia la ruta; debe ser accesible desde el servidor SQL)
BULK INSERT dbo.stg_Atenciones
FROM 'C:\datos\Atenciones_atendidos_2023-dires.csv'
WITH (
    FORMAT          = 'CSV',
    FIELDTERMINATOR = ';',
    FIRSTROW        = 2,
    CODEPAGE        = '65001',
    TABLOCK
);
GO

-- 3.2 Limpieza: quitar espacios de relleno y comillas sobrantes (p. ej. "SAN PABLO-CONSUELO   ")
--     y corregir caracteres mal codificados en el origen (+ì -> Í, +æ -> Ñ, +ë -> É, +ô -> Ó, +ü -> Á)
UPDATE dbo.stg_Atenciones
SET CATEGORIA = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(CATEGORIA)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    RED = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(RED)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    MICRORED = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(MICRORED)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    NOMBRE_ESTACLECIMIENTO = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(NOMBRE_ESTACLECIMIENTO)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    PROVINCIA = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(PROVINCIA)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    DISTRITO = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(DISTRITO)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    TIPO_EDAD = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(TIPO_EDAD)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    SEXO = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(SEXO)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    ETNIA = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ETNIA)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    TIPO_SEGURO = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(TIPO_SEGURO)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á'),
    UPS = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(UPS)), N'"', N''), N'+ì', N'Í'), N'+æ', N'Ñ'), N'+ë', N'É'), N'+ô', N'Ó'), N'+ü', N'Á');
GO

-- 3.3 Poblar dimensiones
INSERT dbo.Red (Nombre)
SELECT DISTINCT RED FROM dbo.stg_Atenciones;

INSERT dbo.Microred (RedId, Nombre)
SELECT DISTINCT r.RedId, s.MICRORED
FROM dbo.stg_Atenciones s
JOIN dbo.Red r ON r.Nombre = s.RED;

INSERT dbo.Provincia (Nombre)
SELECT DISTINCT PROVINCIA FROM dbo.stg_Atenciones;

INSERT dbo.Distrito (ProvinciaId, Nombre)
SELECT DISTINCT p.ProvinciaId, s.DISTRITO
FROM dbo.stg_Atenciones s
JOIN dbo.Provincia p ON p.Nombre = s.PROVINCIA;

INSERT dbo.CategoriaEstablecimiento (Codigo)
SELECT DISTINCT CATEGORIA FROM dbo.stg_Atenciones;

INSERT dbo.Etnia (Nombre)
SELECT DISTINCT ETNIA FROM dbo.stg_Atenciones;

INSERT dbo.TipoSeguro (Nombre)
SELECT DISTINCT TIPO_SEGURO FROM dbo.stg_Atenciones;

INSERT dbo.Ups (Nombre)
SELECT DISTINCT UPS FROM dbo.stg_Atenciones;

INSERT dbo.Establecimiento (CodigoUnico, Nombre, CategoriaId, MicroredId, DistritoId)
SELECT DISTINCT
       s.CODIGO_UNICO, s.NOMBRE_ESTACLECIMIENTO, c.CategoriaId, m.MicroredId, d.DistritoId
FROM dbo.stg_Atenciones s
JOIN dbo.CategoriaEstablecimiento c ON c.Codigo = s.CATEGORIA
JOIN dbo.Red r        ON r.Nombre = s.RED
JOIN dbo.Microred m   ON m.RedId = r.RedId AND m.Nombre = s.MICRORED
JOIN dbo.Provincia p  ON p.Nombre = s.PROVINCIA
JOIN dbo.Distrito d   ON d.ProvinciaId = p.ProvinciaId AND d.Nombre = s.DISTRITO;
GO

-- 3.4 Poblar la tabla de hechos
INSERT dbo.Atencion
       (Fecha, CodigoUnico, UpsId, EtniaId, TipoSeguroId, Sexo, EdadReg, TipoEdad, Atendidos, Atenciones, FechaCorte)
SELECT DATEFROMPARTS(s.ANIO, s.MES, s.DIA),
       s.CODIGO_UNICO, u.UpsId, e.EtniaId, t.TipoSeguroId,
       s.SEXO, s.EDAD_REG, s.TIPO_EDAD, s.ATENDIDOS, s.ATENCIONES,
       CONVERT(DATE, s.FECHA_CORTE, 112)
FROM dbo.stg_Atenciones s
JOIN dbo.Ups u          ON u.Nombre = s.UPS
JOIN dbo.Etnia e        ON e.Nombre = s.ETNIA
JOIN dbo.TipoSeguro t   ON t.Nombre = s.TIPO_SEGURO;
GO

-- 3.5 Verificacion: ambos conteos deben coincidir; luego se puede borrar el staging
SELECT (SELECT COUNT(*) FROM dbo.stg_Atenciones) AS FilasStaging,
       (SELECT COUNT(*) FROM dbo.Atencion)       AS FilasAtencion;
-- DROP TABLE dbo.stg_Atenciones;

GO

/* #############################################################################
   SECCION 2) PROCEDIMIENTOS, TRIGGERS Y FUNCIONES
   Fuente original: AtencionesSalud_procedimientos_triggers_funciones.sql
   ############################################################################# */
GO

/* =============================================================================
   AtencionesSalud - Automatizacion de carga, auditoria e integridad
   Este script EXTIENDE a AtencionesSalud_sqlserver.sql (ejecutarlo primero).
   Contiene:
     A) 2 procedimientos almacenados de ingesta/validacion (TRY/CATCH, transacciones, SAVEPOINT)
     B) 2 triggers (auditoria DML e integridad de negocio)
     C) 2 funciones reutilizables (escalar y de tabla en linea)
   ============================================================================= */

USE AtencionesSalud;
GO

/* =============================================================================
   0) TABLAS DE SOPORTE (logs y control de periodos)
   ============================================================================= */

-- Identificador propio en staging, para poder trazar cada fila rechazada hasta su origen.
ALTER TABLE dbo.stg_Atenciones
    ADD StgId INT IDENTITY(1,1) NOT NULL;
GO

-- Log de ejecucion de los procesos de carga (uno por corrida de cada procedimiento).
CREATE TABLE dbo.LogCargaETL (
    LogId            BIGINT        IDENTITY(1,1) NOT NULL,
    Proceso          VARCHAR(100)  NOT NULL,
    FechaInicio      DATETIME2(0)  NOT NULL,
    FechaFin         DATETIME2(0)  NULL,
    FilasLeidas      INT           NULL,
    FilasInsertadas  INT           NULL,
    FilasRechazadas  INT           NULL,
    Estado           VARCHAR(20)   NOT NULL,   -- 'OK','ERROR','ERROR_PARCIAL'
    MensajeError     NVARCHAR(4000) NULL,
    UsuarioEjecucion SYSNAME       NOT NULL CONSTRAINT DF_LogCargaETL_Usuario DEFAULT (SUSER_SNAME()),
    CONSTRAINT PK_LogCargaETL PRIMARY KEY (LogId)
);

-- Detalle de filas de staging que no pasaron la validacion de negocio.
CREATE TABLE dbo.LogErroresValidacion (
    ErrorId       BIGINT        IDENTITY(1,1) NOT NULL,
    Proceso       VARCHAR(100)  NOT NULL,
    StgId         INT           NOT NULL,
    Campo         VARCHAR(50)   NOT NULL,
    ValorOriginal NVARCHAR(200) NULL,
    Motivo        NVARCHAR(200) NOT NULL,
    FechaRegistro DATETIME2(0)  NOT NULL CONSTRAINT DF_LogErroresValidacion_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_LogErroresValidacion PRIMARY KEY (ErrorId)
);

-- Periodos (Anio/Mes) cerrados para edicion; el trigger de integridad la consulta.
CREATE TABLE dbo.PeriodoCerrado (
    Anio        SMALLINT NOT NULL,
    Mes         TINYINT  NOT NULL,
    FechaCierre DATE     NOT NULL CONSTRAINT DF_PeriodoCerrado_Fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_PeriodoCerrado PRIMARY KEY (Anio, Mes)
);

-- Auditoria de cambios sobre la tabla de hechos.
CREATE TABLE dbo.LogAuditoriaAtencion (
    AuditId             BIGINT       IDENTITY(1,1) NOT NULL,
    Operacion           CHAR(1)      NOT NULL,     -- I = insert, U = update, D = delete
    AtencionId          BIGINT       NOT NULL,
    CodigoUnico         INT          NOT NULL,
    Fecha               DATE         NOT NULL,
    Atendidos_Anterior  SMALLINT     NULL,
    Atendidos_Nuevo     SMALLINT     NULL,
    Atenciones_Anterior SMALLINT     NULL,
    Atenciones_Nuevo    SMALLINT     NULL,
    UsuarioBD           SYSNAME      NOT NULL,
    FechaHora           DATETIME2(0) NOT NULL CONSTRAINT DF_LogAuditoriaAtencion_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_LogAuditoriaAtencion PRIMARY KEY (AuditId)
);
GO

/* =============================================================================
   A) PROCEDIMIENTOS ALMACENADOS
   ============================================================================= */

/* -----------------------------------------------------------------------------
   dbo.sp_CargarDimensiones
   Proposito:
     Poblar las tablas de dimension (Red, Microred, Provincia, Distrito,
     CategoriaEstablecimiento, Etnia, TipoSeguro, Ups, Establecimiento) a partir
     de dbo.stg_Atenciones. Es idempotente: solo inserta lo que no existe todavia,
     por lo que puede ejecutarse varias veces sin duplicar filas.
   Parametros:
     @FilasNuevasEstablecimiento OUTPUT INT - cantidad de establecimientos nuevos
                                               insertados en esta ejecucion.
   Transaccion:
     Una transaccion explicita cubre las 7 dimensiones simples. Antes de insertar
     Establecimiento (el paso que depende de las otras 6 tablas a la vez y es el
     mas propenso a fallar por datos huerfanos) se marca un punto de control con
     SAVE TRANSACTION. Si ese paso falla, se hace ROLLBACK TRANSACTION solo hasta
     ese punto: se conservan las dimensiones simples ya cargadas y se continua
     hasta el COMMIT final, en vez de perder toda la carga por un solo problema.
   Comportamiento ante excepciones:
     - Error solo en el bloque de Establecimiento: se revierte unicamente ese
       INSERT (ROLLBACK TRANSACTION al savepoint), se registra 'ERROR_PARCIAL'
       en dbo.LogCargaETL con el mensaje de error, y el procedimiento continua
       y hace COMMIT del resto.
     - Error en cualquier otro punto (p. ej. perdida de conexion, violacion no
       prevista): el CATCH externo revierte toda la transaccion todavia abierta
       (XACT_STATE() <> 0), registra 'ERROR' en dbo.LogCargaETL y relanza el
       error original con THROW para que quien invoque el procedimiento se
       entere de la falla.
   ----------------------------------------------------------------------------- */
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
   B) TRIGGERS
   ============================================================================= */

/* -----------------------------------------------------------------------------
   dbo.trg_Atencion_Auditoria  (trigger DML de auditoria)
   Proposito:
     Dejar rastro de todo INSERT, UPDATE y DELETE sobre dbo.Atencion en
     dbo.LogAuditoriaAtencion, guardando el valor anterior y nuevo de las
     medidas (Atendidos, Atenciones) y quien hizo el cambio.
   Parametros:
     No aplica (los triggers no reciben parametros; usan las tablas logicas
     "inserted" y "deleted" que arma SQL Server con las filas afectadas).
   Comportamiento ante excepciones:
     No lleva TRY/CATCH propio a proposito: si el INSERT en LogAuditoriaAtencion
     fallara (por ejemplo, la tabla de log no existe o esta sin espacio), el
     error debe abortar tambien la operacion original sobre Atencion, para que
     nunca quede un cambio sin auditar. Esa propagacion automatica del error es
     el comportamiento por defecto de un trigger AFTER en SQL Server.
   ----------------------------------------------------------------------------- */
CREATE TRIGGER dbo.trg_Atencion_Auditoria
ON dbo.Atencion
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.LogAuditoriaAtencion
           (Operacion, AtencionId, CodigoUnico, Fecha, Atendidos_Anterior, Atendidos_Nuevo,
            Atenciones_Anterior, Atenciones_Nuevo, UsuarioBD)
    SELECT 'I', i.AtencionId, i.CodigoUnico, i.Fecha, NULL, i.Atendidos, NULL, i.Atenciones, SUSER_SNAME()
    FROM inserted i
    LEFT JOIN deleted d ON d.AtencionId = i.AtencionId
    WHERE d.AtencionId IS NULL

    UNION ALL

    SELECT 'U', i.AtencionId, i.CodigoUnico, i.Fecha, d.Atendidos, i.Atendidos, d.Atenciones, i.Atenciones, SUSER_SNAME()
    FROM inserted i
    JOIN deleted d ON d.AtencionId = i.AtencionId

    UNION ALL

    SELECT 'D', d.AtencionId, d.CodigoUnico, d.Fecha, d.Atendidos, NULL, d.Atenciones, NULL, SUSER_SNAME()
    FROM deleted d
    LEFT JOIN inserted i ON i.AtencionId = d.AtencionId
    WHERE i.AtencionId IS NULL;
END
GO

/* -----------------------------------------------------------------------------
   dbo.trg_Atencion_ValidarPeriodoCerrado  (trigger de integridad)
   Proposito:
     Impedir INSERT, UPDATE o DELETE sobre dbo.Atencion cuando la fecha del
     registro cae en un periodo (Anio/Mes) marcado como cerrado en
     dbo.PeriodoCerrado. Esta regla depende de OTRA tabla, por lo que no se
     puede expresar con un CHECK constraint (que solo ve columnas de la misma
     fila) ni con una FOREIGN KEY; un trigger es la unica forma declarativa de
     aplicarla automaticamente sin depender de que cada aplicacion la respete.
   Parametros:
     No aplica (usa "inserted" y "deleted", igual que el trigger anterior).
   Comportamiento ante excepciones:
     Si encuentra alguna fila de "inserted" o "deleted" cuyo Anio/Mes esta en
     dbo.PeriodoCerrado, lanza RAISERROR con severidad 16 (error de usuario,
     no fatal) y hace ROLLBACK TRANSACTION, deshaciendo toda la sentencia que
     disparo el trigger (incluso si insertaba o modificaba varias filas a la
     vez). El error se propaga a quien ejecuto la sentencia original (por
     ejemplo, sp_CargarAtenciones lo capturaria en su bloque CATCH).
   ----------------------------------------------------------------------------- */
CREATE TRIGGER dbo.trg_Atencion_ValidarPeriodoCerrado
ON dbo.Atencion
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.PeriodoCerrado pc ON pc.Anio = YEAR(i.Fecha) AND pc.Mes = MONTH(i.Fecha)
        UNION ALL
        SELECT 1
        FROM deleted d
        JOIN dbo.PeriodoCerrado pc ON pc.Anio = YEAR(d.Fecha) AND pc.Mes = MONTH(d.Fecha)
    )
    BEGIN
        RAISERROR ('Operacion no permitida: el periodo (Anio/Mes) de esa fecha esta cerrado.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END
GO

/* =============================================================================
   C) FUNCIONES REUTILIZABLES
   ============================================================================= */

/* -----------------------------------------------------------------------------
   dbo.fn_GrupoEtario  (funcion escalar)
   Proposito:
     Traducir EDAD_REG + TIPO_EDAD (dias/meses/años, tal como vienen en el CSV)
     a un grupo etario legible para reportes, sin repetir esta logica en cada
     consulta o en cada aplicacion que use la base de datos.
   Parametros:
     @EdadReg  SMALLINT - edad registrada (-1 = no registrada).
     @TipoEdad CHAR(1)  - 'D' dias, 'M' meses, 'A' años.
   Valor de retorno:
     VARCHAR(20) con el grupo etario ('Menor de 1 año', '1 a 11 años', ...,
     '60 a mas años' o 'No registrada').
   Comportamiento ante excepciones:
     Es una funcion determinista de solo calculo (sin acceso a tablas), por lo
     que no hay operaciones que puedan fallar en tiempo de ejecucion; ante un
     valor de @TipoEdad fuera de 'D'/'M'/'A' cae en la rama ELSE final y se
     clasifica igualmente en un grupo por edad, en vez de producir un error.
   ----------------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_GrupoEtario
(
    @EdadReg  SMALLINT,
    @TipoEdad CHAR(1)
)
RETURNS VARCHAR(20)
AS
BEGIN
    DECLARE @Grupo VARCHAR(20);

    IF @TipoEdad IN ('D', 'M')
        SET @Grupo = 'Menor de 1 año';
    ELSE IF @EdadReg = -1
        SET @Grupo = 'No registrada';
    ELSE IF @EdadReg BETWEEN 1 AND 11
        SET @Grupo = '1 a 11 años';
    ELSE IF @EdadReg BETWEEN 12 AND 17
        SET @Grupo = '12 a 17 años';
    ELSE IF @EdadReg BETWEEN 18 AND 29
        SET @Grupo = '18 a 29 años';
    ELSE IF @EdadReg BETWEEN 30 AND 59
        SET @Grupo = '30 a 59 años';
    ELSE
        SET @Grupo = '60 a mas años';

    RETURN @Grupo;
END
GO

/* -----------------------------------------------------------------------------
   dbo.fn_ResumenAtencionesPorEstablecimiento  (funcion de tabla en linea)
   Proposito:
     Devolver, para un rango de fechas, el total de atendidos y atenciones por
     establecimiento (con su red). Al ser una funcion de tabla se puede usar
     dentro de un FROM/JOIN como si fuera una vista parametrizada, reutilizable
     desde reportes, otras consultas o procedimientos.
   Parametros:
     @FechaIni DATE - inicio del rango (inclusive).
     @FechaFin DATE - fin del rango (inclusive).
   Valor de retorno:
     TABLE con columnas: CodigoUnico, Establecimiento, Red, RegistrosAtencion,
     TotalAtendidos, TotalAtenciones.
   Comportamiento ante excepciones:
     Al ser una funcion de tabla en linea (un unico RETURN con un SELECT), SQL
     Server no permite bloques TRY/CATCH dentro de ella. Si @FechaIni es
     posterior a @FechaFin simplemente no hay filas que cumplan el BETWEEN
     implicito y se devuelve un conjunto vacio, sin error; si se necesita
     validar los parametros de entrada con un mensaje de error, esa validacion
     debe hacerse antes de invocarla (por ejemplo, en el procedimiento que la
     use) o migrando esta logica a una funcion de tabla multi-sentencia.
   ----------------------------------------------------------------------------- */
CREATE FUNCTION dbo.fn_ResumenAtencionesPorEstablecimiento
(
    @FechaIni DATE,
    @FechaFin DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT e.CodigoUnico,
           e.Nombre AS Establecimiento,
           r.Nombre AS Red,
           COUNT(*)          AS RegistrosAtencion,
           SUM(a.Atendidos)  AS TotalAtendidos,
           SUM(a.Atenciones) AS TotalAtenciones
    FROM dbo.Atencion a
    JOIN dbo.Establecimiento e ON e.CodigoUnico = a.CodigoUnico
    JOIN dbo.Microred m        ON m.MicroredId = e.MicroredId
    JOIN dbo.Red r             ON r.RedId = m.RedId
    WHERE a.Fecha BETWEEN @FechaIni AND @FechaFin
    GROUP BY e.CodigoUnico, e.Nombre, r.Nombre
);
GO

/* =============================================================================
   EJEMPLOS DE USO (comentados; descomentar para probar)
   ============================================================================= */

-- DECLARE @nuevos INT;
-- EXEC dbo.sp_CargarDimensiones @FilasNuevasEstablecimiento = @nuevos OUTPUT;
-- SELECT @nuevos AS EstablecimientosNuevos;

-- DECLARE @ins INT, @rech INT;
-- EXEC dbo.sp_CargarAtenciones @FilasInsertadas = @ins OUTPUT, @FilasRechazadas = @rech OUTPUT;
-- SELECT @ins AS Insertadas, @rech AS Rechazadas;

-- SELECT TOP 20 * FROM dbo.LogCargaETL ORDER BY LogId DESC;
-- SELECT TOP 20 * FROM dbo.LogErroresValidacion ORDER BY ErrorId DESC;

-- SELECT dbo.fn_GrupoEtario(5, 'A') AS Grupo;
-- SELECT * FROM dbo.fn_ResumenAtencionesPorEstablecimiento('2023-01-01','2023-03-31');

-- INSERT INTO dbo.PeriodoCerrado (Anio, Mes) VALUES (2023, 1);
-- UPDATE dbo.Atencion SET Atenciones = Atenciones + 1 WHERE Fecha = '2023-01-01'; -- debe fallar

GO

/* #############################################################################
   SECCION 3) ROLES CON PRIVILEGIOS DIFERENCIADOS
   Fuente original: AtencionesSalud_roles.sql
   ############################################################################# */
GO

/* =============================================================================
   AtencionesSalud - Roles de base de datos con privilegios diferenciados
   Alineados a la Ley N.° 29733 (Ley de Proteccion de Datos Personales, Peru),
   articulo 11 (medidas de seguridad) y a ISO/IEC 27001:2022, Anexo A
   (A.5.15 control de acceso, A.5.18 derechos de acceso, A.8.3 restriccion del
   acceso a la informacion, A.8.15 registro/logging, A.8.16 monitoreo).
   Ejecutar despues de los scripts de tablas, procedimientos y triggers.
   ============================================================================= */

USE AtencionesSalud;
GO

/* -----------------------------------------------------------------------------
   1) LOGINS Y USUARIOS DE EJEMPLO
   En un despliegue real, cada persona tiene su propio login (no se comparten
   credenciales): eso es lo que permite que la auditoria (SUSER_SNAME() en
   dbo.LogAuditoriaAtencion) identifique a una persona concreta, tal como exige
   la trazabilidad del articulo 11 de la Ley 29733.
   ----------------------------------------------------------------------------- */
CREATE LOGIN dba_solari      WITH PASSWORD = 'Cambiar#DBA_2026!',      CHECK_POLICY = ON;
CREATE LOGIN analista_rojas  WITH PASSWORD = 'Cambiar#Analista_2026!', CHECK_POLICY = ON;
CREATE LOGIN auditor_vega    WITH PASSWORD = 'Cambiar#Auditor_2026!',  CHECK_POLICY = ON;
GO

CREATE USER dba_solari      FOR LOGIN dba_solari;
CREATE USER analista_rojas  FOR LOGIN analista_rojas;
CREATE USER auditor_vega    FOR LOGIN auditor_vega;
GO

/* -----------------------------------------------------------------------------
   2) ROL: rol_administrador_bd
   Alcance: administra estructura, indices, procedimientos, respaldo y
   restauracion. Es el unico rol que puede ejecutar los procedimientos de
   carga y crear/modificar objetos.
   Norma:
     - ISO 27001 A.8.2 ("privileged access rights"): el acceso administrativo
       se otorga a un rol nominal, no a una cuenta compartida ni a "sa".
     - Ley 29733 Art. 11 lit. a/b: medidas tecnicas de control de acceso e
       integridad. Por eso, aunque el rol tiene control sobre la estructura,
       se le DENIEGA explicitamente poder borrar o alterar los registros de
       auditoria: ni siquiera un administrador debe poder cubrir sus huellas.
       Esta denegacion se respeta aunque el rol se agregue a db_owner, porque
       en SQL Server un DENY explicito prevalece sobre cualquier GRANT salvo
       para el usuario "dbo" o miembros de sysadmin (por eso el DBA debe
       operar con un login propio, nunca como "sa" ni como "dbo").
   ----------------------------------------------------------------------------- */
CREATE ROLE rol_administrador_bd;
GO

GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION TO rol_administrador_bd;
GRANT ALTER ON SCHEMA::dbo TO rol_administrador_bd;
GRANT EXECUTE ON SCHEMA::dbo TO rol_administrador_bd;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rol_administrador_bd;
GRANT BACKUP DATABASE, BACKUP LOG TO rol_administrador_bd;
GRANT VIEW DEFINITION ON SCHEMA::dbo TO rol_administrador_bd;

-- Los registros de auditoria y de carga son de solo lectura para todos, admin incluido.
DENY UPDATE, DELETE, ALTER ON dbo.LogAuditoriaAtencion    TO rol_administrador_bd;
DENY UPDATE, DELETE, ALTER ON dbo.LogCargaETL             TO rol_administrador_bd;
DENY UPDATE, DELETE, ALTER ON dbo.LogErroresValidacion    TO rol_administrador_bd;

ALTER ROLE rol_administrador_bd ADD MEMBER dba_solari;
GO

/* -----------------------------------------------------------------------------
   3) ROL: rol_analista_datos
   Alcance: solo lectura, exclusivamente sobre los datos ya validados (la
   tabla de hechos, dimensiones y funciones de reporte). No accede a la tabla
   de staging (datos crudos, sin validar) ni a los registros de auditoria.
   Norma:
     - Ley 29733 Art. 11 lit. b (principio de minimizacion / necesidad de
       conocer): el analista solo ve lo necesario para su labor de reporte,
       no el detalle de quien cargo que ni los errores de calidad de datos.
     - ISO 27001 A.8.3 ("restriccion del acceso a la informacion"): acceso de
       solo lectura, sin permisos de escritura en ningun objeto.
   ----------------------------------------------------------------------------- */
CREATE ROLE rol_analista_datos;
GO

GRANT SELECT ON dbo.Atencion                 TO rol_analista_datos;
GRANT SELECT ON dbo.Establecimiento          TO rol_analista_datos;
GRANT SELECT ON dbo.Red                      TO rol_analista_datos;
GRANT SELECT ON dbo.Microred                 TO rol_analista_datos;
GRANT SELECT ON dbo.Provincia                TO rol_analista_datos;
GRANT SELECT ON dbo.Distrito                 TO rol_analista_datos;
GRANT SELECT ON dbo.CategoriaEstablecimiento TO rol_analista_datos;
GRANT SELECT ON dbo.Etnia                    TO rol_analista_datos;
GRANT SELECT ON dbo.TipoSeguro               TO rol_analista_datos;
GRANT SELECT ON dbo.Ups                      TO rol_analista_datos;
GRANT SELECT ON dbo.TipoEdad                 TO rol_analista_datos;
GRANT SELECT ON OBJECT::dbo.fn_ResumenAtencionesPorEstablecimiento TO rol_analista_datos;
GRANT EXECUTE ON OBJECT::dbo.fn_GrupoEtario  TO rol_analista_datos;

-- Explicitamente sin acceso a datos crudos ni a registros de auditoria/carga.
DENY SELECT ON dbo.stg_Atenciones          TO rol_analista_datos;
DENY SELECT ON dbo.LogAuditoriaAtencion    TO rol_analista_datos;
DENY SELECT ON dbo.LogCargaETL             TO rol_analista_datos;
DENY SELECT ON dbo.LogErroresValidacion    TO rol_analista_datos;
DENY SELECT ON dbo.PeriodoCerrado          TO rol_analista_datos;
DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rol_analista_datos;

ALTER ROLE rol_analista_datos ADD MEMBER analista_rojas;
GO

/* -----------------------------------------------------------------------------
   4) ROL: rol_auditor
   Alcance: solo lectura sobre los registros de auditoria, de carga y sobre
   los metadatos de seguridad (quien tiene que permisos), para poder verificar
   el cumplimiento sin poder modificar nada, ni siquiera los datos operativos.
   Norma:
     - ISO 27001 A.5.3 ("segregation of duties"): quien audita no administra
       ni opera; sus permisos son deliberadamente distintos de los otros dos
       roles y no se solapan con capacidad de escritura en ningun objeto.
     - Ley 29733 Art. 11: sustenta la funcion de supervision/control interno
       que la norma exige para verificar que las medidas de seguridad se
       apliquen en la practica (trazabilidad y rendicion de cuentas).
   ----------------------------------------------------------------------------- */
CREATE ROLE rol_auditor;
GO

GRANT SELECT ON dbo.LogAuditoriaAtencion   TO rol_auditor;
GRANT SELECT ON dbo.LogCargaETL            TO rol_auditor;
GRANT SELECT ON dbo.LogErroresValidacion   TO rol_auditor;
GRANT SELECT ON dbo.PeriodoCerrado         TO rol_auditor;
GRANT SELECT ON dbo.Atencion               TO rol_auditor;   -- para poder contrastar auditoria vs. datos
GRANT VIEW DEFINITION ON SCHEMA::dbo       TO rol_auditor;   -- ver definicion de objetos, no su ejecucion
GRANT VIEW DATABASE STATE                  TO rol_auditor;   -- consultar DMV de seguridad y actividad

-- El auditor jamas escribe nada.
DENY INSERT, UPDATE, DELETE, EXECUTE, ALTER ON SCHEMA::dbo TO rol_auditor;

ALTER ROLE rol_auditor ADD MEMBER auditor_vega;
GO

/* -----------------------------------------------------------------------------
   5) VERIFICACION (para el informe de cumplimiento)
   ----------------------------------------------------------------------------- */
SELECT dp.name AS rol, mp.name AS miembro
FROM sys.database_role_members drm
JOIN sys.database_principals dp ON dp.principal_id = drm.role_principal_id
JOIN sys.database_principals mp ON mp.principal_id = drm.member_principal_id
WHERE dp.name IN ('rol_administrador_bd','rol_analista_datos','rol_auditor')
ORDER BY rol, miembro;

SELECT pr.name AS principal, pe.state_desc, pe.permission_name,
       COALESCE(OBJECT_NAME(pe.major_id), 'SCHEMA/DB') AS objeto
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name IN ('rol_administrador_bd','rol_analista_datos','rol_auditor')
ORDER BY pr.name, pe.state_desc, pe.permission_name;

GO

/* #############################################################################
   SECCION 4) POLITICA DE RESPALDO Y RESTAURACION
   Fuente original: AtencionesSalud_respaldo_restauracion.sql
   ############################################################################# */
GO

/* =============================================================================
   AtencionesSalud - Politica de respaldo (FULL + DIFFERENTIAL) y restauracion
   Ver la justificacion completa (por que FULL+DIFF y no FULL+LOG) en
   Informe_Seguridad_Cumplimiento.md, seccion "Politica de respaldo".
   Ajustar las rutas de disco (@RutaBackup) al entorno real antes de ejecutar.
   ============================================================================= */

USE master;
GO

DECLARE @RutaBackup NVARCHAR(200) = N'C:\Backups\AtencionesSalud\';

/* -----------------------------------------------------------------------------
   1) MODELO DE RECUPERACION
   SIMPLE: esta base es un repositorio analitico que se recarga por lotes desde
   el CSV de origen (ver sp_CargarDimensiones / sp_CargarAtenciones). Si se
   pierde una transaccion puntual, el dato se puede volver a cargar desde el
   CSV; no se necesita recuperacion "a un segundo exacto" (point-in-time), asi
   que no se paga el costo operativo de administrar respaldos de log.
   ----------------------------------------------------------------------------- */
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

GO

/* #############################################################################
   SECCION 5) ANALISIS DE PLAN DE EJECUCION E INDICE
   Fuente original: AtencionesSalud_plan_ejecucion_indice.sql
   ############################################################################# */
GO

/* =============================================================================
   AtencionesSalud - Analisis de plan de ejecucion e indice de rendimiento
   Consulta critica: total de atendidos/atenciones por tipo de seguro en un
   rango de fechas (usada en reportes de cobertura de aseguramiento). Antes de
   este script, dbo.Atencion tiene indices por Fecha y por CodigoUnico
   (ver AtencionesSalud_sqlserver.sql) pero NINGUNO por TipoSeguroId, que es
   justamente el filtro de esta consulta: se espera un escaneo completo.

   Metodologia: correr cada bloque tal cual, en orden, en SQL Server Management
   Studio con "Include Actual Execution Plan" (Ctrl+M) activado, y copiar aqui
   los numeros de SET STATISTICS IO/TIME y el operador principal del plan
   (Clustered Index Scan vs. Index Seek) en la tabla de metricas del informe.
   ============================================================================= */

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
GO
