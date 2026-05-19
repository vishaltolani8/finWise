import base64
from datetime import datetime
import json
import math
import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, UploadFile
from groq import Groq
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from pydantic import BaseModel, Field


# Load .env from the same directory as this script
env_path = Path(__file__).parent / ".env"
load_dotenv(env_path)

# Debug: Print if API key is loaded (remove in production)
api_key = os.getenv("GROQ_API_KEY", "").strip()
print(f"Groq API Key loaded: {'Yes' if api_key else 'NO - Check .env file!'}")

app = FastAPI(title="FinWise AI Service", version="0.1.0")
GROQ_MODEL = "llama-3.3-70b-versatile"
GROQ_VISION_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"
MAX_RECEIPT_IMAGE_BYTES = 3 * 1024 * 1024

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class CategoryTotal(BaseModel):
    name: str
    amount: float
    transactionCount: int = 0


class RecentTransaction(BaseModel):
    title: str
    category: str
    amount: float
    income: bool
    date: str


class BudgetStatus(BaseModel):
    name: str
    limit: float
    spent: float
    remaining: float = 0
    percentUsed: float = 0


class FinancialSnapshot(BaseModel):
    periodStart: str
    periodEnd: str
    income: float = 0
    expenses: float = 0
    savings: float = 0
    savingsRate: float = 0
    transactionCount: int = 0
    topCategories: list[CategoryTotal] = Field(default_factory=list)
    recentTransactions: list[RecentTransaction] = Field(default_factory=list)
    budgetStatuses: list[BudgetStatus] = Field(default_factory=list)


class InsightRequest(BaseModel):
    app: str = "FinWise"
    user: dict[str, Any] = Field(default_factory=dict)
    snapshot: FinancialSnapshot


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/debug")
def debug_info() -> dict[str, Any]:
    """Debug endpoint to check API key and Groq connection"""
    api_key = os.getenv("GROQ_API_KEY", "").strip()
    has_key = bool(api_key)
    ai_status = "not tested"
    ai_error = None

    if has_key:
        try:
            response_text = generate_ai_text(
                api_key,
                "Say 'Groq is working!' in exactly 3 words",
            )
            ai_status = (
                "working"
                if "Groq" in response_text
                else f"unexpected: {response_text}"
            )
        except Exception as e:
            ai_status = "error"
            ai_error = str(e)

    return {
        "api_key_present": has_key,
        "api_key_prefix": api_key[:10] + "..." if api_key else "",
        "provider": "groq",
        "model": GROQ_MODEL,
        "ai_status": ai_status,
        "ai_error": ai_error,
    }


@app.post("/api/insights")
def create_insights(payload: InsightRequest) -> dict[str, Any]:
    fallback = build_fallback(payload.snapshot)
    api_key = os.getenv("GROQ_API_KEY", "").strip()
    if not api_key:
        return fallback

    try:
        response_text = generate_ai_text(api_key, build_prompt(payload))
        parsed = parse_json_response(response_text)
        return normalize_response(parsed, fallback)
    except Exception as exc:
        fallback["source"] = "fallback-after-error"
        fallback["riskFlags"] = [
            *fallback.get("riskFlags", []),
            user_friendly_ai_error(exc),
        ]
        return fallback


@app.post("/api/scan-receipt")
async def scan_receipt(file: UploadFile = File(...)) -> dict[str, Any]:
    fallback = build_receipt_fallback()
    api_key = os.getenv("GROQ_API_KEY", "").strip()
    if not api_key:
        fallback["error"] = "AI receipt scanning is temporarily unavailable."
        fallback["debug"] = "Missing GROQ_API_KEY"
        return fallback

    try:
        image_bytes = await file.read()
        if not image_bytes:
            fallback["error"] = "No receipt image was uploaded."
            fallback["debug"] = "Uploaded image is empty"
            return fallback
        if len(image_bytes) > MAX_RECEIPT_IMAGE_BYTES:
            fallback["error"] = "Receipt image is too large. Please try a smaller photo."
            fallback["debug"] = (
                f"Image too large: {len(image_bytes)} bytes, "
                f"limit is {MAX_RECEIPT_IMAGE_BYTES} bytes"
            )
            return fallback

        mime_type = image_mime_type(file)
        encoded_image = base64.b64encode(image_bytes).decode("utf-8")
        response_text = generate_receipt_scan_text(
            api_key=api_key,
            base64_image=encoded_image,
            mime_type=mime_type,
        )
        parsed = parse_json_response(response_text)
        return normalize_receipt_response(parsed, fallback)
    except Exception as exc:
        fallback["source"] = "fallback-after-error"
        fallback["rateLimited"] = is_rate_limit_error(exc)
        fallback["error"] = user_friendly_receipt_error(exc)
        fallback["debug"] = sanitize_debug_error(exc)
        return fallback


