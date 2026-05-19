# FinWise AI Service

FastAPI service for FinWise AI Insights. It accepts structured monthly finance
metrics from the Flutter app and returns personalized guidance using Groq.

## Run locally

```powershell
cd backend/ai_service
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
$env:GROQ_API_KEY=GROQ_API_KEY
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

If `GROQ_API_KEY` is not set, the service returns a deterministic fallback so
the app remains demoable.

Android emulator default URL from Flutter is `http://10.0.2.2:8000`.
