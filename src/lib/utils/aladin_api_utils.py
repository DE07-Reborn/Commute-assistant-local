import os
import requests
import pandas as pd

class aladin_api_utils:
    
    BASE_URL = "https://www.aladin.co.kr/ttb/api/ItemList.aspx"
    VERSION = "20131101"    # API 최신버전: 20131101
    
    def __init__(self):
        self.ttbkey = os.getenv("ALADIN_KEY")
        if not self.ttbkey:
            raise ValueError("ALADIN_KEY not set")
        
        self.timeout = 10
        
    def fetch_bestseller(self, start:int, max_results:int):
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
        
        data = res.json()
        items = data.get("item", [])
        
        df = pd.DataFrame(items)
        
        return df