def user_friendly_ai_error(exc: Exception) -> str:
    message = str(exc)
    if "429" in message or "RESOURCE_EXHAUSTED" in message:
        return "AI quota is temporarily unavailable, so FinWise used local guidance for this insight."
    return "AI guidance is temporarily unavailable, so FinWise used local guidance for this insight."


def is_rate_limit_error(exc: Exception) -> bool:
    message = str(exc)
    return "429" in message or "rate_limit" in message.lower() or "RESOURCE_EXHAUSTED" in message


def user_friendly_receipt_error(exc: Exception) -> str:
    if is_rate_limit_error(exc):
        return "AI is busy, try again in a minute"
    return "Receipt scanning is temporarily unavailable. Please enter the expense manually."


def generate_ai_text(api_key: str, prompt: str) -> str:
    client = Groq(api_key=api_key)
    response = client.chat.completions.create(
        model=GROQ_MODEL,
        messages=[
            {
                "role": "system",
                "content": (
                    "You are FinWise, a careful financial education assistant. "
                    "Return only valid JSON."
                ),
            },
            {"role": "user", "content": prompt},
        ],
        temperature=0.3,
        max_tokens=1200,
        response_format={"type": "json_object"},
    )
    return response.choices[0].message.content or ""


def generate_receipt_scan_text(
    api_key: str,
    base64_image: str,
    mime_type: str,
) -> str:
    client = Groq(api_key=api_key)
    response = client.chat.completions.create(
        model=GROQ_VISION_MODEL,
        messages=[
            {
                "role": "system",
                "content": (
                    "You are FinWise, a careful receipt extraction assistant. "
                    "Return only valid JSON."
                ),
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": build_receipt_prompt()},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{base64_image}",
                        },
                    },
                ],
            },
        ],
        temperature=0.1,
        max_tokens=800,
        response_format={"type": "json_object"},
    )
    return response.choices[0].message.content or ""


def build_prompt(payload: InsightRequest) -> str:
    snapshot = payload.snapshot.model_dump()
    user_name = str(payload.user.get("name") or "the user")
    return f"""
You are FinWise, an AI financial education assistant for students and young
professionals in Pakistan. Use the user's real expense-tracking metrics to
teach saving and investing. Be practical, kind, and specific.

Rules:
- Do not claim guaranteed returns.
- Keep advice educational, not formal financial advice.
- Mention SIP, compounding, budgeting, or emergency savings when relevant.
- Return only valid JSON matching this shape:
{{
  "summary": "2-4 sentence insight",
  "recommendations": ["3-5 concrete actions"],
  "investmentLessons": ["2-4 educational lessons"],
  "scenario": {{
    "monthlySaving": number,
    "assumedAnnualReturn": 0.12,
    "years": 10,
    "projectedAmount": number,
    "explanation": "short explanation"
  }},
  "riskFlags": ["optional warnings"],
  "source": "groq"
}}

User: {user_name}
Financial snapshot JSON:
{json.dumps(snapshot, ensure_ascii=False)}
""".strip()


def build_receipt_prompt() -> str:
    return """
Extract one expense transaction from this receipt for a Pakistan-first personal
finance app.

Rules:
- Use the final payable total as amount. If the receipt is not readable, use 0.
- Use PKR amounts when visible. Do not include currency symbols in amount.
- Use the merchant/store name as title when visible; otherwise use a short receipt title.
- Choose the closest category from: Dining, Groceries, Shopping, Transit, Entertainment, Bills, Health, Education, Fuel, Travel, Other.
- Return date as YYYY-MM-DD when visible; otherwise use an empty string.
- Return only valid JSON matching this shape:
{
  "title": "merchant or receipt title",
  "amount": number,
  "category": "category name",
  "date": "YYYY-MM-DD",
  "confidence": 0.0,
  "notes": "short note about what was extracted",
  "source": "groq-vision"
}
""".strip()


