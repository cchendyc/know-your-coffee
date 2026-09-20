import unicodedata

_ALNUM = set("abcdefghijklmnopqrstuvwxyz0123456789")


def norm_name(name: str) -> str:
    """"Caffè" and "Caffe" must normalize identically, so strip diacritics
    (NFKD) before dropping non-alphanumerics."""
    decomposed = unicodedata.normalize("NFKD", name)
    return "".join(c for c in decomposed.lower() if c in _ALNUM)


def is_same_shop(a: dict, b: dict) -> bool:
    return (
        norm_name(a["name"]) == norm_name(b["name"])
        and abs(a["lat"] - b["lat"]) < 0.003
        and abs(a["lng"] - b["lng"]) < 0.004
    )
