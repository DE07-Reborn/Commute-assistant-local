"""
도서 추천 로직
1. 계절(obs_yyyymmddhh) + 시간대(obs_ts) + 날씨(ws, ta, hm, rn, sd_tot, pop, sky) => 환경 Context 구성
2. 환경 Context -> latent(잠재 상태) 계산
3. 환경 + latent score -> 대표 장르 결정 (config-driven)
4. 대표 장르 -> 세부 장르 선택
5. S3에서 해당 세부 장르의 eBook 정보 가져오기
   - (Tier1) rec_genre 매칭
   - (Tier2) rep_genre 범위(서브장르 묶음)에서 1권 fallback
   - (Tier3) global default 1권 fallback (무조건 존재해야 함)
"""

from __future__ import annotations

from functools import reduce

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import (
    col, lit, when,
    month, hour,
    concat_ws, coalesce,
    sha2, substring, conv,
    pmod, broadcast,
    size, element_at,
    greatest
)
from pyspark.sql.types import ArrayType, StringType
from pyspark.sql.functions import udf

# 대표 장르 > 세부 장르 매핑
REP_GENRE_MAP = {
    "HEALTH_LIFESTYLE": ["건강정보", "건강정보_건강에세이_투병기", "두뇌건강", "음식과 건강", "지압_마사지", "정신건강"],
    "HOBBY": ["공예", "원예", "등산_캠핑", "바둑_장기", "취미기타", "퍼즐_스도쿠_퀴즈", "건강요리", "디저트", "뜨개질_바느질_DIY", "인테리어", "제과제빵"],
    "ECONOMY": ["경제학_경제일반", "재테크_투자", "트렌드_미래전망"],
    "LITERATURE_FICTION": ["고전", "한국소설", "일본소설", "영미소설", "시"],
    "GENRE_FICTION": ["추리_미스터리소설", "판타지_환상문학", "역사소설", "과학소설", "호러_공포소설", "액션_스릴러소설"],
    "ACADEMIC": ["과학", "사회과학", "역사", "예술_대중문화", "인문학"],
    "LIGHT": ["에세이", "여행"],
    "PRODUCTIVITY": ["삶의자세_정신훈련", "성공전략_성공학", "인간관계일반", "행복론", "힐링", "시간관리_정보관리", "두뇌계발"],
}
DEFAULT_REP_GENRE = "LITERATURE_FICTION"

@udf(returnType=ArrayType(StringType()))
def rep_to_subgenre(rep_genre: str):
    return REP_GENRE_MAP.get(rep_genre, REP_GENRE_MAP[DEFAULT_REP_GENRE])

# 장르 점수 기준
GENRE_SCORE_CONFIG = {
    "HEALTH_LIFESTYLE": {
        "context": {"is_cold": 0.4, "season:winter": 0.3, "is_humid": 0.3},
        "latent": {"cognitive_load": 0.5, "avoidance_inv": 0.5},
    },
    "HOBBY": {
        "context": {"season:spring": 0.4, "is_clear": 0.4, "daypart:morning": 0.2},
        "latent": {"valence": 0.6, "avoidance_inv": 0.4},
    },
    "ECONOMY": {
        "context": {"season:summer": 0.4, "daypart:morning": 0.3, "is_clear": 0.3},
        "latent": {"cognitive_load": 0.6, "dominance": 0.4},
    },
    "LITERATURE_FICTION": {
        "context": {"is_clear": 0.4, "season:fall": 0.3, "daypart:evening": 0.3},
        "latent": {"valence": 0.6, "arousal_inv": 0.4},
    },
    "GENRE_FICTION": {
        "context": {"is_cloudy": 0.4, "is_rainy": 0.3, "daypart:night": 0.3},
        "latent": {"avoidance": 0.6, "cognitive_load_inv": 0.4},
    },
    "ACADEMIC": {
        "context": {"season:fall": 0.4, "is_mild": 0.3, "daypart:afternoon": 0.3},
        "latent": {"cognitive_load": 0.7, "dominance": 0.3},
    },
    "LIGHT": {
        "context": {"is_rainy": 0.4, "is_snowy": 0.3, "daypart:evening": 0.3},
        "latent": {"cognitive_load_inv": 0.6, "valence": 0.4},
    },
    "PRODUCTIVITY": {
        "context": {"is_clear": 0.4, "daypart:morning": 0.6},
        "latent": {"cognitive_load": 0.6, "dominance": 0.4},
    },
}

