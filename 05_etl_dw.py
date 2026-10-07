"""PASO 5 - ETL Kimball para el dataset de atenciones de salud.

Funciones:
- Extrae el CSV fuente.
- Limpia textos y duplicados exactos.
- Convierte edades negativas a valor desconocido.
- Genera dimensiones y tabla de hechos.
- Exporta CSVs del DW y un log de ejecución.
- Opcionalmente carga las tablas a SQL Server con pyodbc.

Ejemplos:
  python 05_etl_dw.py --input Atenciones_atendidos_2023-dires.csv --outdir dw_export
  python 05_etl_dw.py --input Atenciones_atendidos_2023-dires.csv --outdir dw_export --sample 10000

Carga SQL Server (después de ejecutar 05_dw_ddl.sql):
  python 05_etl_dw.py --input Atenciones_atendidos_2023-dires.csv --load-sql \
      --server localhost --database DW_DataSaludPeru --trusted
"""
import argparse
import os
import time
import pandas as pd


def log_row(etapa, entrada, salida, detalle, logs):
    logs.append({
        "Etapa": etapa,
        "FilasEntrada": int(entrada) if entrada is not None else None,
        "FilasSalida": int(salida) if salida is not None else None,
        "Detalle": detalle,
    })


def clean_text_columns(df):
    for c in df.select_dtypes(include="object").columns:
        df[c] = df[c].fillna("").astype(str).str.strip()
    return df


