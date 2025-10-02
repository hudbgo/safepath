# dashboard/app.py
import streamlit as st
import requests
import pandas as pd
import os

BACKEND_URL = os.getenv("BACKEND_URL", "http://127.0.0.1:8000").rstrip("/")
API_PREFIX = "/api"

st.set_page_config(page_title="safepath - Dashboard", layout="wide")
st.title("safepath — Dashboard de vulnerabilidades")

col1, col2 = st.columns([1, 3])
with col1:
    st.subheader("Conexión")
    backend = st.text_input("Backend URL", value=BACKEND_URL)
    if st.button("Comprobar backend"):
        try:
            r = requests.get(backend + API_PREFIX + "/health", timeout=5)
            if r.ok:
                st.success("Backend online")
            else:
                st.error(f"Backend respondió: {r.status_code}")
        except Exception as e:
            st.error(f"No se puede conectar: {e}")

with col2:
    st.subheader("Hallazgos recientes")
    try:
        r = requests.get(backend + API_PREFIX + "/findings?limit=500", timeout=10)
        if not r.ok:
            st.error("Error al obtener datos: " + r.text)
        else:
            data = r.json()
            if not data:
                st.info("No hay hallazgos todavía.")
            else:
                df = pd.DataFrame(data)
                df["created_at"] = pd.to_datetime(df["created_at"])
                df = df.sort_values("created_at", ascending=False)
                st.dataframe(df, use_container_width=True)
                st.markdown("### Filtros")
                hosts = ["(todos)"] + sorted(df["host"].dropna().unique().tolist())
                chosen = st.selectbox("Filtrar por host", hosts)
                if chosen != "(todos)":
                    st.dataframe(df[df["host"] == chosen])
                st.markdown("### Resumen por severidad")
                severity_counts = df["severity"].fillna("unknown").value_counts()
                st.bar_chart(severity_counts)
    except Exception as e:
        st.error("Fallo al pedir al backend: " + str(e))
