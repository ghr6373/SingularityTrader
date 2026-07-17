//+------------------------------------------------------------------+
//|                                         Singularity Engine v1.6 |
//|                                  Copyright 2026, GapGPT & Trader |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, GapGPT"
#property link      ""
#property version   "1.60"
#property strict

#include <Trade\Trade.mqh>

//--- ENUMS
enum ENUM_SIGNAL_DIRECTION {
    SIGNAL_NONE,
    SIGNAL_BUY,
    SIGNAL_SELL
};

//--- STRUCTURES
struct LayerResult {
    bool              is_confirmed;      
    double            confidence;       
    string            description;      
    ENUM_SIGNAL_DIRECTION direction;

    LayerResult() : is_confirmed(false), confidence(0.0), description(""), direction(SIGNAL_NONE) {}
    LayerResult(bool confirmed, double conf, string desc, ENUM_SIGNAL_DIRECTION dir) 
        : is_confirmed(confirmed), confidence(conf), description(desc), direction(dir) {}
};

//--- INPUT PARAMETERS

input group "---- RISK MANAGEMENT SETTINGS ----"
input bool   InpUseAutoRisk   = true;      // Use Percentage Risk? (True=Auto, False=Fixed)
input double InpRiskPercent   = 1.0;       // Risk % per Trade (If Auto is ON)
input double InpFixedLot      = 0.1;       // Fixed Lot Size (If Auto is OFF)

input group "---- ADDITIONAL SETTINGS ----"
input double InpMinLot        = 0.01;      // Minimum Lot Allowed
input double InpMaxLot        = 10.0;     // Maximum Lot Allowed
input int    InpLookback      = 20;        // Lookback Period
input double InpVolThreshold  = 1.5;       // Volume Spike Multiplier
input int    InpSLBuffer      = 10;        // SL Buffer (Points)
input double InpRRRatio       = 2.0;      // Risk:Reward Ratio
input long   InpMagicNumber   = 123456;    // Magic Number

//--- BASE CLASS
class CBaseLayer {
protected:
    string m_name;
    double m_weight;
public:
    CBaseLayer(string name, double weight) : m_name(name), m_weight(weight) {}
    virtual LayerResult Check() = 0; // Virtual function must be defined correctly
};

//+------------------------------------------------------------------+
//| LAYER 1: LIQUIDITY & STOP HUNTING                               |
//+------------------------------------------------------------------+
class CLayer1_Liquidity : public CBaseLayer {
public:
    CLayer1_Liquidity(int lookback, double vol_thresh) 
        : CBaseLayer("Liquidity_Layer", 0.40) {}

    virtual LayerResult Check() override {
        double high[], low[], close[];
        long volume[];
        int lookback = InpLookback;

        ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); 
        ArraySetAsSeries(close, true); ArraySetAsSeries(volume, true);

        if(CopyHigh(_Symbol, _Period, 0, lookback + 5, high) <= 0) return LayerResult(false, 0, "Err High", SIGNAL_NONE);
        if(CopyLow(_Symbol, _Period, 0, lookback + 5, low) <= 0) return LayerResult(false, 0, "Err Low", SIGNAL_NONE);
        if(CopyClose(_Symbol, _Period, 0, lookback + 5, close) <= 0) return LayerResult(false, 0, "Err Close", SIGNAL_NONE);
        if(CopyTickVolume(_Symbol, _Period, 0, lookback + 5, volume) <= 0) return LayerResult(false, 0, "Err Vol", SIGNAL_NONE);

        double swing_high = 0, swing_low = 999999;
        for(int i=1; i<lookback; i++) {
            if(high[i] > high[i+1] && high[i] > high[i-1]) swing_high = high[i];
            if(low[i] < low[i+1] && low[i] < low[i-1]) swing_low = low[i];
        }

        if(swing_low != 999999 && low[0] < swing_low && close[0] > swing_low) {
            double avg_vol = 0;
            for(int i=1; i<=5; i++) avg_vol += (double)volume[i];
            avg_vol /= 5.0;
            if((double)volume[0] > avg_vol * InpVolThreshold)
                return LayerResult(true, 0.7, "Liquidity Sweep Low", SIGNAL_BUY);
        }

        if(swing_high > 0 && high[0] > swing_high && close[0] < swing_high) {
            double avg_vol = 0;
            for(int i=1; i<=5; i++) avg_vol += (double)volume[i];
            avg_vol /= 5.0;
            if((double)volume[0] > avg_vol * InpVolThreshold)
                return LayerResult(true, 0.7, "Liquidity Sweep High", SIGNAL_SELL);
        }

        return LayerResult(false, 0, "No Liquidity Event", SIGNAL_NONE);
    }
};

//+------------------------------------------------------------------+
//| LAYER 2: MARKET STRUCTURE (CHoCH)                               |
//+------------------------------------------------------------------+
class CLayer2_MarketStructure : public CBaseLayer {
public:
    CLayer2_MarketStructure(int period) 
        : CBaseLayer("Market_Structure_Layer", 0.60) {}

    virtual LayerResult Check() override {
        double high[], low[], close[];
        int lookback = InpLookback;

        ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); 
        ArraySetAsSeries(close, true);

        if(CopyHigh(_Symbol, _Period, 0, lookback + 5, high) <= 0) return LayerResult(false, 0, "Err High", SIGNAL_NONE);
        if(CopyLow(_Symbol, _Period, 0, lookback + 5, low) <= 0) return LayerResult(false, 0, "Err Low", SIGNAL_NONE);
        if(CopyClose(_Symbol, _Period, 0, lookback + 5, close) <= 0) return LayerResult(false, 0, "Err Close", SIGNAL_NONE);

