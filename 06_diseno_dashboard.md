# PASO 6 - Diseño del dashboard BI y análisis OLAP

## Dashboard propuesto

**Página 1 - Resumen ejecutivo**
- Tarjeta: Total Atenciones.
- Tarjeta: Total Atendidos.
- Tarjeta: Cantidad Establecimientos.
- Tarjeta: Promedio Atenciones por Establecimiento.
- Gráfico de columnas: Total Atenciones por Provincia.
- Gráfico de líneas: Total Atenciones por Mes.
- Gráfico de barras: Total Atenciones por UPS.
- Segmentadores: Provincia, Distrito, Sexo, TipoSeguro y Mes.

**Página 2 - Perfil de atención**
- Barras: Atenciones por TipoSeguro.
- Barras: Atenciones por Sexo.
- Matriz: Provincia > Distrito > Establecimiento.
- Tarjeta: Promedio Atenciones por Atendido.

## Operación OLAP demostrable
Usar una jerarquía en una matriz o gráfico:
**Provincia -> Distrito -> Establecimiento**.
Con el botón de "Expandir un nivel" de Power BI se realiza un **drill-down** desde la provincia hasta el establecimiento.

## Preguntas de negocio que responde
1. ¿Qué provincias y establecimientos concentran el mayor volumen de atenciones?
2. ¿Cómo se distribuyen las atenciones por servicio (UPS), sexo y tipo de seguro?

## Metadatos y gobernanza de KPIs
| KPI | Fuente | Fórmula | Responsable | Criterio de calidad |
|---|---|---|---|---|
| Total Atenciones | FactAtenciones.Atenciones | SUM(Atenciones) | Analista BI | No nulo, entero >= 0 |
| Total Atendidos | FactAtenciones.Atendidos | SUM(Atendidos) | Analista BI | No nulo, entero >= 0 |
| Cantidad Establecimientos | DimEstablecimiento.CodigoUnico | DISTINCTCOUNT(CodigoUnico) | Administrador DW | Código único no duplicado |
| Promedio Atenciones por Establecimiento | FactAtenciones + DimEstablecimiento | Total Atenciones / establecimientos | Analista BI | Denominador > 0 |
| % Atenciones SIS | FactAtenciones + DimPaciente | Atenciones SIS / total | Analista BI | TipoSeguro normalizado |

## Evidencia que debe capturarse para el informe
- Captura de la página 1 del dashboard.
- Captura de la página 2 del dashboard.
- Captura antes y después del drill-down Provincia -> Distrito -> Establecimiento.
- Captura de las medidas DAX en Power BI.
