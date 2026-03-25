#!/usr/bin/env python3
"""
深度阅读文章抓取脚本
功能: 伪装微信浏览器抓取 URL → HTML 清理 → Markdown 转换
依赖: requests, beautifulsoup4, markdownify
用法: python fetch_article.py <url>
"""

import sys
import re
import os
import subprocess

# 全局导入（check_dependencies 会在运行时确保依赖已安装）
import requests
from bs4 import BeautifulSoup
from markdownify import markdownify


def check_dependencies():
    """检测并安装缺失依赖（运行时兜底）"""
    try:
        import requests  # noqa: F401
        from bs4 import BeautifulSoup  # noqa: F401
        from markdownify import markdownify  # noqa: F401
    except ImportError:
        print("Installing dependencies...", file=sys.stderr)
        subprocess.check_call([sys.executable, "-m", "pip", "install",
                               "-q", "requests", "beautifulsoup4", "markdownify"])

def fetch_html(url):
    """抓取 HTML，伪装微信浏览器"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) WindowsWechat(0x63090a13) UnifiedPCWindowsWechat(0xf254101f) XWEB/16389 SideBar Flue',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        # 不主动请求 gzip/deflate/br 压缩，避免 requests 自动解压失败导致二进制垃圾
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
        'Referer': 'https://www.bing.com/'
    }
    
    response = requests.get(url, headers=headers, timeout=15)
    response.raise_for_status()

    # 返回原始 bytes，由 extract_body 中的 BeautifulSoup 负责编码检测。
    # 微信等站点 meta charset 声明 UTF-8 但正文实际为 GBK，
    # BeautifulSoup 的 UnicodeDammit 会尽量智能处理混合编码。
    return response.content

def extract_body(html):
    """提取 body 内容，减少无关噪音"""
    from bs4 import BeautifulSoup
    if isinstance(html, bytes):
        # 让 BS4 检测编码后解码为 str，避免 bytes 被当作 str 处理
        dammit = BeautifulSoup(html, 'html.parser')
        encoding = dammit.original_encoding or 'utf-8'
        html = html.decode(encoding, errors='replace')
    soup = BeautifulSoup(html, 'html.parser')

    # 移除干扰元素
    for tag in soup.find_all(['script', 'style', 'noscript', 'iframe', 
                               'nav', 'header', 'footer', 'aside', 'menu',
                               'svg', 'canvas', 'form', 'button']):
        tag.decompose()
    
    # 移除注释
    for comment in soup.find_all(string=lambda text: isinstance(text, str) and text.strip().startswith('<!--')):
        comment.extract()
    
    # 尝试提取 article 或 main
    body = soup.find('article') or soup.find('main') or soup.find('body')
    return str(body) if body else html  # noqa: R502

def clean_html_to_markdown(html_content):
    """清理 HTML 属性，转换为 Markdown"""
    from bs4 import BeautifulSoup
    from markdownify import markdownify
    
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # 保留语义标签的 class/id（可选，markdownify 会保留部分）
    # 移除所有行内样式和数据属性
    for tag in soup.find_all(True):
        if tag.attrs is None:
            continue
        attrs_to_remove = ['style', 'data-', 'class', 'id', 'onclick',
                           'onload', 'onerror', 'rel', 'target']
        for attr in attrs_to_remove:
            if attr == 'data-':
                [tag.attrs.pop(k) for k in list(tag.attrs.keys()) if k.startswith('data-')]
            elif attr in tag.attrs:
                del tag.attrs[attr]
        
        # 清理空标签（保留换行结构）
        if tag.name in ['div', 'span'] and not tag.get_text(strip=True):
            tag.decompose()
    
    # 转换为 Markdown
    md = markdownify(
        str(soup),
        heading_style="ATX",
        bullets="-",
        links=True,
        images=True,
        code_language_ticks=False
    )
    
    return md

def cleanup_markdown(md):
    """清理 Markdown 中的冗余"""
    # 移除空链接
    md = re.sub(r'\[([^\]]+)\]\(\s*\)', r'\1', md)
    
    # 清理多余空行
    md = re.sub(r'\n{4,}', '\n\n\n', md)
    
    # 移除只有空格的行
    lines = [line.rstrip() for line in md.split('\n')]
    md = '\n'.join(line for line in lines if line.strip() or line == '')
    
    # 截断超长内容（保留前 48000 字符，留空间给上下文）
    if len(md) > 48000:
        md = md[:48000] + '\n\n... (内容过长，已截断)'
    
    return md.strip()

def main():
    # 强制 stdout 为 UTF-8，避免 Windows GBK 控制台导致中文输出乱码
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

    if len(sys.argv) < 2:
        print("Usage: python fetch_article.py <url>", file=sys.stderr)
        sys.exit(1)
    
    url = sys.argv[1]
    
    # 验证 URL
    if not re.match(r'^https?://', url):
        print("Error: Invalid URL", file=sys.stderr)
        sys.exit(1)
    
    try:
        # 检测依赖（运行时兜底安装）
        check_dependencies()

        # 抓取
        html = fetch_html(url)
        
        # 提取 body
        body = extract_body(html)
        
        # 转换 Markdown
        md = clean_html_to_markdown(body)
        
        # 清理
        md = cleanup_markdown(md)
        
        # 输出
        print(md)
        
    except subprocess.CalledProcessError as e:
        print(f"Failed to install dependencies: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()