# Book Recommender
class BookRecommender:

    def __init__(self, spark: SparkSession, bucket: str):
        self.spark = spark
        self.bucket = bucket
        self.booklist_path = f"s3a://{bucket}/BookList/*/*.parquet"

        # Tier cache
        self._tier1_top_by_genre_df = None   # (genre -> top1)
        self._tier2_top_by_rep_df = None     # (rep_genre -> top1 among its subgenres)
        self._tier3_global_top_df = None     # (single row) global default top1

    # S3에 저장된 장르별 TOP eBook 로딩 (+ fallback tier 구축)
    def _load_top_ebook_df(self):
        if (
            self._tier1_top_by_genre_df is not None
            and self._tier2_top_by_rep_df is not None
            and self._tier3_global_top_df is not None
        ):
            return

        from pyspark.sql.window import Window
        from pyspark.sql.functions import row_number, explode

        books = self.spark.read.parquet(self.booklist_path)
        ebooks = books.filter(col("has_ebook"))

        # Tier1: genre(=sub genre)별 top1
        w1 = Window.partitionBy("genre").orderBy(col("bestRank").cast("int").asc())

        tier1 = (
            ebooks
            .withColumn("rn", row_number().over(w1))
            .filter(col("rn") == 1)
            .select(
                col("genre").alias("tier1_genre"),
                col("title").alias("tier1_title"),
                col("author").alias("tier1_author"),
                col("categoryName").alias("tier1_categoryName"),
                col("description").alias("tier1_description"),
                col("ebook_isbn13").alias("tier1_ebook_isbn13"),
                col("ebook_link").alias("tier1_ebook_link"),
            )
        )

        # Tier3: global top1 (전역 fallback, 반드시 존재해야 함)
        w3 = Window.orderBy(col("bestRank").cast("int").asc())

        tier3 = (
            ebooks
            .withColumn("rn", row_number().over(w3))
            .filter(col("rn") == 1)
            .select(
                col("title").alias("tier3_title"),
                col("author").alias("tier3_author"),
                col("categoryName").alias("tier3_categoryName"),
                col("description").alias("tier3_description"),
                col("ebook_isbn13").alias("tier3_ebook_isbn13"),
                col("ebook_link").alias("tier3_ebook_link"),
            )
        )

        # Tier2: rep_genre별 top1 (rep_genre의 subgenre 묶음에서 bestRank top1)
        rep_rows = []
        for rep, subs in REP_GENRE_MAP.items():
            rep_rows.append((rep, subs))

        rep_schema_df = self.spark.createDataFrame(rep_rows, ["rep_genre", "sub_list"])
        rep_exploded = rep_schema_df.select(col("rep_genre"), explode(col("sub_list")).alias("sub_genre"))

        # rep_genre + (매칭된 ebooks) 중 bestRank top1
        w2 = Window.partitionBy("rep_genre").orderBy(col("bestRank").cast("int").asc())

        tier2 = (
            rep_exploded
            .join(ebooks, rep_exploded["sub_genre"] == ebooks["genre"], "inner")
            .withColumn("rn", row_number().over(w2))
            .filter(col("rn") == 1)
            .select(
                col("rep_genre").alias("tier2_rep_genre"),
                col("title").alias("tier2_title"),
                col("author").alias("tier2_author"),
                col("categoryName").alias("tier2_categoryName"),
                col("description").alias("tier2_description"),
                col("ebook_isbn13").alias("tier2_ebook_isbn13"),
                col("ebook_link").alias("tier2_ebook_link"),
            )
        )

        self._tier1_top_by_genre_df = tier1
        self._tier2_top_by_rep_df = tier2
        self._tier3_global_top_df = tier3

    # 메인 추천 로직
    def add_recommendation(self, df: DataFrame):

        # 환경 Context - 계절/시간대
        df = (
            df
            .withColumn("month", month(col("obs_ts")))
            .withColumn("hour", hour(col("obs_ts")))
            .withColumn(
                "season",
                when(col("month").isin(3, 4, 5), "spring")
                .when(col("month").isin(6, 7, 8), "summer")
                .when(col("month").isin(9, 10, 11), "fall")
                .otherwise("winter")
            )
            .withColumn(
                "daypart",
                when(col("hour").between(6, 11), "morning")
                .when(col("hour").between(12, 17), "afternoon")
                .when(col("hour").between(18, 23), "evening")
                .otherwise("night")
            )
            .drop("month", "hour")
        )

        # 환경 Context - 날씨
        ta = coalesce(col("ta"), lit(15.0))
        hm = coalesce(col("hm"), lit(60.0))
        rn = coalesce(col("rn"), lit(0.0))
        ws = coalesce(col("ws"), lit(2.0))
        sky = coalesce(col("sky"), lit(3))
        sunny = (sky == 1) & (ta >= 22) & (hm <= 60)
        cloudy = (sky >= 4)
        cool = (
            ((col("daypart").isin("morning", "afternoon")) & ta.between(20, 26)) |
            ((col("daypart") == "evening") & ta.between(18, 22)) |
            ((col("daypart") == "night") & ta.between(15, 20))
        )
        hot = (ta >= 30) | ((col("daypart") == "night") & (ta >= 25))

        df = (df
            .withColumn("is_rainy", (rn > 0) | (col("pop") >= 60))
            .withColumn("is_snowy", col("sd_tot") > 0)
            .withColumn("is_windy", ws >= 6)
            .withColumn("is_humid", hm >= 75)
            .withColumn("is_cold", ta <= 5)
            .withColumn("is_hot", ta >= 30)
            .withColumn("is_mild", ta.between(10, 24))
            .withColumn("is_clear", sky.isin(1, 2))
            .withColumn("is_cloudy", sky >= 4)
        )

        # Latent State 계산
        df = (df
            .withColumn(        # Valence : 정서적 긍부정도
                "valence",
                when(sunny, 0.8)
                .when(cool, 0.65)
                .when(hot, 0.35)
                .when(cloudy, 0.4)
                .otherwise(0.55)
            )
            .withColumn(        # Arousal : 자극/활성도
                "arousal",
                when(hot & (col("daypart") == "afternoon"), 0.75)
                .otherwise(0.55)
            )
            .withColumn(        # Dominance : 통제감
                "dominance",
                when(hot, 0.45)
                .when(cool, 0.7)
                .otherwise(0.6)
            )
            .withColumn(        # Cognitive Load : 인지 부하(부담)
                "cognitive_load",
                when(cool & col("daypart").isin("morning", "afternoon"), 0.75)
                .when(sunny, 0.7)
                .when(cloudy, 0.45)
                .otherwise(0.55)
            )
            .withColumn(        # Avoidance : 회피
                "avoidance",
                when(hot, 0.85)
                .when(cloudy, 0.65)
                .when(cool, 0.3)
                .otherwise(0.2)
            )
        )

        # 장르 점수 계산
        score_cols = []
        for genre, conf in GENRE_SCORE_CONFIG.items():
            exprs = []

            for k, w in conf.get("context", {}).items():
                if ":" in k:
                    c, v = k.split(":")
                    exprs.append(w * (col(c) == v).cast("double"))
                else:
                    exprs.append(w * col(k).cast("double"))

            for k, w in conf.get("latent", {}).items():
                if k.endswith("_inv"):
                    exprs.append(w * (1 - col(k.replace("_inv", ""))))
                else:
                    exprs.append(w * col(k))

            score_col = f"score_{genre.lower()}"
            df = df.withColumn(score_col, reduce(lambda a, b: a + b, exprs))
            score_cols.append((genre, score_col))

        # 최고 점수의 장르 선택
        rep_expr = None
        for genre, score in score_cols:
            condition = col(score) == greatest(*[col(c) for _, c in score_cols])
            rep_expr = when(condition, genre) if rep_expr is None else rep_expr.when(condition, genre)

        df = df.withColumn("rep_genre", rep_expr.otherwise(DEFAULT_REP_GENRE))

        # 대표 장르 > 서브 장르 선택 - hash 기반 결정
        df = df.withColumn("sub_genres", rep_to_subgenre(col("rep_genre")))
        df = df.withColumn("sub_size", size(col("sub_genres")))

        seed = concat_ws("::", col("stn_id"), col("obs_time"))                  # 같은 지점 + 같은 시간 => 같은 seed
        hash_dec = conv(substring(sha2(seed, 256), 1, 16), 16, 10).cast("long") # 숫자 타입 seed로 변환

        df = df.withColumn(
            "rec_idx",
            (pmod(hash_dec, col("sub_size")) + lit(1)).cast("int")
        )
        df = (df
            .withColumn(
                "rec_genre",
                element_at(col("sub_genres"), col("rec_idx"))
            )
            .drop("sub_genres", "sub_size", "rec_idx")
        )

        # eBook Join
        self._load_top_ebook_df()

        # Tier1: rec_genre -> genre top1
        df = (
            df
            .join(
                broadcast(self._tier1_top_by_genre_df),
                df["rec_genre"] == self._tier1_top_by_genre_df["tier1_genre"],
                "left"
            )
            .drop("tier1_genre")
        )

        # Tier2: rep_genre -> rep_genre에서 top1
        df = (
            df
            .join(
                broadcast(self._tier2_top_by_rep_df),
                df["rep_genre"] == self._tier2_top_by_rep_df["tier2_rep_genre"],
                "left"
            )
            .drop("tier2_rep_genre")
        )

        # Tier3: global default top1
        df = (
            df
            .join(
                broadcast(self._tier3_global_top_df),
                lit(True),
                "left"
            )
        )

        # 최종 선택 (Tier1 > Tier2 > Tier3 순)
        df = (
            df
            .withColumn("title", coalesce(col("tier1_title"), col("tier2_title"), col("tier3_title")))
            .withColumn("author", coalesce(col("tier1_author"), col("tier2_author"), col("tier3_author")))
            .withColumn("categoryName", coalesce(col("tier1_categoryName"), col("tier2_categoryName"), col("tier3_categoryName")))
            .withColumn("description", coalesce(col("tier1_description"), col("tier2_description"), col("tier3_description")))
            .withColumn("ebook_isbn13", coalesce(col("tier1_ebook_isbn13"), col("tier2_ebook_isbn13"), col("tier3_ebook_isbn13")))
            .withColumn("ebook_link", coalesce(col("tier1_ebook_link"), col("tier2_ebook_link"), col("tier3_ebook_link")))
            .drop(
                "tier1_title", "tier1_author", "tier1_categoryName", "tier1_description", "tier1_ebook_isbn13", "tier1_ebook_link",
                "tier2_title", "tier2_author", "tier2_categoryName", "tier2_description", "tier2_ebook_isbn13", "tier2_ebook_link",
                "tier3_title", "tier3_author", "tier3_categoryName", "tier3_description", "tier3_ebook_isbn13", "tier3_ebook_link",
            )
        )

        return df.select(
            "obs_time", "obs_ts", "obs_yyyymmddhh", "stn_id",
            "ws", "ta", "hm", "rn", "sd_tot", "wc", "pop", "sky",
            "title", "author", "categoryName",
            "description", "ebook_isbn13", "ebook_link",
            'music_json'
        )