def parse_json_response(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()
    first = cleaned.find("{")
    last = cleaned.rfind("}")
    if first >= 0 and last > first:
        cleaned = cleaned[first : last + 1]
    return json.loads(cleaned)


def image_mime_type(file: UploadFile) -> str:
    content_type = (file.content_type or "").split(";")[0].lower().strip()
    if content_type in {"image/jpeg", "image/jpg", "image/png", "image/webp"}:
        return "image/jpeg" if content_type == "image/jpg" else content_type

    suffix = Path(file.filename or "").suffix.lower()
    if suffix in {".jpg", ".jpeg"}:
        return "image/jpeg"
    if suffix == ".png":
        return "image/png"
    if suffix == ".webp":
        return "image/webp"
    return "image/jpeg"


def normalize_response(parsed: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    scenario = parsed.get("scenario") if isinstance(parsed.get("scenario"), dict) else {}
    return {
        "summary": string_or(parsed.get("summary"), fallback["summary"]),
        "recommendations": string_list_or(
            parsed.get("recommendations"), fallback["recommendations"]
        ),
        "investmentLessons": string_list_or(
            parsed.get("investmentLessons"), fallback["investmentLessons"]
        ),
        "scenario": {
            "monthlySaving": number_or(
                scenario.get("monthlySaving"), fallback["scenario"]["monthlySaving"]
            ),
            "assumedAnnualReturn": number_or(
                scenario.get("assumedAnnualReturn"),
                fallback["scenario"]["assumedAnnualReturn"],
            ),
            "years": int(number_or(scenario.get("years"), fallback["scenario"]["years"])),
            "projectedAmount": number_or(
                scenario.get("projectedAmount"), fallback["scenario"]["projectedAmount"]
            ),
            "explanation": string_or(
                scenario.get("explanation"), fallback["scenario"]["explanation"]
            ),
        },
        "riskFlags": string_list_or(parsed.get("riskFlags"), fallback["riskFlags"]),
        "source": "groq",
    }


def normalize_receipt_response(
    parsed: dict[str, Any],
    fallback: dict[str, Any],
) -> dict[str, Any]:
    return {
        "title": string_or(parsed.get("title"), fallback["title"]),
        "amount": max(number_or(parsed.get("amount"), fallback["amount"]), 0),
        "category": string_or(parsed.get("category"), fallback["category"]),
        "date": date_or_empty(parsed.get("date")),
        "confidence": max(min(number_or(parsed.get("confidence"), 0), 1), 0),
        "notes": string_or(parsed.get("notes"), fallback["notes"]),
        "source": "groq-vision",
        "error": None,
        "rateLimited": False,
    }


def build_fallback(snapshot: FinancialSnapshot) -> dict[str, Any]:
    top_category = (
        snapshot.topCategories[0].name
        if snapshot.topCategories
        else "your largest spending category"
    )
    monthly_saving = max(snapshot.savings, 0)
    projected = future_value_monthly(monthly_saving)
    savings_rate = snapshot.savingsRate * 100 if math.isfinite(snapshot.savingsRate) else 0
    risk_flags: list[str] = []
    if snapshot.savings < 0:
        risk_flags.append("Expenses are higher than income this month.")
    for budget in snapshot.budgetStatuses:
        if budget.percentUsed > 1:
            risk_flags.append(f"{budget.name} is over budget.")

    return {
        "summary": (
            f"You saved {savings_rate:.1f}% of your income this month. "
            f"The biggest spending pressure is {top_category}, so a small habit "
            "change there can improve your investment capacity."
        ),
        "recommendations": [
            f"Review {top_category} and set a weekly reduction target.",
            "Move savings first, then spend from the remaining balance.",
            "Turn your monthly surplus into a simple SIP-style investing habit.",
            "Compare this month with next month to see whether the change worked.",
        ],
        "investmentLessons": [
            "Compounding rewards consistency more than one-time large investments.",
            "A SIP spreads investment timing risk by investing a fixed amount regularly.",
            "Emergency savings should come before higher-risk investing.",
        ],
        "scenario": {
            "monthlySaving": monthly_saving,
            "assumedAnnualReturn": 0.12,
            "years": 10,
            "projectedAmount": projected,
            "explanation": (
                "This projection uses monthly contributions and an assumed 12% "
                "annual return to show how regular saving can compound over time."
            ),
        },
        "riskFlags": risk_flags,
        "source": "fallback",
    }


def build_receipt_fallback() -> dict[str, Any]:
    return {
        "title": "Receipt",
        "amount": 0,
        "category": "Other",
        "date": "",
        "confidence": 0,
        "notes": "",
        "source": "fallback",
        "error": None,
        "debug": None,
        "rateLimited": False,
    }


def future_value_monthly(monthly_saving: float, annual_return: float = 0.12, years: int = 10) -> float:
    if monthly_saving <= 0:
        return 0
    monthly_rate = annual_return / 12
    value = 0.0
    for _ in range(years * 12):
        value = (value + monthly_saving) * (1 + monthly_rate)
    return round(value, 2)


def string_or(value: Any, fallback: str) -> str:
    text = str(value or "").strip()
    return text or fallback


def string_list_or(value: Any, fallback: list[str]) -> list[str]:
    if not isinstance(value, list):
        return fallback
    cleaned = [str(item).strip() for item in value if str(item).strip()]
    return cleaned or fallback


def date_or_empty(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    candidate = text[:10]
    try:
        datetime.fromisoformat(candidate)
        return candidate
    except ValueError:
        return ""


def sanitize_debug_error(exc: Exception) -> str:
    message = str(exc).strip()
    if not message:
        return "Unknown scanner error"
    message = message.replace(os.getenv("GROQ_API_KEY", "").strip(), "***")
    if len(message) > 280:
        return message[:280] + "..."
    return message


def number_or(value: Any, fallback: float) -> float:
    try:
        number = float(value)
        return number if math.isfinite(number) else fallback
    except (TypeError, ValueError):
        return fallback
