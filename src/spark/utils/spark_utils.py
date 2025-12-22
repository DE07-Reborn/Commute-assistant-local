from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, split, from_json, regexp_replace, 
    when, lit, to_timestamp, date_format, 
)

import redis
import logging

from pyspark.sql.types import StructType, StructField, StringType
import os

class Spark_utils:
    """
        Utils library for spark jobs
    """

    def __init__(self):
        self.bucket = os.getenv("AWS_S3_BUCKET")
        if not self.bucket:
            raise RuntimeError("AWS_S3_BUCKET env var is required")
        
        logging.basicConfig(level=logging.INFO)
        self.log = logging.getLogger("spark-utils")

        self.redis_host = os.getenv("REDIS_HOST")
        self.redis_port = int(os.getenv("REDIS_PORT"))
        

    def get_spark(self, appName):
        """
            Build new spark session with appName
            param 
                appName : Name of spark session
        """
        return (
            SparkSession.builder
            .appName(appName)
            .master("spark://spark-master:7077")
            .config("spark.sql.session.timeZone", "Asia/Seoul")
            .config("spark.hadoop.fs.s3a.aws.credentials.provider", 
                    "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
            .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
            .config("spark.redis.host", self.redis_host)
            .config("spark.redis.port", str(self.redis_port)) 
            .getOrCreate()
        )
    
    def read_kafka_topic(self, spark_session, topic, offset='latest'):
        """
            Read and load kafka topic 
            parmam
                spark_session : Current Spark Session
                topic : Kafka topic name
                offset : Starting offset in topic
        """
        return(
            spark_session.readStream
            .format("kafka")
            .option("kafka.bootstrap.servers", "kafka:19092")
            .option("subscribe", topic)
            .option("startingOffsets", offset)
            .option("failOnDataLoss", "false")
            .load()
        )
    


    def preprocessing_kma_weather(self, raw_data):
        """
            preprocessing hourly kma weather data 
                - Extract meaningful columns and impute abnormal data
            param   
                raw_data : data stored in topic
        """
        
        # Specify column from data to be used
        schema = StructType([
            StructField("raw_line", StringType(), False),
            StructField("obs_time", StringType(), False),
            StructField("stn_id", StringType(), False),
        ])

        # Cast value to String and set into column as data
        df_json = (
            raw_data
            .selectExpr("CAST(value as STRING) as json_str")
            .select(
                from_json(col("json_str"), schema).alias("data")
            )
            .select("data.*")
        )

        # Split the raw_line by space and store in fields as list
        df_splited = df_json.withColumn(
            'fields',
            split(regexp_replace(col("raw_line"), r"\s+", " "), " ")
        )

        # Extract meaningful columns from list and save as column
        df_parsed = (
            df_splited
            .withColumn("ws", col('fields')[3].cast('double')) # 풍속
            .withColumn("ta", col('fields')[11].cast('double')) # 기온
            .withColumn("hm", col('fields')[13].cast('double')) # 상대습도
            .withColumn("rn", col('fields')[15].cast('double')) # 강수량
            .withColumn("sd_tot", col('fields')[21].cast('double')) # 신적설
            .withColumn('wc', col('fields')[22].cast('int')) # GT 현재일기
            .withColumn("ca_tot", col('fields')[25].cast('int')) # 하늘상태
        )

        # Imputation
        def sanitize_num(c):
            return when(col(c).isin(-9, -99), lit(0)).otherwise(col(c))

        df_clean = (
            df_parsed
            .withColumn("ws", sanitize_num("ws"))
            .withColumn("rn", sanitize_num("rn"))
            .withColumn("sd_tot", sanitize_num("sd_tot"))
            .withColumn("ta", when(col("ta").isin(-9, -99), lit(None)).otherwise(col("ta")))
            .withColumn("hm", when(col("hm").isin(-9, -99), lit(None)).otherwise(col("hm")))
            .withColumn("ca_tot", when(col("ca_tot").isin(-9, -99), lit(None)).otherwise(col("ca_tot")))
            .withColumn('wc', when(col('wc').isin(-9, -99), lit(None)).otherwise(col('wc')))
        )

        # Extra information
        # Compute is pop : Is raining and sky : Condition of the sky
        df_parsed = (
            df_clean
            .withColumn(
                "pop",
                when(col("rn") > 0, lit(1)).otherwise(lit(0))
            ) # 강수 유무
            .withColumn(
                "sky",
                when(col("ca_tot") == 0, lit(1))
                .when(col("ca_tot").between(1, 2), lit(2))
                .when(col("ca_tot").between(3, 5), lit(3))
                .when(col("ca_tot").between(6, 7), lit(4))
                .otherwise(lit(5))
            ) # 하늘상태 (1-맑음; 2-구름조금; 3-부분적흐림; 4-대체로흐림; 5-흐림)
        )

        # Fix final DataFrame
        return (
            df_parsed
            .withColumn("obs_ts", to_timestamp(col("obs_time"), "yyyyMMddHHmm"))
            .withColumn("obs_yyyymmddhh", date_format(col("obs_ts"), "yyyyMMddHH"))
            .select(
                "obs_time", "obs_ts", "obs_yyyymmddhh",
                "stn_id",
                "ws", "ta", "hm", "rn", "sd_tot",
                "wc", "pop", "sky"
            )
        )


    def save_batch_to_s3(self, batch_df, batch_id):
        """
            Save spark dataframe as parquet in s3 folder
        """
        try:
            count = batch_df.count()
            s3_path = f"s3a://{self.bucket}/kma-weather/hourly-data"
            
            self.log.info(f"Batch {batch_id}: Writing {count} records to S3...")
            
            (
                batch_df
                .write
                .mode("append")
                .partitionBy("obs_yyyymmddhh")
                .parquet(s3_path)
            )
            
            self.log.info(f"Batch {batch_id}: Successfully saved {count} records to S3 - {s3_path}")
            
        except Exception as e:
            self.log.error(f"Batch {batch_id}: S3 write error: {e}")
            raise


    def save_batch_to_redis(self, batch_df, batch_id):
        try:
            rows = batch_df.collect()

            if not rows:
                self.log.info(f'Batch {batch_id}: No data to write to Redis')
                return
            
            r = redis.Redis(
                host=self.redis_host,
                port=self.redis_port,
                decode_responses=True
            )
            for row in rows:
                try:
                    weather_data = {
                        # 관측시간(obs_time), 기온(TA), 습도(hm), 현재일기(wc), 강수유무(pop), 하늘상태(sky)
                        'obs_time': row['obs_time'] or '',
                        'ta': str(row['ta']) if row['ta'] is not None else '',
                        'hm': str(row['hm']) if row['hm'] is not None else '',
                        'wc': str(row['wc']) if row['wc'] is not None else '',
                        'pop': str(row['pop']) if row['pop'] is not None else '',
                        'sky': str(row['sky']) if row['sky'] is not None else '',
                        # 도서 및 음악 추천 결과 저장
                    }
                    
                    # Store in Redis as key : kma-stn:stn_id
                    key = f"kma-stn:{row['stn_id']}"
                    r.hset(key, mapping=weather_data)
                    
                    # TTL 24 hours
                    r.expire(key, 86400)
                    
                    self.log.info(f"Batch {batch_id}: Saved to Redis - {key}")
                    
                except Exception as row_error:
                    self.log.error(f"Batch {batch_id}: Error saving row to Redis: {row_error}")
                    continue
            
            self.log.info(f"Batch {batch_id}: Successfully saved {len(rows)} records to Redis")
            
        except Exception as e:
            self.log.error(f"Batch {batch_id}: Redis batch write error: {e}")
            raise

    def weather_to_class(self, session, file_path, weather_df):
        weather_df.createOrReplaceTempView("weather_df")
        music_df = session.read.parquet(f"s3a://{self.bucket}/{file_path}")
        music_df.createOrReplaceTempView("music_df")

        # music_list의 경우 list형이기 때문에 이대로 csv나 parquet으로 저장하지 못함.
        # json으로는 저장 가능
        result_df = session.sql("""
        with weather_convert AS(
            SELECT *,
            CASE WHEN month(obs_ts) BETWEEN 3 AND 5 THEN '봄'
            WHEN month(obs_ts) BETWEEN 6 AND 8 THEN '여름'
            WHEN month(obs_ts) BETWEEN 9 AND 11 THEN '가을'
            ELSE '겨울'
            END AS season,
            CASE WHEN hour(obs_ts) BETWEEN 0 AND 6 THEN '새벽'
            WHEN hour(obs_ts) BETWEEN 7 AND 11 THEN '오전'
            WHEN hour(obs_ts) BETWEEN 12 AND 17 THEN '오후'
            WHEN hour(obs_ts) BETWEEN 18 AND 24 THEN '밤'
            END AS time_category,
            CASE WHEN wc IN (70, 71, 72, 73, 74, 75, 76, 77, 78, 79) THEN '눈'
            WHEN wc IN (50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99) THEN '비'
            WHEN (season = '여름' AND ta >= 30 AND time_category IN ('오전', '오후')) OR (season = '여름' AND ta >= 25 AND time_category IN ('새벽', '밤')) THEN '더위'
            WHEN sky = 5 THEN '흐림'
            WHEN date_format(obs_ts, 'MM-dd') BETWEEN '02-25' AND '04-05'
                    OR date_format(obs_ts, 'MM-dd') BETWEEN '08-25' AND '10-05'
                THEN '환절기'
            WHEN (time_category IN ('오전', '오후') AND ta BETWEEN 20 AND 26) OR (time_category = '밤' AND ta BETWEEN 18 AND 22) OR (time_category = '밤' AND ta BETWEEN 15 AND 20) THEN '선선'
            ELSE '화창' END AS weather_category,
            CONCAT(season, '-', time_category, '-', weather_category) AS weather_code
            FROM weather_df
        ),
        weather_code_join AS(
        SELECT a.stn_Id, collect_list((b.artists, b.album_name, b.track_name)) music_list
        FROM weather_convert a
        JOIN music_df b ON a.weather_code = b.weather_code
        GROUP BY a.stn_id
        )
        SELECT a.*, b.music_list
        FROM weather_convert a
        JOIN weather_code_join b ON a.stn_id = b.stn_id
        """)

        return result_df
