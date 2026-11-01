#!/usr/bin/env python3
"""
LMPE ARM64 APT Repository - Web Catalog Generator
Generates a static, interactive, searchable index.html for GitHub Pages.
"""

import sys
import os
import gzip
import html
import datetime

def format_size(bytes_val):
    try:
        b = int(bytes_val)
        for unit in ['B', 'KB', 'MB', 'GB']:
            if b < 1024 or unit == 'GB':
                return f"{b:.1f} {unit}" if unit != 'B' else f"{b} B"
            b /= 1024
    except Exception:
        return str(bytes_val)

def parse_packages_data(data):
    pkgs = []
    for block in data.strip().split("\n\n"):
        p = {}
        lines = block.split("\n")
        i = 0
        while i < len(lines):
            line = lines[i]
            if ":" in line and not line.startswith(" "):
                k, v = line.split(":", 1)
                k = k.strip().lower()
                v = v.strip()
                if k == "description":
                    p[k] = v
                    i += 1
                    while i < len(lines) and lines[i].startswith(" "):
                        i += 1
                    continue
                else:
                    p[k] = v
            i += 1
        if "package" in p:
            pkgs.append(p)
    return pkgs

def get_packages(repo_dir):
    packages_gz = os.path.join(repo_dir, "dists", "gigi", "main", "binary-arm64", "Packages.gz")
    packages_txt = os.path.join(repo_dir, "dists", "gigi", "main", "binary-arm64", "Packages")

    if os.path.exists(packages_gz):
        with gzip.open(packages_gz, "rt", encoding="utf-8", errors="ignore") as f:
            return parse_packages_data(f.read())
    elif os.path.exists(packages_txt):
        with open(packages_txt, "r", encoding="utf-8", errors="ignore") as f:
            return parse_packages_data(f.read())
    else:
        # Fallback to pool scan
        pool_dir = os.path.join(repo_dir, "pool", "main")
        pkgs = []
        if os.path.isdir(pool_dir):
            for deb in sorted(os.listdir(pool_dir)):
                if deb.endswith(".deb"):
                    parts = deb[:-4].split("_")
                    name = parts[0] if len(parts) > 0 else deb
                    ver = parts[1] if len(parts) > 1 else ""
                    arch = parts[2] if len(parts) > 2 else "arm64"
                    size = os.path.getsize(os.path.join(pool_dir, deb))
                    pkgs.append({
                        "package": name,
                        "version": ver,
                        "architecture": arch,
                        "size": size,
                        "filename": f"pool/main/{deb}",
                        "description": "LMPE ARM64 package"
                    })
        return pkgs

