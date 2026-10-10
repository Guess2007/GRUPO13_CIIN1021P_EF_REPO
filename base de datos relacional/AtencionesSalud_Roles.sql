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
ORDER BY pr.name, pe.state_desc, pe.permission_name;+
