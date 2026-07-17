import time, yaml, os
import MetaTrader5 as mt5
import psycopg2
import pandas as pd

# بارگذاری کانفیگ
with open("config/config.yaml") as f:
    cfg = yaml.safe_load(f)

# اتصال به دیتابیس
conn = psycopg2.connect(
    host=cfg["database"]["host"],
    port=cfg["database"]["port"],
    user=cfg["database"]["user"],
    password=cfg["database"]["password"],
    dbname=cfg["database"]["dbname"]
)
cur = conn.cursor()

# اتصال به MT5
mt5.initialize()

while True:
    for symbol in cfg["symbols"]:
        for tf in cfg["timeframes"]:
            rates = mt5.copy_rates_from_pos(symbol, getattr(mt5, f"TIMEFRAME_{tf}"), 0, 500)
            df = pd.DataFrame(rates)
            # TODO: ذخیره در TimescaleDB (INSERT ... ON CONFLICT DO NOTHING)
    conn.commit()
    time.sleep(60)
