from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, split, from_json, regexp_replace, 
    when, lit, to_timestamp, date_format, 
    explode, min, max, avg, struct,
    collect_list, expr
)

import json
import redis
import logging

from pyspark.sql.types import (
    StructType, StructField, 
    StringType, IntegerType, ArrayType
)
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
            # General setup
            .master("spark://spark-master:7077")
            .config("spark.sql.session.timeZone", "Asia/Seoul")
            .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
            .config("spark.jars.ivy", "/tmp/ivy")
            # S3
            .config("spark.hadoop.fs.s3a.aws.credentials.provider",
                "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
            .config("spark.hadoop.fs.s3a.connection.maximum", "80")
            .config("spark.hadoop.fs.s3a.path.style.access", "true")
            # Stream
            .config("spark.streaming.stopGracefullyOnShutdown", "true")
            .config("spark.streaming.backpressure.enabled", "true")
            .config("spark.streaming.kafka.allowNonConsecutiveOffsets", "true")
            .config("spark.streaming.kafka.consumer.poll.ms", "30000")
            .config("spark.sql.adaptive.enabled", "true")
            .config("spark.sql.shuffle.partitions", "4")
            .config("spark.streaming.kafka.maxRatePerPartition", "800")

            # Redis
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
            .option("kafka.bootstrap.servers", "kafka:9092")
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




    # Forecast 
    def preprocessing_weather_forecast(self, raw_data):
        """
            Preprocessing the weather forecast data format of
                raw_json : struct
                base_time : string
                coord_id : string,
                addresses : list(string)
        """

        # schema of raw_json
        weather_item_schema = StructType([
            StructField("baseDate", StringType(), True),
            StructField("baseTime", StringType(), True),
            StructField("category", StringType(), True),
            StructField("fcstDate", StringType(), True),
            StructField("fcstTime", StringType(), True),
            StructField("fcstValue", StringType(), True),
            StructField("nx", IntegerType(), True),
            StructField("ny", IntegerType(), True),
        ])
        raw_json_schema = StructType([
            StructField("response", StructType([
                StructField("body", StructType([
                    StructField("items", StructType([
                        StructField("item", ArrayType(weather_item_schema), True)
                    ]), True)
                ]), True)
            ]), True)
        ])

        # Schema
        schema = StructType([
            StructField('raw_json', raw_json_schema, True),
            StructField('base_time', StringType(), True),
            StructField('coord_id', StringType(), True),
            StructField('addresses', ArrayType(StringType()), True)
        ])

        # JSON parse
        df_parsed = (
            raw_data
            .selectExpr('CAST(value as String) as json', 'timestamp')
            .select(from_json(col('json'), schema).alias('data'), col('timestamp'))
            .select(
                col('data.raw_json'),
                col('data.base_time'),
                col('data.coord_id'),
                col('data.addresses'),
                col('timestamp')
            )
        )

        # Explode to create each column : address and raw_json
        df_address = (
            df_parsed
            .withColumn('address', explode(col('addresses')))
            .withColumn('item', explode(col("raw_json.response.body.items.item")))
            .select(
                col("address"),
                col('base_time'),
                col("item.fcstTime").alias("fcst_time"),
                col("item.category").alias("category"),
                col("item.fcstValue").alias("fcst_value"),
                col("timestamp")
            )
        )

        # Cast to each using columns to either double or integer
        df_num = (
            df_address
            # 온도
            .withColumn(
                "T1H_val",
                when(col("category") == "T1H", col("fcst_value").cast("double"))
            )
            # 1시간 강수량
            .withColumn(
                "RN1_val",
                when(
                    col("category") == "RN1",
                    when(col("fcst_value") == "강수없음", "0").otherwise(col("fcst_value"))
                ).cast("double")
            )
            # 하늘 상태
            .withColumn(
                "SKY_val",
                when(col("category") == "SKY", col("fcst_value").cast("int"))
            )
            # 습도
            .withColumn(
                "REH_val",
                when(col("category") == "REH", col("fcst_value").cast("double"))
            )
            # 강수 형태
            .withColumn(
                "PTY_val",
                when(col("category") == "PTY", col("fcst_value").cast("int"))
            )
            # 풍속
            .withColumn(
                "WSD_val",
                when(col("category") == "WSD", col("fcst_value").cast("double"))
            )
        )

        # Aggregation
        """ 
            Group by address and its base time, compute 
            To see whether is raining today, if yes then when and what type 
            To see hows the cloud looks like To see Today's humidity 
            To see Today's wind speed To see today's min, average, max average within time 
            To see today's discomfort index To see today's apparent temperature 
        """
        result = (
            df_num
            .groupBy("address", "base_time")
            .agg(
                # Is raining
                (max("PTY_val") > 0).alias("is_raining"),
                min(
                    when(col("PTY_val") > 0, col("fcst_time"))
                ).alias("when_is_raining"),
                avg("RN1_val").alias("precipitation"),

                # humidity and wind speed (avg)
                avg("REH_val").alias("humidity"),
                avg("WSD_val").alias("wind_speed"),

                # temperate(min, avg, max)
                min("T1H_val").alias("temp_min"),
                max("T1H_val").alias("temp_max"),
                avg("T1H_val").alias("temp_avg"),

                # SKY
                collect_list(
                    when(
                        col("SKY_val").isNotNull(),
                        struct(
                            col("fcst_time"),
                            col("SKY_val").alias("code"),
                            when(col("SKY_val") == 1, "맑음")
                            .when(col("SKY_val") == 2, "구름조금")
                            .when(col("SKY_val") == 3, "구름많음")
                            .when(col("SKY_val") == 4, "흐림")
                            .alias("label")
                        )
                    )
                ).alias("sky_details_raw"),

                # precipitation
                collect_list(
                    when(
                        col("PTY_val").isNotNull(),
                        struct(
                            col("fcst_time"),
                            col("PTY_val").alias("code"),
                            when(col("PTY_val") == 0, "없음")
                            .when(col("PTY_val") == 1, "비")
                            .when(col("PTY_val") == 2, "비/눈")
                            .when(col("PTY_val") == 3, "눈")
                            .when(col("PTY_val") == 5, "빗방울")
                            .when(col("PTY_val") == 6, "빗방울눈날림")
                            .when(col("PTY_val") == 7, "눈날림")
                            .alias("label")
                        )
                    )
                ).alias("precipitation_details_raw")
            )
        )

        # Remove null struct
        result = (
            result
            .withColumn(
                "sky_details",
                expr("filter(sky_details_raw, x -> x is not null)")
            )
            .withColumn(
                "precipitation_details",
                expr("filter(precipitation_details_raw, x -> x is not null)")
            )
            .drop("sky_details_raw", "precipitation_details_raw")
        )

        # Discomfort index and apapparent temperature
        result = result.withColumn(
            "discomfort_index",
            0.81 * col("temp_avg")
            + 0.01 * col("humidity") * (0.99 * col("temp_avg") - 14.3)
            + 46.3
        )
        result = result.withColumn(
            "apparent_temp",
            13.12 \
            + 0.6215 * col("temp_avg") \
            - 11.37 * (col("wind_speed")**0.16) \
            + 0.3965 * col("temp_avg") * (col("wind_speed")**0.16)
        )

        return result
    

    def save_batch_to_redis_forecast(self, batch_df, batch_id):
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
                    # Store in Redis as key : forecast:address
                    key = f"forecast:{row['address']}"
                    value = json.dumps(row.asDict(), ensure_ascii=False)
                    r.set(key, value)
                    
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

    def save_batch_to_s3_forecast(self, batch_df, batch_id):
        """
            Save spark dataframe as parquet in s3 folder
        """
        try:
            s3_path = f"s3a://{self.bucket}/weather-forecast/hourly-data"
            
            self.log.info(f"Batch {batch_id}: Writing records to S3...")
            
            (
                batch_df
                .write
                .mode("overwrite")
                .partitionBy("base_time")
                .parquet(s3_path)
                .option("compression", "snappy")
                .option("maxRecordsPerFile", 20000)
            )
            
            self.log.info(f"Batch {batch_id}: Successfully saved records to S3 - {s3_path}")
            
        except Exception as e:
            self.log.error(f"Batch {batch_id}: S3 write error: {e}")
            raise