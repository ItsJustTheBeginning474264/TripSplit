"""Money helpers.

All calculations are done in integer *cents* (paise) so that rounding errors can never
make a split total differ from the expense amount. Decimals are only used at the edges
(parsing requests, formatting responses).
"""
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from errors import ValidationError

MAX_AMOUNT_CENTS = 9_999_999_999  # 99,999,999.99 - fits DECIMAL(12,2) with room to spare
_TWO_PLACES = Decimal("0.01")


def _to_decimal(value, field):
    if value is None or isinstance(value, bool):
        raise ValidationError(f"{field} is required and must be a number")
    try:
        d = Decimal(str(value).strip())
    except (InvalidOperation, ValueError):
        raise ValidationError(f"{field} must be a valid number")
    if not d.is_finite():
        raise ValidationError(f"{field} must be a valid number")
    return d


def parse_amount(value, field="amount", allow_zero=False):
    """Parse a rupee amount (max 2 decimals) and return it as integer cents."""
    d = _to_decimal(value, field)
    if abs(d) > Decimal(MAX_AMOUNT_CENTS) / 100:
        raise ValidationError(f"{field} is too large")
    if d != d.quantize(_TWO_PLACES):
        raise ValidationError(f"{field} can have at most 2 decimal places")
    cents = int((d * 100).to_integral_value(ROUND_HALF_UP))
    if cents < 0:
        raise ValidationError(f"{field} cannot be negative")
    if cents == 0 and not allow_zero:
        raise ValidationError(f"{field} must be greater than zero")
    return cents


def parse_percentage(value, field="percentage"):
    """Parse a percentage in the range (0, 100] with at most 2 decimals."""
    d = _to_decimal(value, field)
    if d != d.quantize(_TWO_PLACES):
        raise ValidationError(f"{field} can have at most 2 decimal places")
    if d <= 0:
        raise ValidationError(f"{field} must be greater than zero")
    if d > 100:
        raise ValidationError(f"{field} cannot be more than 100")
    return d


def to_decimal(cents):
    """Integer cents -> Decimal rupees with two places."""
    return (Decimal(cents) / 100).quantize(_TWO_PLACES)


def cents_from_db(value):
    """Convert a DB numeric (Decimal from MySQL, float/int from SQLite) to integer cents."""
    if value is None:
        return 0
    return int((Decimal(str(value)) * 100).to_integral_value(ROUND_HALF_UP))


def dec_from_db(value):
    """Convert a DB numeric to a Decimal with two places (for JSON output)."""
    return to_decimal(cents_from_db(value))
