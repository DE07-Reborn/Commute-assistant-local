import os
import json
import re
import requests
import pandas as pd

class aladin_api_utils:
    
    BASE_URL = "https://www.aladin.co.kr/ttb/api/ItemList.aspx"
    VERSION = "20131101"

    def __init__(self):
        self.ttbkey = os.getenv("ALADIN_KEY")
        if not self.ttbkey:
            raise ValueError("ALADIN_KEY not set")

        self.timeout = 10

    def _safe_json_loads(self, text: str) -> dict | None:
        try:
            # 제어문자(깨진 JSON 발생) 제거
            cleaned = re.sub(r"[\x00-\x1f\x7f]", "", text)
            return json.loads(cleaned)
        except Exception as e:
            print("JSON parse failed")
            print(text[:500])
            print(e)
            return None

    def fetch_bestseller(self, start: int, max_results: int) -> pd.DataFrame:
        params = {
            "ttbkey": self.ttbkey,
            "QueryType": "Bestseller",
            "SearchTarget": "Book",
            "start": start,
            "MaxResults": max_results,
            "output": "JS",
            "Version": self.VERSION,
            "OptResult": "ebookList"
        }

        res = requests.get(self.BASE_URL, params=params, timeout=self.timeout)
        res.raise_for_status()

        data = self._safe_json_loads(res.text)
        if not data:
            # 페이지 단위로 그냥 스킵
            return pd.DataFrame()

        items = data.get("item", [])
        return pd.DataFrame(items)
