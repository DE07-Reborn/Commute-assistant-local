from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, split, from_json, regexp_replace, 
    when, lit, to_timestamp, date_format, 
    to_json, struct
)
from pyspark.sql.types import StructType, StructField, StringType
import logging, os

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("weather-streaming")

def get_spark(appName):
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
        .getOrCreate()
    )



def main():
    spark = get_spark("consume_hourly_weather")
    bucket = os.getenv("AWS_S3_BUCKET")
    if not bucket:
        raise RuntimeError("AWS_S3_BUCKET env var is required")
    
    checkpoint_s3 = f"s3a://{bucket}/weather/_checkpoint"
    checkpoint_kafka = f"s3a://{bucket}/weather/_checkpoint_kafka"

    # read recent data from kafka topic : batch
    df_raw = (
        spark.readStream
        .format("kafka")
        .option("kafka.bootstrap.servers", "kafka:19092")
        .option("subscribe", "hourly_weather_raw")
        .option("startingOffsets", "latest")
        .option("failOnDataLoss", "false")
        .load()
    )


    # Divide Column from kafka value 
    kafka_value_schema = StructType([
        StructField("raw_line", StringType(), False),
        StructField("obs_time", StringType(), False),
        StructField("stn_id", StringType(), False),
    ])

    df_json = (
        df_raw
        .selectExpr("CAST(value as STRING) as json_str")
        .select(
            from_json(col("json_str"), kafka_value_schema).alias("data")
        )
        .select("data.*")
    )

    # split by empty space within a row
    df_split = df_json.withColumn(
        "fields",
        split(regexp_replace(col("raw_line"), r"\s+", " "), " ")
    )


    # extract using columns from df_split
    df_parsed = (
        df_split
        .withColumn("ws", col('fields')[3].cast('double')) # 풍속
        .withColumn("ta", col('fields')[11].cast('double')) # 기온
        .withColumn("hm", col('fields')[13].cast('double')) # 상대습도
        .withColumn("rn", col('fields')[15].cast('double')) # 강수량
        .withColumn("sd_tot", col('fields')[21].cast('double')) # 신적설
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
    )

    # Create new columns
    df_parsed = (
        df_clean
        .withColumn(
            "pty",
            when((col("rn") > 0) & (col("sd_tot") > 0), lit("Snow"))
            .when(col("rn") > 0, lit("Rain"))
            .otherwise(lit(None))
        ) # 강수형태
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

    # Final DataFrame
    df_final = (
        df_parsed
        .withColumn("obs_ts", to_timestamp(col("obs_time"), "yyyyMMddHHmm"))
        .withColumn("obs_yyyymmddhh", date_format(col("obs_ts"), "yyyyMMddHH"))
        .select(
            "obs_time", "obs_ts", "obs_yyyymmddhh",
            "stn_id",
            "ws", "ta", "hm", "rn", "sd_tot",
            "pty", "pop", "sky"
        )
    )

    # Save into s3
    s3_query = (
        df_final
        .writeStream
        .format("parquet")
        .option("path", f"s3a://{bucket}/weather/hourly/")
        .option("checkpointLocation", checkpoint_s3)
        .outputMode("append")
        .trigger(processingTime="1 minute")
        .start()
    )

    kafka_out_df = (
        df_final
        .select(
            col("stn_id").cast("string").alias("key"),
            to_json(struct("*")).alias("value")
        )
    )

    kafka_query = (
        kafka_out_df
        .writeStream
        .format("kafka")
        .option("kafka.bootstrap.servers", "kafka:19092")
        .option("topic", "hourly_weather_processed")
        .option("checkpointLocation", checkpoint_kafka)
        .outputMode("append")
        .start()
    )

    log.info("Weather streaming started. Waiting termination...")
    spark.streams.awaitAnyTermination()


if __name__ == "__main__":
    main()