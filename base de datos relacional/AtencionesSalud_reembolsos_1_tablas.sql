GO

GO

IF DB_ID(N'AtencionesSalud') IS NULL
    CREATE DATABASE AtencionesSalud;
GO
USE AtencionesSalud;
GO

USE AtencionesSalud;
GO

CREATE SCHEMA reembolsos AUTHORIZATION dbo;
GO

-- ---------- Extension de la geografia existente (dbo) ----------

CREATE TABLE dbo.Region (
    RegionId SMALLINT     IDENTITY(1,1) NOT NULL,
    Nombre   NVARCHAR(50) NOT NULL,
    CONSTRAINT PK_Region        PRIMARY KEY (RegionId),
    CONSTRAINT UQ_Region_Nombre UNIQUE (Nombre)
);
GO

ALTER TABLE dbo.Provincia ADD RegionId SMALLINT NULL;
GO

-- Las 10 provincias ya cargadas pertenecen a la region San Martin.
INSERT INTO dbo.Region (Nombre) VALUES (N'SAN MARTIN');

UPDATE dbo.Provincia
SET RegionId = (SELECT RegionId FROM dbo.Region WHERE Nombre = N'SAN MARTIN');
GO

ALTER TABLE dbo.Provincia ALTER COLUMN RegionId SMALLINT NOT NULL;
ALTER TABLE dbo.Provincia
    ADD CONSTRAINT FK_Provincia_Region FOREIGN KEY (RegionId) REFERENCES dbo.Region (RegionId);
GO

-- ---------- Catalogos propios de reembolsos ----------

CREATE TABLE reembolsos.Sede (
    SedeId   SMALLINT      IDENTITY(1,1) NOT NULL,
    RegionId SMALLINT      NOT NULL,
    Nombre   NVARCHAR(80)  NOT NULL,
    CONSTRAINT PK_Sede         PRIMARY KEY (SedeId),
    CONSTRAINT UQ_Sede         UNIQUE (RegionId, Nombre),
    CONSTRAINT FK_Sede_Region  FOREIGN KEY (RegionId) REFERENCES dbo.Region (RegionId)
);

CREATE TABLE reembolsos.TipoAtencion (
    TipoAtencionId TINYINT       IDENTITY(1,1) NOT NULL,
    Nombre         NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_TipoAtencion        PRIMARY KEY (TipoAtencionId),
    CONSTRAINT UQ_TipoAtencion_Nombre UNIQUE (Nombre)
);

CREATE TABLE reembolsos.MedioSolicitud (
    MedioSolicitudId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre           NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_MedioSolicitud        PRIMARY KEY (MedioSolicitudId),
    CONSTRAINT UQ_MedioSolicitud_Nombre UNIQUE (Nombre)
);

CREATE TABLE reembolsos.TipoSolicitante (
    TipoSolicitanteId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre            NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_TipoSolicitante        PRIMARY KEY (TipoSolicitanteId),
    CONSTRAINT UQ_TipoSolicitante_Nombre UNIQUE (Nombre)
);

CREATE TABLE reembolsos.CondicionAsegurado (
    CondicionAseguradoId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre               NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_CondicionAsegurado        PRIMARY KEY (CondicionAseguradoId),
    CONSTRAINT UQ_CondicionAsegurado_Nombre UNIQUE (Nombre)
);

CREATE TABLE reembolsos.Parentesco (
    ParentescoId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre       NVARCHAR(30) NOT NULL,
    CONSTRAINT PK_Parentesco        PRIMARY KEY (ParentescoId),
    CONSTRAINT UQ_Parentesco_Nombre UNIQUE (Nombre)
);

CREATE TABLE reembolsos.SituacionAsegurado (
    SituacionAseguradoId TINYINT      IDENTITY(1,1) NOT NULL,
    Nombre               NVARCHAR(40) NOT NULL,
    CONSTRAINT PK_SituacionAsegurado        PRIMARY KEY (SituacionAseguradoId),
    CONSTRAINT UQ_SituacionAsegurado_Nombre UNIQUE (Nombre)
);
GO

-- ---------- Tabla de hechos ----------
-- Grano: periodo + sede + tipo de atencion + medio + solicitante + condicion +
-- parentesco + situacion. MontoPagado es DECIMAL (dinero), no un conteo entero.

