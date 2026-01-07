import psycopg2
from psycopg2.extras import RealDictCursor

def get_db():
    conn = psycopg2.connect(
        dbname="iot_db",
        user="iot",
        password="2003",
        host="47.128.146.122",
        port=5432,
        cursor_factory=RealDictCursor  # 👈 CHÍNH LÀ DÒNG NÀY
    )
    return conn
