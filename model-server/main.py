from fastapi import FastAPI
from pydantic import BaseModel
import yaml, os
import torch, pandas as pd

# بارگذاری کانفیگ
with open("config/config.yaml") as f:
    cfg = yaml.safe_load(f)

app = FastAPI(title="SingularityTrader Model Server")

class PredictRequest(BaseModel):
    symbol: str
    timeframe: str

class PredictResponse(BaseModel):
    signal: str  # "buy","sell","hold"
    confidence: float

@app.post("/predict", response_model=PredictResponse)
async def predict(req: PredictRequest):
    # TODO: بارگذاری و اجرای مدل LSTM/Transformer
    # داده‌های اخیر را از TimescaleDB بخوانید و پیش‌بینی کنید
    # نمونه پاسخ:
    return PredictResponse(signal="hold", confidence=0.50)
