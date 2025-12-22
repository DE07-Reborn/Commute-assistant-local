import pandas as pd

class booklist_preprocess_utils:
    
    def __init__(self):
        self.TARGET_GENRES = [
            "건강정보", "건강정보/건강에세이/투병기", "두뇌건강", "음식과 건강", "지압/마사지", "정신건강",
            "공예", "원예", "등산/캠핑", "바둑/장기", "취미기타", "퍼즐/스도쿠/퀴즈", "건강요리", "디저트", "뜨개질/바느질/DIY", "인테리어", "제과제빵",
            "경제학/경제일반", "재테크/투자", "트렌드/미래전망",
            "고전",
            "한국소설", "일본소설", "영미소설", "추리/미스터리소설", "판타지/환상문학", "역사소설", "과학소설", "호러/공포소설", "액션/스릴러소설",
            "시",
            "과학",
            "사회과학",
            "에세이",
            "여행",
            "역사",
            "예술/대중문화",
            "인문학",
            "삶의자세/정신훈련", "성공전략/성공학", "인간관계 일반", "행복론", "힐링", "시간관리/정보관리", "두뇌계발"
        ]
    
    # 알라딘 기준 카테고리 표기 -> 장르 파싱
    def parse_target_genre(self, category_name:str):
        if not isinstance(category_name, str):
            return None
        
        category_parts = [c.strip() for c in category_name.split(">") if c.strip()]
        
        for part in category_parts:
            if part in self.TARGET_GENRES:
                # 공백 or '/' -> '_'
                return part.replace(" ", "_").replace("/", "_")
        
        return None
    
    # ebook 관련 컬럼 추출
    def extract_ebook_fields(self, subinfo:str):
        if not isinstance(subinfo, dict):
            return {
                "has_ebook": False,
                "ebook_count": 0,
            }
        
        ebook_list = subinfo.get("ebookList")
        if not isinstance(ebook_list, list) or len(ebook_list) == 0:
            return {
                "has_ebook": False,
                "ebook_count": 0,
            }
        
        ebook = ebook_list[0]
        return {
            "has_ebook": True,
            "ebook_count": len(ebook_list),
            "ebook_itemId": ebook.get("itemId"),
            "ebook_isbn": ebook.get("isbn"),
            "ebook_isbn13": ebook.get("isbn13"),
            "ebook_priceSales": ebook.get("priceSales"),
            "ebook_link": ebook.get("link"),
        }
    
    # 전체 df 전처리
    def preprocess_bestseller(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        
        df["genre"] = df["categoryName"].apply(self.parse_target_genre)
        
        ebook_df = df["subInfo"].apply(self.extract_ebook_fields).apply(pd.Series)
        df = pd.concat([df, ebook_df], axis=1)
        df = df.drop(columns=["subInfo", "seriesInfo"], errors="ignore")  # parquet 처리 불가 컬럼 제거
        
        return df