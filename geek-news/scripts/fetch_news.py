#!/usr/bin/env python3
"""Fetch geek news from geek.keyi.ma API."""

import json
import urllib.request
import urllib.error

API_URL = "https://geek.keyi.ma/api/news"


def fetch_news():
    """
    Fetch news from the geek.keyi.ma API.

    Returns:
        dict: Parsed JSON response with news data
    """
    try:
        req = urllib.request.Request(
            API_URL,
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
    result = fetch_news()
    print(json.dumps(result, ensure_ascii=False, indent=2))