def generate_html(repo_dir):
    pkgs = get_packages(repo_dir)
    pkgs.sort(key=lambda x: x.get("package", "").lower())

    total_pkgs = len(pkgs)
    total_bytes = sum(int(p.get("size", 0)) for p in pkgs)
    total_size = format_size(total_bytes)
    now_utc = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    # Generate rows
    rows_html = []
    for p in pkgs:
        name = html.escape(p.get("package", ""))
        ver = html.escape(p.get("version", ""))
        arch = html.escape(p.get("architecture", "arm64"))
        size_str = format_size(p.get("size", 0))
        desc = html.escape(p.get("description", ""))
        fn = html.escape(p.get("filename", f"pool/main/{name}_{ver}_{arch}.deb"))

        search_text = html.escape(f"{name} {desc} {arch}".lower(), quote=True)

        rows_html.append(f"""          <tr data-search="{search_text}">
            <td>
              <div class="pkg-name">{name}</div>
              {f'<div class="pkg-desc">{desc}</div>' if desc else ''}
            </td>
            <td><code class="pkg-ver">{ver}</code></td>
            <td><span class="pkg-arch">{arch}</span></td>
            <td><span class="pkg-size">{size_str}</span></td>
            <td><a href="{fn}" class="btn-dl" download>⬇️ .deb</a></td>
          </tr>""")

    tbody_content = "\n".join(rows_html)

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LMPE ARM64 APT Repository — Gigi (Pi 5 & CM5)</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🍃</text></svg>">
  <style>
    :root {{
      --bg: #090d13;
      --card-bg: #121820;
      --border: #232d38;
      --text: #e6edf3;
      --text-muted: #8b949e;
      --mint: #87cf3e;
      --mint-glow: rgba(135, 207, 62, 0.12);
      --mint-dark: #5fb336;
      --code-bg: #05080c;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background-color: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      padding: 2.5rem 1rem;
      line-height: 1.5;
    }}
    .container {{ max-width: 1180px; margin: 0 auto; }}
    header {{ text-align: center; margin-bottom: 2.5rem; }}
    .logo {{ font-size: 3.5rem; margin-bottom: 0.5rem; display: inline-block; }}
    h1 {{ font-size: 2.2rem; font-weight: 700; color: #fff; margin-bottom: 0.4rem; }}
    h1 span {{ color: var(--mint); }}
    .subtitle {{ color: var(--text-muted); font-size: 1.05rem; max-width: 700px; margin: 0 auto 1.25rem; }}
    .badges {{ display: flex; gap: 0.5rem; justify-content: center; flex-wrap: wrap; margin-bottom: 1.5rem; }}
    .badge {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      padding: 0.3rem 0.85rem;
      border-radius: 9999px;
      font-size: 0.82rem;
      font-weight: 500;
      color: var(--text-muted);
    }}
    .badge.highlight {{
      border-color: var(--mint);
      color: var(--mint);
      background: var(--mint-glow);
    }}
    .card {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 1.25rem 1.5rem;
      margin-bottom: 1.75rem;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.25);
    }}
    .card-title {{
      font-size: 1.05rem;
      font-weight: 600;
      margin-bottom: 0.85rem;
      color: #fff;
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }}
    pre.code-block {{
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1rem 1.25rem;
      overflow-x: auto;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
      font-size: 0.88rem;
      color: #8be9fd;
      position: relative;
      line-height: 1.6;
    }}
    .code-comment {{ color: #6272a4; }}
    .copy-btn {{
      position: absolute;
      top: 0.75rem;
      right: 0.75rem;
      background: var(--card-bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 0.35rem 0.75rem;
      border-radius: 6px;
      font-size: 0.75rem;
      cursor: pointer;
      font-weight: 500;
      transition: all 0.2s;
    }}
    .copy-btn:hover {{ border-color: var(--mint); color: var(--mint); }}
    .toolbar {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 1rem;
      margin-bottom: 1rem;
      flex-wrap: wrap;
    }}
    .search-wrapper {{
      position: relative;
      flex: 1;
      min-width: 280px;
    }}
    .search-input {{
      width: 100%;
      background: var(--card-bg);
      border: 1px solid var(--border);
      color: var(--text);
      padding: 0.75rem 1rem 0.75rem 2.4rem;
      border-radius: 8px;
      font-size: 0.95rem;
      outline: none;
      transition: border-color 0.2s, box-shadow 0.2s;
    }}
    .search-input:focus {{
      border-color: var(--mint);
      box-shadow: 0 0 0 3px var(--mint-glow);
    }}
    .search-icon {{
      position: absolute;
      left: 0.85rem;
      top: 50%;
      transform: translateY(-50%);
      color: var(--text-muted);
      font-size: 0.9rem;
      pointer-events: none;
    }}
    .count-label {{
      color: var(--text-muted);
      font-size: 0.88rem;
      font-variant-numeric: tabular-nums;
    }}
    .table-container {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      overflow-x: auto;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.25);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      text-align: left;
      font-size: 0.9rem;
    }}
    th {{
      background: rgba(5, 8, 12, 0.6);
      padding: 0.85rem 1.1rem;
      color: var(--text-muted);
      font-weight: 600;
      border-bottom: 1px solid var(--border);
      text-transform: uppercase;
      font-size: 0.75rem;
      letter-spacing: 0.05em;
    }}
    td {{
      padding: 0.85rem 1.1rem;
      border-bottom: 1px solid rgba(35, 45, 56, 0.6);
      vertical-align: middle;
    }}
    tr:last-child td {{ border-bottom: none; }}
    tr:hover td {{ background: rgba(255, 255, 255, 0.02); }}
    .pkg-name {{
      font-weight: 600;
      color: #fff;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", monospace;
      font-size: 0.95rem;
    }}
    .pkg-desc {{
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-top: 0.2rem;
      line-height: 1.35;
    }}
    .pkg-ver {{
      font-family: ui-monospace, SFMono-Regular, "SF Mono", monospace;
      font-size: 0.82rem;
      color: #8be9fd;
    }}
    .pkg-arch {{
      display: inline-block;
      padding: 0.15rem 0.5rem;
      border-radius: 4px;
      font-size: 0.75rem;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", monospace;
      background: var(--mint-glow);
      color: var(--mint);
      border: 1px solid rgba(135, 207, 62, 0.25);
    }}
    .pkg-size {{
      color: var(--text-muted);
      font-family: ui-monospace, SFMono-Regular, "SF Mono", monospace;
      font-size: 0.82rem;
      white-space: nowrap;
    }}
    .btn-dl {{
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
      padding: 0.4rem 0.85rem;
      border-radius: 6px;
      background: var(--border);
      color: var(--text);
      text-decoration: none;
      font-size: 0.8rem;
      font-weight: 500;
      transition: all 0.2s;
      white-space: nowrap;
    }}
    .btn-dl:hover {{
      background: var(--mint);
      color: #090d13;
      transform: translateY(-1px);
    }}
    footer {{
      text-align: center;
      margin-top: 2.5rem;
      color: var(--text-muted);
      font-size: 0.85rem;
    }}
    footer a {{ color: var(--mint); text-decoration: none; }}
    footer a:hover {{ text-decoration: underline; }}
    kbd {{
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 4px;
      padding: 0.1rem 0.4rem;
      font-size: 0.75rem;
      color: var(--text-muted);
    }}
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="logo">🍃</div>
      <h1>LMPE <span>ARM64</span> Repository</h1>
      <p class="subtitle">Official Debian 13 (Trixie) &amp; Linux Mint (Gigi) package repository optimized with Cortex-A76 microarchitecture tuning for Raspberry Pi 5 and Compute Module 5.</p>
      <div class="badges">
        <span class="badge highlight">Suite: gigi</span>
        <span class="badge highlight">Component: main</span>
        <span class="badge">Arch: arm64 &amp; all</span>
        <span class="badge">Packages: {total_pkgs}</span>
        <span class="badge">Pool Size: {total_size}</span>
        <span class="badge">Updated: {now_utc}</span>
      </div>
    </header>

    <div class="card">
      <div class="card-title">🚀 Quick Setup Instructions</div>
      <pre class="code-block"><button class="copy-btn" onclick="copySetup()">Copy</button><code id="setup-cmd"><span class="code-comment"># 1. Download and install LMPE GPG keyring</span>
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://gamingtux.github.io/lmde-arm64/lmde-arm64.gpg -o /etc/apt/keyrings/lmde-arm64.gpg

