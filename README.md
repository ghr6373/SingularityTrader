\# SingularityTrader



\## Overview

An explainable, AI-driven trading framework for MT5, supporting XAUUSD \& EURUSD.



\## Structure

\- singularity\_Engine\_v1.mq5 : MT5 Expert Advisor

\- docker-compose.yml         : Orchestrates TimescaleDB, model-server, data-fetcher

\- config/                    : Environment \& YAML config

\- model-server/              : FastAPI model-serving

\- data-fetcher/              : Python data ingestion



\## Prerequisites

\- Docker Desktop \& Compose

\- MetaTrader 5 (WebRequest enabled)

\- Git



\## Quickstart

1\. git clone https://github.com/ghr6373/SingularityTrader.git

2\. cd SingularityTrader

3\. Populate EA source \& configs (as above)

4\. docker compose up -d

5\. Attach `singularity\_Engine\_v1.ex5` to MT5 chart



\## License

MIT