def build_dw(input_path, sample=0):
    logs = []
    t0 = time.time()
    df = pd.read_csv(input_path, sep=";", encoding="utf-8", low_memory=False,
                     nrows=sample if sample > 0 else None)
    log_row("EXTRACCION", len(df), len(df), "Lectura del CSV fuente con separador ';'.", logs)

    before = len(df)
    df = clean_text_columns(df)
    exact_dups = int(df.duplicated().sum())
    df = df.drop_duplicates().copy()
    log_row("LIMPIEZA_DUPLICADOS", before, len(df),
            f"Se eliminaron {exact_dups} duplicados exactos.", logs)

    neg_ages = int((pd.to_numeric(df["EDAD_REG"], errors="coerce") < 0).sum())
    df["EDAD_REG"] = pd.to_numeric(df["EDAD_REG"], errors="coerce")
    df.loc[df["EDAD_REG"] < 0, "EDAD_REG"] = pd.NA

    df["ATENDIDOS"] = pd.to_numeric(df["ATENDIDOS"], errors="coerce").fillna(0).astype("int64")
    df["ATENCIONES"] = pd.to_numeric(df["ATENCIONES"], errors="coerce").fillna(0).astype("int64")
    df.loc[df["ATENDIDOS"] < 0, "ATENDIDOS"] = 0
    df.loc[df["ATENCIONES"] < 0, "ATENCIONES"] = 0

    df["Fecha"] = pd.to_datetime(
        dict(year=df["ANIO"], month=df["MES"], day=df["DIA"]), errors="coerce"
    )
    invalid_dates = int(df["Fecha"].isna().sum())
    df = df[df["Fecha"].notna()].copy()
    log_row("NORMALIZACION", before, len(df),
            f"Edad negativa tratada como desconocida: {neg_ages}; fechas inválidas descartadas: {invalid_dates}.", logs)

    # DIM TIEMPO
    dim_tiempo = df[["Fecha"]].drop_duplicates().sort_values("Fecha").reset_index(drop=True)
    dim_tiempo["IdTiempo"] = range(1, len(dim_tiempo) + 1)
    dim_tiempo["Anio"] = dim_tiempo["Fecha"].dt.year.astype(int)
    dim_tiempo["Mes"] = dim_tiempo["Fecha"].dt.month.astype(int)
    dim_tiempo["Dia"] = dim_tiempo["Fecha"].dt.day.astype(int)
    dim_tiempo["Trimestre"] = dim_tiempo["Fecha"].dt.quarter.astype(int)
    meses = {1:"Enero",2:"Febrero",3:"Marzo",4:"Abril",5:"Mayo",6:"Junio",
             7:"Julio",8:"Agosto",9:"Septiembre",10:"Octubre",11:"Noviembre",12:"Diciembre"}
    dim_tiempo["NombreMes"] = dim_tiempo["Mes"].map(meses)
    dim_tiempo = dim_tiempo[["IdTiempo","Fecha","Anio","Mes","Dia","Trimestre","NombreMes"]]

    # DIM ESTABLECIMIENTO: si un mismo código presenta variantes, se conserva la primera fila observada.
    est_cols = ["CODIGO_UNICO","NOMBRE_ESTACLECIMIENTO","CATEGORIA","RED","MICRORED","PROVINCIA","DISTRITO"]
    dim_est = df[est_cols].drop_duplicates(subset=["CODIGO_UNICO"], keep="first").copy()
    dim_est = dim_est.sort_values("CODIGO_UNICO").reset_index(drop=True)
    dim_est["IdEstablecimiento"] = range(1, len(dim_est) + 1)
    dim_est = dim_est.rename(columns={
        "CODIGO_UNICO":"CodigoUnico",
        "NOMBRE_ESTACLECIMIENTO":"NombreEstablecimiento",
        "CATEGORIA":"Categoria",
        "RED":"Red",
        "MICRORED":"Microred",
        "PROVINCIA":"Provincia",
        "DISTRITO":"Distrito",
    })[["IdEstablecimiento","CodigoUnico","NombreEstablecimiento","Categoria","Red","Microred","Provincia","Distrito"]]

    # DIM PACIENTE (perfil agregado, sin identificadores personales)
    pac_cols = ["EDAD_REG","TIPO_EDAD","SEXO","ETNIA","TIPO_SEGURO"]
    dim_pac = df[pac_cols].drop_duplicates().reset_index(drop=True)
    dim_pac["IdPaciente"] = range(1, len(dim_pac) + 1)
    dim_pac = dim_pac.rename(columns={
        "EDAD_REG":"Edad","TIPO_EDAD":"TipoEdad","SEXO":"Sexo","ETNIA":"Etnia","TIPO_SEGURO":"TipoSeguro"
    })[["IdPaciente","Edad","TipoEdad","Sexo","Etnia","TipoSeguro"]]

    # DIM SERVICIO
    dim_serv = df[["UPS"]].drop_duplicates().sort_values("UPS").reset_index(drop=True)
    dim_serv["IdServicio"] = range(1, len(dim_serv) + 1)
    dim_serv = dim_serv.rename(columns={"UPS":"UPS"})[["IdServicio","UPS"]]

    # FACT: resolver claves sustitutas mediante merge
    fact = df[["Fecha","CODIGO_UNICO","EDAD_REG","TIPO_EDAD","SEXO","ETNIA","TIPO_SEGURO","UPS","ATENDIDOS","ATENCIONES","FECHA_CORTE"]].copy()
    fact = fact.merge(dim_tiempo[["IdTiempo","Fecha"]], on="Fecha", how="left")
    fact = fact.merge(dim_est[["IdEstablecimiento","CodigoUnico"]], left_on="CODIGO_UNICO", right_on="CodigoUnico", how="left")
    fact = fact.merge(dim_pac, left_on=["EDAD_REG","TIPO_EDAD","SEXO","ETNIA","TIPO_SEGURO"],
                      right_on=["Edad","TipoEdad","Sexo","Etnia","TipoSeguro"], how="left")
    fact = fact.merge(dim_serv, on="UPS", how="left")
    fact = fact.rename(columns={"ATENDIDOS":"Atendidos","ATENCIONES":"Atenciones","FECHA_CORTE":"FechaCorte"})
    fact = fact[["IdTiempo","IdEstablecimiento","IdPaciente","IdServicio","Atendidos","Atenciones","FechaCorte"]]

    log_row("CARGA_MODELO_DIMENSIONAL", len(df), len(fact),
            f"DimTiempo={len(dim_tiempo)}, DimEstablecimiento={len(dim_est)}, DimPaciente={len(dim_pac)}, DimServicio={len(dim_serv)}.", logs)
    log_row("FIN", len(df), len(fact), f"ETL completado en {time.time()-t0:.2f} segundos.", logs)

    return dim_tiempo, dim_est, dim_pac, dim_serv, fact, pd.DataFrame(logs)


