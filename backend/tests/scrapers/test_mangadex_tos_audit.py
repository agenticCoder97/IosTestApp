"""
Static guard: every download_image call path in mangadex.py must invoke
post_json (the MD@Home report). Prevents future refactors from silently
dropping the ToS-required report.
"""
import ast
import pathlib

MANGADEX_PY = pathlib.Path(__file__).resolve().parents[2] / "app" / "scrapers" / "comic" / "mangadex.py"


def _get_func(tree: ast.AST, class_name: str, method_name: str) -> ast.FunctionDef:
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == class_name:
            for item in node.body:
                if isinstance(item, ast.AsyncFunctionDef) and item.name == method_name:
                    return item
    raise AssertionError(f"{class_name}.{method_name} not found in {MANGADEX_PY}")


def _calls_to(func: ast.FunctionDef, attr: str) -> list[ast.Call]:
    return [
        node for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == attr
    ]


def test_download_image_calls_post_json_in_both_branches():
    tree = ast.parse(MANGADEX_PY.read_text())
    fn = _get_func(tree, "MangadexScraper", "download_image")

    # Find the try block; assert post_json is called inside both the try (success)
    # and except (failure) branches.
    try_blocks = [n for n in ast.walk(fn) if isinstance(n, ast.Try)]
    assert try_blocks, "download_image must use try/except for report POST"
    tb = try_blocks[0]

    success_posts = [
        c for n in tb.body for c in ast.walk(n)
        if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
        and c.func.attr == "post_json"
    ]
    failure_posts = [
        c for handler in tb.handlers for n in handler.body for c in ast.walk(n)
        if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
        and c.func.attr == "post_json"
    ]
    assert success_posts, "post_json missing on success branch of download_image"
    assert failure_posts, "post_json missing on failure branch of download_image"