<span class="code-comment"># 2. Add LMPE APT repository source</span>
echo "deb [signed-by=/etc/apt/keyrings/lmde-arm64.gpg] https://gamingtux.github.io/lmde-arm64 gigi main" | sudo tee /etc/apt/sources.list.d/lmpe.list

<span class="code-comment"># 3. Update package index</span>
sudo apt update</code></pre>
    </div>

    <div class="toolbar">
      <div class="search-wrapper">
        <span class="search-icon">🔍</span>
        <input type="text" id="pkg-search" class="search-input" placeholder="Search packages (e.g. cinnamon, nemo, timeshift, ffmpeg)... Press / to focus" oninput="filterPackages()">
      </div>
      <div class="count-label" id="pkg-count">Showing {total_pkgs} of {total_pkgs} packages</div>
    </div>

    <div class="table-container">
      <table id="pkg-table">
        <thead>
          <tr>
            <th>Package</th>
            <th>Version</th>
            <th>Architecture</th>
            <th>Size</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
{tbody_content}
        </tbody>
      </table>
    </div>

    <footer>
      <p>LMPE (Linux Mint Pi Edition) • Built with ❤️ for Raspberry Pi 5 &amp; CM5 • <a href="https://github.com/GamingTux/lmde-arm64" target="_blank" rel="noopener">GitHub Repository</a></p>
    </footer>
  </div>

  <script>
    function filterPackages() {{
      const query = document.getElementById('pkg-search').value.toLowerCase().trim();
      const rows = document.querySelectorAll('#pkg-table tbody tr');
      let visible = 0;
      rows.forEach(row => {{
        const text = row.getAttribute('data-search') || '';
        if (!query || text.includes(query)) {{
          row.style.display = '';
          visible++;
        }} else {{
          row.style.display = 'none';
        }}
      }});
      document.getElementById('pkg-count').textContent = `Showing ${{visible}} of ${{rows.length}} packages`;
    }}

    function copySetup() {{
      const text = `sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://gamingtux.github.io/lmde-arm64/lmde-arm64.gpg -o /etc/apt/keyrings/lmde-arm64.gpg
echo "deb [signed-by=/etc/apt/keyrings/lmde-arm64.gpg] https://gamingtux.github.io/lmde-arm64 gigi main" | sudo tee /etc/apt/sources.list.d/lmpe.list
sudo apt update`;
      navigator.clipboard.writeText(text).then(() => {{
        const btn = document.querySelector('.copy-btn');
        btn.textContent = 'Copied!';
        setTimeout(() => btn.textContent = 'Copy', 2000);
      }});
    }}

    document.addEventListener('keydown', (e) => {{
      if (e.key === '/' && document.activeElement !== document.getElementById('pkg-search')) {{
        e.preventDefault();
        document.getElementById('pkg-search').focus();
      }}
    }});
  </script>
</body>
</html>
"""

    out_file = os.path.join(repo_dir, "index.html")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(html_content)

    print(f"Generated {out_file} with {total_pkgs} packages ({total_size})")

if __name__ == "__main__":
    target_repo = sys.argv[1] if len(sys.argv) > 1 else "./repo"
    generate_html(target_repo)