def export_csvs(outdir, dims):
    os.makedirs(outdir, exist_ok=True)
    names = ["DimTiempo", "DimEstablecimiento", "DimPaciente", "DimServicio", "FactAtenciones", "ETL_Log"]
    for name, df in zip(names, dims):
        df.to_csv(os.path.join(outdir, f"{name}.csv"), index=False, encoding="utf-8-sig")


def sql_connect(args):
    try:
        import pyodbc
    except ImportError as e:
        raise SystemExit("Falta pyodbc. Instalar con: pip install pyodbc") from e

    if args.trusted:
        cs = (f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={args.server};"
              f"DATABASE={args.database};Trusted_Connection=yes;TrustServerCertificate=yes;")
    else:
        cs = (f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={args.server};DATABASE={args.database};"
              f"UID={args.user};PWD={args.password};TrustServerCertificate=yes;")
    return pyodbc.connect(cs)


def bulk_insert(conn, table, columns, df, chunk=5000):
    cur = conn.cursor()
    cur.fast_executemany = True
    placeholders = ",".join(["?"] * len(columns))
    cols_sql = ",".join(f"[{c}]" for c in columns)
    sql = f"INSERT INTO dbo.{table} ({cols_sql}) VALUES ({placeholders})"
    data = df[columns].where(pd.notna(df[columns]), None)
    for start in range(0, len(data), chunk):
        rows = list(data.iloc[start:start+chunk].itertuples(index=False, name=None))
        cur.executemany(sql, rows)
        conn.commit()
    cur.close()


def load_sql(args, dim_tiempo, dim_est, dim_pac, dim_serv, fact, logdf):
    conn = sql_connect(args)
    cur = conn.cursor()
    # Se asume que el DDL fue ejecutado y las tablas están vacías.
    counts = cur.execute("SELECT COUNT(*) FROM dbo.FactAtenciones").fetchone()[0]
    if counts:
        raise SystemExit("FactAtenciones ya contiene datos. Vacíe/recree el DW antes de cargar para evitar duplicados.")
    cur.close()

    # Mantener IDs sustitutos definidos por el ETL requiere IDENTITY_INSERT.
    for table, df, cols in [
        ("DimTiempo", dim_tiempo, list(dim_tiempo.columns)),
        ("DimEstablecimiento", dim_est, list(dim_est.columns)),
        ("DimPaciente", dim_pac, list(dim_pac.columns)),
        ("DimServicio", dim_serv, list(dim_serv.columns)),
    ]:
        c = conn.cursor()
        c.execute(f"SET IDENTITY_INSERT dbo.{table} ON")
        conn.commit(); c.close()
        bulk_insert(conn, table, cols, df)
        c = conn.cursor(); c.execute(f"SET IDENTITY_INSERT dbo.{table} OFF"); conn.commit(); c.close()

    bulk_insert(conn, "FactAtenciones", list(fact.columns), fact)
    bulk_insert(conn, "ETL_Log", ["Etapa","FilasEntrada","FilasSalida","Detalle"], logdf)
    conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--outdir", default="dw_export")
    ap.add_argument("--sample", type=int, default=0, help="Cantidad de filas para prueba; 0 procesa todo.")
    ap.add_argument("--load-sql", action="store_true")
    ap.add_argument("--server", default="localhost")
    ap.add_argument("--database", default="DW_DataSaludPeru")
    ap.add_argument("--trusted", action="store_true")
    ap.add_argument("--user", default="sa")
    ap.add_argument("--password", default="")
    args = ap.parse_args()

    result = build_dw(args.input, args.sample)
    export_csvs(args.outdir, result)
    print(result[-1].to_string(index=False))
    print(f"Archivos exportados en: {args.outdir}")

    if args.load_sql:
        load_sql(args, *result)
        print("Carga a SQL Server completada.")


if __name__ == "__main__":
    main()
