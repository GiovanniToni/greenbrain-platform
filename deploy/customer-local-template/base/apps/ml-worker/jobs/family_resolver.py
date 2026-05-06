import sqlalchemy as sa


ALIASES = {
    'photos': 'pothos',
}

def resolve_family_and_slug(engine, family_or_slug: str) -> tuple[str, str]:
    # alias common typos
    try:
        family_or_slug = (family_or_slug or '').strip().lower()
    except Exception:
        pass
    family_or_slug = ALIASES.get(family_or_slug, family_or_slug)
    """
    Input può essere:
      - famiglia (nome umano) es: "abete corona"
      - famiglia_slug canonico es: "abete-corona"
    Output sempre: (famiglia, famiglia_slug)
    """
    x = (family_or_slug or "").strip().lower()
    if not x:
        raise ValueError("family_or_slug vuoto")

    q = sa.text("""
        select famiglia, famiglia_slug
        from public.famiglie_catalog_static
        where lower(famiglia) = :x
           or lower(famiglia_slug) = :x
        limit 1
    """)
    with engine.connect() as conn:
        row = conn.execute(q, {"x": x}).fetchone()

    if row and row[0] and row[1]:
        return str(row[0]).strip().lower(), str(row[1]).strip().lower()

    # fallback compat
    fam = x
    slug = x.replace(" ", "-")
    return fam, slug
