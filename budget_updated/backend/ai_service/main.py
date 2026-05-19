import json
import math
import os
from pathlib import Path
from typing import Any

from groq import Groq
from fastapi import FastAPI
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


def user_friendly_ai_error(exc: Exception) -> str:
    message = str(exc)
    if "429" in message or "RESOURCE_EXHAUSTED" in message:
        return "AI quota is temporarily unavailable, so FinWise used local guidance for this insight."
    return "AI guidance is temporarily unavailable, so FinWise used local guidance for this insight."


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
        max_completion_tokens=1200,
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


def number_or(value: Any, fallback: float) -> float:
    try:
        number = float(value)
        return number if math.isfinite(number) else fallback
    except (TypeError, ValueError):
        return fallback
