#!/usr/bin/env python3
"""Fetch daily news from topurl.cn API."""

import json
import urllib.request
import urllib.error
import sys

API_URL = "https://news.topurl.cn/api"

def fetch_news(ip="202.106.0.20"):
    """
    Fetch news from the API.

    Args:
        ip: IP address for weather location (default: 202.106.0.20 - gets full dataset)

    Returns:
        dict: Parsed JSON response with full news list

    Note:
        Using ip=202.106.0.20 is the "magic key" to get complete news dataset.
        Category filtering should be done locally, not via API.
    """
    params = []
    if ip:
        params.append(f"ip={ip}")
    
    url = API_URL
    if params:
        url += "?" + "&".join(params)
    
    try:
        req = urllib.request.Request(
            url,
            headers={
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read().decode('utf-8')
            return json.loads(data)
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP Error {e.code}: {e.reason}"}
    except urllib.error.URLError as e:
        return {"error": f"URL Error: {e.reason}"}
    except json.JSONDecodeError as e:
        return {"error": f"JSON Decode Error: {e}"}
    except Exception as e:
        return {"error": f"Error: {e}"}

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description='Fetch daily news from topurl.cn')
    parser.add_argument('--ip', default='202.106.0.20', help='IP address (default: 202.106.0.20 for full dataset)')
    args = parser.parse_args()

    result = fetch_news(ip=args.ip)
    print(json.dumps(result, ensure_ascii=False, indent=2))