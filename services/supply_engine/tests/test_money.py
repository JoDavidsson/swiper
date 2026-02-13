from app.extractor.money import parse_money_sv


def test_parse_money_sv_common_formats():
    assert parse_money_sv("12 995 kr").amount == 12995
    assert parse_money_sv("12 995 kr").currency == "SEK"
    assert parse_money_sv("12\u00a0995 kr").amount == 12995  # nbsp
    assert parse_money_sv("12.995 kr").amount == 12995
    assert parse_money_sv("12 995:-").amount == 12995
    assert parse_money_sv("12 995:-").currency is None
    assert parse_money_sv("12 995 SEK").amount == 12995
    assert parse_money_sv("12 995 SEK").currency == "SEK"
    assert parse_money_sv("12 995,00 kr").amount == 12995.0


def test_parse_money_sv_dot_decimal_vs_thousand():
    # Thousand grouping when exactly 3 digits after dot
    assert parse_money_sv("1.234 kr").amount == 1234
    # Decimal when not 3 digits after dot
    assert parse_money_sv("12.50 kr").amount == 12.5


def test_parse_money_sv_unparseable():
    out = parse_money_sv("Pris på förfrågan")
    assert out.amount is None
    assert "unparseable" in out.warnings