        double last_fractal_high = 0;
        double last_fractal_low = 999999;

        for(int i=2; i<lookback; i++) {
            if(high[i] > high[i+1] && high[i] > high[i-1]) { last_fractal_high = high[i]; break; }
        }
        for(int i=2; i<lookback; i++) {
            if(low[i] < low[i+1] && low[i] < low[i-1]) { last_fractal_low = low[i]; break; }
        }

        if(last_fractal_high > 0 && close[0] > last_fractal_high) 
            return LayerResult(true, 0.85, "Bullish CHoCH", SIGNAL_BUY);
            
        if(last_fractal_low != 999999 && close[0] < last_fractal_low) 
            return LayerResult(true, 0.85, "Bearish CHoCH", SIGNAL_SELL);

        return LayerResult(false, 0, "No Structure Break", SIGNAL_NONE);
    }
};

//+------------------------------------------------------------------+
//| LAYER 3: RISK MANAGEMENT & EXECUTION                              |
//+------------------------------------------------------------------+
class CLayer3_RiskManager {
private:
    CTrade  m_trade;

public:
    CLayer3_RiskManager() {
        m_trade.SetExpertMagicNumber(InpMagicNumber);
    }

    double CalculateLotSize(double sl_distance_points) {
        if (!InpUseAutoRisk) return InpFixedLot;

        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double risk_amount = balance * (InpRiskPercent / 100.0);
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

        if (sl_distance_points <= 0 || tick_value <= 0) return InpFixedLot;

        double lot = risk_amount / (sl_distance_points * (tick_value / tick_size));
        double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
        lot = MathFloor(lot / step) * step;
        
        if (lot < InpMinLot) lot = InpMinLot;
        if (lot > InpMaxLot) lot = InpMaxLot;
        return lot;
    }

    void ExecuteTrade(ENUM_SIGNAL_DIRECTION dir, double sl, double tp) {
        double price = (dir == SIGNAL_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double sl_dist = MathAbs(price - sl) / _Point;
        double lot = CalculateLotSize(sl_dist);

        if (dir == SIGNAL_BUY) {
            m_trade.Buy(lot, _Symbol, price, sl, tp, "Singularity Buy");
        } else if (dir == SIGNAL_SELL) {
            m_trade.Sell(lot, _Symbol, price, sl, tp, "Singularity Sell");
        }
    }
};

//+------------------------------------------------------------------+
//| SINGULARITY ENGINE CORE                                          |
//+------------------------------------------------------------------+
class CSingularityEngine {
private:
    CLayer1_Liquidity* m_l1;
    CLayer2_MarketStructure* m_l2;
    CLayer3_RiskManager* m_l3;

public:
    CSingularityEngine() {
        m_l1 = new CLayer1_Liquidity(InpLookback, InpVolThreshold);
        m_l2 = new CLayer2_MarketStructure(InpLookback);
        m_l3 = new CLayer3_RiskManager();
    }

    ~CSingularityEngine() {
        delete m_l1; delete m_l2; delete m_l3;
    }

    void OnTick() {
        if (PositionSelectByMagic(InpMagicNumber)) return;

        LayerResult r1 = m_l1.Check();
        LayerResult r2 = m_l2.Check();

        if (r1.is_confirmed && r2.is_confirmed && r1.direction == r2.direction) {
            double price = (r1.direction == SIGNAL_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = 0, tp = 0;
            double points_buffer = InpSLBuffer * _Point;

            if (r1.direction == SIGNAL_BUY) {
                double low_array[]; 
                if(CopyLow(_Symbol, _Period, 0, 10, low_array) > 0) {
                    ArraySetAsSeries(low_array, true);
                    int min_idx = ArrayMinimum(low_array);
                    sl = low_array[min_idx] - points_buffer;
                    double risk = price - sl;
                    if(risk > 0) {
                        tp = price + (risk * InpRRRatio);
                        m_l3.ExecuteTrade(SIGNAL_BUY, sl, tp);
                    }
                }
            } 
            else if (r1.direction == SIGNAL_SELL) {
                double high_array[]; 
                if(CopyHigh(_Symbol, _Period, 0, 10, high_array) > 0) {
                    ArraySetAsSeries(high_array, true);
                    int max_idx = ArrayMaximum(high_array);
                    sl = high_array[max_idx] + points_buffer;
                    double risk = sl - price;
                    if(risk > 0) {
                        tp = price - (risk * InpRRRatio);
                        m_l3.ExecuteTrade(SIGNAL_SELL, sl, tp);
                    }
                }
            }
        }
    }

    bool PositionSelectByMagic(long magic) {
        for(int i=PositionsTotal()-1; i>=0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket)) {
                if(PositionGetInteger(POSITION_MAGIC) == magic) return true;
            }
        }
        return false;
    }
};

//--- GLOBAL INSTANCE
CSingularityEngine* engine = NULL;

//+------------------------------------------------------------------+
//| Expert functions                                                 |
//+------------------------------------------------------------------+
int OnInit() {
    engine = new CSingularityEngine();
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    if(CheckPointer(engine) == POINTER_DYNAMIC) delete engine;
}

void OnTick() {
    if(CheckPointer(engine) == POINTER_DYNAMIC) engine.OnTick();
}
