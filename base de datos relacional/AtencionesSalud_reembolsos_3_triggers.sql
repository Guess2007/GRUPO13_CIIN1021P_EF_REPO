/* =============================================================================
   AtencionesSalud - Dominio REEMBOLSOS
   1.3.  TRIGGERS
   Requiere haber ejecutado antes AtencionesSalud_reembolsos_1_tablas.sql
   (usa reembolsos.LogAuditoriaReembolso).
   ============================================================================= */

USE AtencionesSalud;
GO

CREATE TRIGGER reembolsos.trg_Reembolso_Auditoria
ON reembolsos.Reembolso
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO reembolsos.LogAuditoriaReembolso
           (Operacion, ReembolsoId, Periodo, MontoPagado_Anterior, MontoPagado_Nuevo, UsuarioBD)
    SELECT 'I', i.ReembolsoId, i.Periodo, NULL, i.MontoPagado, SUSER_SNAME()
    FROM inserted i
    LEFT JOIN deleted d ON d.ReembolsoId = i.ReembolsoId
    WHERE d.ReembolsoId IS NULL

    UNION ALL

    SELECT 'U', i.ReembolsoId, i.Periodo, d.MontoPagado, i.MontoPagado, SUSER_SNAME()
    FROM inserted i
    JOIN deleted d ON d.ReembolsoId = i.ReembolsoId

    UNION ALL

    SELECT 'D', d.ReembolsoId, d.Periodo, d.MontoPagado, NULL, SUSER_SNAME()
    FROM deleted d
    LEFT JOIN inserted i ON i.ReembolsoId = d.ReembolsoId
    WHERE i.ReembolsoId IS NULL;
END
GO
