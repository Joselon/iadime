from typing import List

def render_markdown_to_html(text: str) -> str:
    def escape_html(value: str) -> str:
        return (value or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    lines = (text or "").splitlines()
    html_lines: List[str] = []
    in_code = False
    in_mermaid = False
    code_buffer: List[str] = []
    code_language = ""

    def flush_code() -> None:
        nonlocal in_code, in_mermaid, code_buffer, code_language
        if not in_code:
            return
        code_text = "\n".join(code_buffer)
        if in_mermaid:
            html_lines.append(f'<div class="mermaid">{escape_html(code_text)}</div>')
        else:
            lang_attr = f' class="language-{code_language}"' if code_language else ""
            html_lines.append(f'<pre><code{lang_attr}>{escape_html(code_text)}</code></pre>')
        code_buffer = []
        code_language = ""
        in_code = False
        in_mermaid = False

    for line in lines:
        if line.startswith("```mermaid"):
            flush_code()
            in_code = True
            in_mermaid = True
            continue
        if line.startswith("```"):
            if in_code:
                flush_code()
            else:
                in_code = True
                in_mermaid = False
                code_language = line[3:].strip()
            continue
        if in_code:
            code_buffer.append(line)
            continue
        if line.startswith("### "):
            html_lines.append(f"<h3>{escape_html(line[4:])}</h3>")
        elif line.startswith("## "):
            html_lines.append(f"<h2>{escape_html(line[3:])}</h2>")
        elif line.startswith("# "):
            html_lines.append(f"<h1>{escape_html(line[2:])}</h1>")
        else:
            html_lines.append(f"<p>{escape_html(line)}</p>")

    flush_code()
    return "\n".join(html_lines)
