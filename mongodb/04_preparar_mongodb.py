"""Convierte el dataset de atenciones del MINSA a JSON Lines para mongoimport.

Ejemplo:
  python 04_preparar_mongodb.py --input Atenciones_atendidos_2023-dires.csv --output atenciones_salud.jsonl

Luego:
  mongoimport --db DataSaludPeru --collection atenciones_salud --file atenciones_salud.jsonl
"""
import argparse
import json
import pandas as pd


def limpiar_texto(v):
    if pd.isna(v):
        return ""
    return str(v).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", default="atenciones_salud.jsonl")
    ap.add_argument("--limit", type=int, default=0, help="0 = todos los registros")
    args = ap.parse_args()

    usecols = [
        "ANIO", "MES", "DIA", "CATEGORIA", "RED", "MICRORED", "CODIGO_UNICO",
        "NOMBRE_ESTACLECIMIENTO", "PROVINCIA", "DISTRITO", "EDAD_REG", "TIPO_EDAD",
        "SEXO", "ETNIA", "TIPO_SEGURO", "UPS", "ATENDIDOS", "ATENCIONES", "FECHA_CORTE"
    ]

    total = 0
    with open(args.output, "w", encoding="utf-8") as out:
        for chunk in pd.read_csv(args.input, sep=";", encoding="utf-8", usecols=usecols,
                                 chunksize=50000, low_memory=False):
            for c in chunk.select_dtypes(include="object").columns:
                chunk[c] = chunk[c].map(limpiar_texto)

            # Edad -1 se interpreta como desconocida, no como edad real.
            chunk.loc[chunk["EDAD_REG"] < 0, "EDAD_REG"] = pd.NA

            fechas = pd.to_datetime(
                dict(year=chunk["ANIO"], month=chunk["MES"], day=chunk["DIA"]),
                errors="coerce"
            )

            for i, row in chunk.iterrows():
                fecha = fechas.loc[i]
                doc = {
                    "fecha": {"$date": fecha.strftime("%Y-%m-%dT00:00:00Z")} if not pd.isna(fecha) else None,
                    "establecimiento": {
                        "codigo": int(row["CODIGO_UNICO"]),
                        "nombre": row["NOMBRE_ESTACLECIMIENTO"],
                        "categoria": row["CATEGORIA"],
                        "red": row["RED"],
                        "microred": row["MICRORED"],
                        "provincia": row["PROVINCIA"],
                        "distrito": row["DISTRITO"]
                    },
                    "paciente": {
                        "edad": None if pd.isna(row["EDAD_REG"]) else int(row["EDAD_REG"]),
                        "tipoEdad": row["TIPO_EDAD"],
                        "sexo": row["SEXO"],
                        "etnia": row["ETNIA"],
                        "seguro": row["TIPO_SEGURO"]
                    },
                    "ups": row["UPS"],
                    "atendidos": int(row["ATENDIDOS"]),
                    "atenciones": int(row["ATENCIONES"]),
                    "fechaCorte": str(row["FECHA_CORTE"])
                }
                out.write(json.dumps(doc, ensure_ascii=False) + "\n")
                total += 1
                if args.limit and total >= args.limit:
                    print(f"Generados {total:,} documentos en {args.output}")
                    return
    print(f"Generados {total:,} documentos en {args.output}")


if __name__ == "__main__":
    main()