CREATE TABLE reembolsos.Reembolso (
    ReembolsoId          BIGINT        IDENTITY(1,1) NOT NULL,
    Periodo              DATE          NOT NULL,
    SedeId               SMALLINT      NOT NULL,
    TipoAtencionId       TINYINT       NOT NULL,
    MedioSolicitudId     TINYINT       NOT NULL,
    TipoSolicitanteId    TINYINT       NOT NULL,
    CondicionAseguradoId TINYINT       NOT NULL,
    ParentescoId         TINYINT       NOT NULL,
    SituacionAseguradoId TINYINT       NOT NULL,
    NumeroAsegurados     INT           NOT NULL,
    SolicitudesReembolso INT           NOT NULL,
    MontoPagado          DECIMAL(12,2) NOT NULL,
    CONSTRAINT PK_Reembolso                  PRIMARY KEY CLUSTERED (ReembolsoId),
    CONSTRAINT FK_Reembolso_Sede             FOREIGN KEY (SedeId)               REFERENCES reembolsos.Sede (SedeId),
    CONSTRAINT FK_Reembolso_TipoAtencion     FOREIGN KEY (TipoAtencionId)       REFERENCES reembolsos.TipoAtencion (TipoAtencionId),
    CONSTRAINT FK_Reembolso_MedioSolicitud   FOREIGN KEY (MedioSolicitudId)     REFERENCES reembolsos.MedioSolicitud (MedioSolicitudId),
    CONSTRAINT FK_Reembolso_TipoSolicitante  FOREIGN KEY (TipoSolicitanteId)    REFERENCES reembolsos.TipoSolicitante (TipoSolicitanteId),
    CONSTRAINT FK_Reembolso_Condicion        FOREIGN KEY (CondicionAseguradoId) REFERENCES reembolsos.CondicionAsegurado (CondicionAseguradoId),
    CONSTRAINT FK_Reembolso_Parentesco       FOREIGN KEY (ParentescoId)         REFERENCES reembolsos.Parentesco (ParentescoId),
    CONSTRAINT FK_Reembolso_Situacion        FOREIGN KEY (SituacionAseguradoId) REFERENCES reembolsos.SituacionAsegurado (SituacionAseguradoId),
    CONSTRAINT CK_Reembolso_Numeros          CHECK (NumeroAsegurados >= 0 AND SolicitudesReembolso >= 0 AND MontoPagado >= 0)
);

CREATE NONCLUSTERED INDEX IX_Reembolso_Periodo ON reembolsos.Reembolso (Periodo);
CREATE NONCLUSTERED INDEX IX_Reembolso_Sede    ON reembolsos.Reembolso (SedeId, Periodo);
GO

-- ---------- Staging (mismas columnas y orden que el CSV) ----------

CREATE TABLE reembolsos.stg_Reembolsos (
    StgId                     INT IDENTITY(1,1) NOT NULL,
    Periodo                   VARCHAR(10),      -- DD/MM/AAAA
    Region                    NVARCHAR(50),
    Sede                      NVARCHAR(80),
    TipoDeAtencion            NVARCHAR(100),
    MedioDeSolicitud          NVARCHAR(30),
    Solicitante               NVARCHAR(30),
    CondicionDelAsegurado     NVARCHAR(30),
    Parentesco                NVARCHAR(30),
    Situacion                 NVARCHAR(40),
    NumeroDeAsegurados        VARCHAR(10),
    SolicitudesDeReembolso    VARCHAR(10),
    MontoPagado               VARCHAR(20),      -- "S/ 1,225,889.22"
    CONSTRAINT PK_stg_Reembolsos PRIMARY KEY (StgId)
);
GO

-- ---------- Tabla de auditoria (la usa el trigger de la seccion 1.3) ----------

CREATE TABLE reembolsos.LogAuditoriaReembolso (
    AuditId             BIGINT        IDENTITY(1,1) NOT NULL,
    Operacion           CHAR(1)       NOT NULL,   -- I, U, D
    ReembolsoId         BIGINT        NOT NULL,
    Periodo             DATE          NOT NULL,
    MontoPagado_Anterior DECIMAL(12,2) NULL,
    MontoPagado_Nuevo    DECIMAL(12,2) NULL,
    UsuarioBD           SYSNAME       NOT NULL,
    FechaHora           DATETIME2(0)  NOT NULL CONSTRAINT DF_LogAuditoriaReembolso_Fecha DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_LogAuditoriaReembolso PRIMARY KEY (AuditId)
);
GO

CREATE VIEW reembolsos.vw_ReembolsosAgregado
AS
SELECT r.Nombre  AS Region,
       sd.Nombre AS Sede,
       ta.Nombre AS TipoAtencion,
       reem.Periodo,
       SUM(reem.NumeroAsegurados)     AS TotalAsegurados,
       SUM(reem.SolicitudesReembolso) AS TotalSolicitudes,
       SUM(reem.MontoPagado)          AS TotalMontoPagado
FROM reembolsos.Reembolso reem
JOIN reembolsos.Sede sd        ON sd.SedeId = reem.SedeId
JOIN dbo.Region r              ON r.RegionId = sd.RegionId
JOIN reembolsos.TipoAtencion ta ON ta.TipoAtencionId = reem.TipoAtencionId
GROUP BY r.Nombre, sd.Nombre, ta.Nombre, reem.Periodo
HAVING SUM(reem.NumeroAsegurados) >= 5;
GO

GRANT CREATE TABLE, CREATE VIEW ON SCHEMA::reembolsos TO rol_administrador_bd;
GRANT ALTER, SELECT, INSERT, UPDATE, DELETE ON SCHEMA::reembolsos TO rol_administrador_bd;

GRANT SELECT ON reembolsos.vw_ReembolsosAgregado TO rol_analista_datos;
DENY SELECT ON reembolsos.Reembolso        TO rol_analista_datos;
DENY SELECT ON reembolsos.stg_Reembolsos   TO rol_analista_datos;

GRANT SELECT ON reembolsos.Reembolso TO rol_auditor;
DENY INSERT, UPDATE, DELETE, ALTER  ON SCHEMA::reembolsos TO rol_auditor;
GO
