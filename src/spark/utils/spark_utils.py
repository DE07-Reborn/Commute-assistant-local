from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, split, from_json, regexp_replace, 
    when, lit, to_timestamp, date_format, 
)

import redis
import json

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

    def save_to_s3(self, df, folder, checkpoint, _format = 'parquet'):
        """
            Save spark dataframe as  format in s3 folder with checkpoint
            param
                df : spark dataset
                folder : the directory name of data
                checkpoint : Check point info of data within spark/kafka
                _format : The format of dataset store into S3
        """
        (
            df
            .writeStream
            .format(_format)
            .option('path', f"s3a://{self.bucket}/{folder}")
            .option("checkpointLocation", checkpoint)
            .outputMode("append")
            .start()
        )


    def save_partition_to_redis(self, partition, redis_host="redis", redis_port=6379):
        try:
            r = redis.Redis(
                host=redis_host,
                port=redis_port,
                decode_responses=True
            )
            pipe = r.pipeline()

            for row in partition:
                key = f"weather:stn:{row['stn_id']}"
                value = json.dumps(row.asDict())
                pipe.set(key, value)

            pipe.execute()

        except Exception as e:
            print(f"Redis write error: {e}")

        
    def write_df_to_redis(self, df, redis_host='redis', redis_port=6379):
        """
            For each partition in dataframe, save it into redis
            parmam
                df : DataFrame
                redis_host : host name of redis
                redis_port : port number of redis
        """
        df.foreachPartition(
            lambda partition : self.save_partition_to_redis(
                partition=partition, 
                redis_host=redis_host, 
                redis_port=redis_port
            )
        )