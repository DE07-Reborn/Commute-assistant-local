from spark.utils.spark_utils import Spark_utils
from spark.utils.book_recommender import BookRecommender
from pyspark.sql.functions import broadcast
from pyspark.sql.functions import (
    col, when, lit, coalesce, row_number, to_date
)
from pyspark.sql.window import Window

import logging

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("weather-forecast-streaming")

def run_weather_stream(spark_utils, spark, music_df):
    """
        The topic is received data every Hourly(00:05) 
    """

    log.info("Initializing weather stream...")

    # Read Kafka
    raw_weather = spark_utils.read_kafka_topic(spark, 'hourly_weather_raw')

    # Preprocess
    df_weather = spark_utils.preprocessing_kma_weather(raw_weather)

    df_weather = df_weather.join(
        broadcast(music_df),
        on='weather_code',
        how='left'
    )

    br = BookRecommender(
        spark=spark,
        bucket=spark_utils.bucket
    )
    df_with_recommendation = br.add_recommendation(df_weather)
    df_meta = spark.read.csv(f"s3a://{spark_utils.bucket}/stn-metadata/metadata.csv", header=True, inferSchema=True)
    df_with_recommendation_stn_meta = df_with_recommendation.join(df_meta, on="stn_id")

    # Redis Sink
    redis_checkpoint = f"s3a://{spark_utils.bucket}/kma-weather/_checkpoint_redis"
    redis_query = (
        df_with_recommendation_stn_meta
        .repartition(1)
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_redis)
        .outputMode("append")
        .option("checkpointLocation", redis_checkpoint)
        .start()
    )

    # S3 Sink
    s3_checkpoint = f"s3a://{spark_utils.bucket}/kma-weather/_checkpoint_s3"
    s3_query = (
        df_with_recommendation_stn_meta.writeStream
        .foreachBatch(spark_utils.save_batch_to_s3)
        .outputMode("append")
        .option("checkpointLocation", s3_checkpoint)
        .start()
    )

    log.info("Weather streaming started.")
    return [redis_query, s3_query]


def run_forecast_stream(spark_utils, spark):
    """
        30 minutes interval for 6hours of weather forecast
    """

    log.info("Initializing forecast stream...")

    # Read Kafka
    raw_forecast = spark_utils.read_kafka_topic(spark, '30min_forecast_raw')

    # Preprocess
    df_forecast = spark_utils.preprocessing_weather_forecast(raw_forecast)

    # Redis Sink
    redis_checkpoint = f"s3a://{spark_utils.bucket}/weather-forecast/_checkpoint_redis"
    redis_query = (
        df_forecast.writeStream
        .foreachBatch(spark_utils.save_batch_to_redis_forecast)
        .outputMode("update")
        .option("checkpointLocation", redis_checkpoint)
        .start()
    )

    # S3 Sink
    s3_checkpoint = f"s3a://{spark_utils.bucket}/weather-forecast/_checkpoint_s3"
    s3_query = (
        df_forecast.writeStream
        .foreachBatch(spark_utils.save_batch_to_s3_forecast)
        .outputMode("complete")
        .option("checkpointLocation", s3_checkpoint)
        .start()
    )

    log.info("Forecast streaming started.")
    return [redis_query, s3_query]

def run_air_realtime_stream(spark_utils, spark):

    log.info("Initializing air-realtime stream...")

    air_realtime_raw = spark_utils.read_kafka_topic(spark, "air-quality-realtime")
    air_realtime_df = spark_utils.preprocessing_air_realtime(air_realtime_raw)
    '''
    air_redis_checkpoint = f"s3a://{spark_utils.bucket}/air-realtime/_checkpoint_redis"
    air_redis_query = (
        air_realtime_df
        .repartition(1)
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_redis_air_realtime)
        .outputMode("append")
        .option("checkpointLocation", air_redis_checkpoint)
        .start()
    )
    '''
    air_s3_checkpoint = f"s3a://{spark_utils.bucket}/air-realtime/_checkpoint_s3"
    air_s3_query = (
        air_realtime_df
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_s3_air_realtime)
        .outputMode("append")
        .option("checkpointLocation", air_s3_checkpoint)
        .start()
    )

    log.info("Air-realtime streaming started.")
    return [air_s3_query]

def run_air_forecast_stream(spark_utils, spark):
    log.info("Initializing air-forecast stream...")
    air_forecast_raw = spark_utils.read_kafka_topic(spark, "air-quality-forecast")
    air_forecast_df = spark_utils.preprocessing_air_forecast(air_forecast_raw)

    air_fc_s3_checkpoint = f"s3a://{spark_utils.bucket}/air-forecast/_checkpoint_s3"
    air_fc_s3_query = (
        air_forecast_df
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_s3_air_forecast)
        .outputMode("complete")
        .option("checkpointLocation", air_fc_s3_checkpoint)
        .start()
    )
    '''
    air_fc_redis_checkpoint = f"s3a://{spark_utils.bucket}/air-forecast/_checkpoint_redis"
    air_fc_redis_query = (
        air_forecast_df
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_redis_air_forecast)
        .outputMode("update")
        .option("checkpointLocation", air_fc_redis_checkpoint)
        .start()
    )
    '''
    log.info("Air-forecast streaming started.")
    return [air_fc_s3_query]

def run_air_summary_stream(spark_utils, spark):
    log.info("Initializing air-summary stream...")
    air_realtime_raw = spark_utils.read_kafka_topic(spark, "air-quality-realtime")
    air_realtime_df = spark_utils.preprocessing_air_realtime(air_realtime_raw)

    def get_latest_forecast_path(spark_session, base_path):
        jvm = spark_session._jvm
        conf = spark_session._jsc.hadoopConfiguration()
        fs = jvm.org.apache.hadoop.fs.FileSystem.get(jvm.java.net.URI(base_path), conf)
        path = jvm.org.apache.hadoop.fs.Path(base_path)

        if not fs.exists(path):
            return None

        latest_value = None
        for status in fs.listStatus(path):
            name = status.getPath().getName()
            if name.startswith("data_time_yyyymmddhh="):
                value = name.split("=", 1)[1]
                if latest_value is None or value > latest_value:
                    latest_value = value

        if latest_value is None:
            return None

        return f"{base_path}/data_time_yyyymmddhh={latest_value}"

    def write_air_summary(batch_df, batch_id):
        if batch_df is None or batch_df.rdd.isEmpty():
            log.info(f"Batch {batch_id}: Empty air-summary batch")
            return

        batch_df = batch_df.withColumn("obs_date", to_date(col("obs_ts")))
        s3_path = f"s3a://{spark_utils.bucket}/air-forecast/hourly-data"
        spark_session = batch_df.sparkSession
        forecast_df = None

        try:
            latest_path = get_latest_forecast_path(spark_session, s3_path)
            if latest_path is None:
                log.warning(f"Batch {batch_id}: No air-forecast partitions found at {s3_path}")
            else:
                forecast_df = spark_session.read.parquet(latest_path)
        except Exception:
            log.warning(f"Batch {batch_id}: No air-forecast snapshot found at {s3_path}")

        if forecast_df is None or forecast_df.rdd.isEmpty():
            joined = (
                batch_df
                .withColumn("pm10_forecast_grade", lit(""))
                .withColumn("pm25_forecast_grade", lit(""))
                .withColumn("forecast_mask_required", lit("N"))
                .withColumn("inform_date", lit(None).cast("date"))
            )
        else:
            w = Window.partitionBy("region", "inform_date").orderBy(col("data_time_ts").desc())
            forecast_latest = (
                forecast_df
                .withColumn("rn", row_number().over(w))
                .filter(col("rn") == 1)
                .drop("rn")
            )
            joined = batch_df.join(
                forecast_latest,
                (batch_df.sido_name == forecast_latest.region) &
                (batch_df.obs_date == forecast_latest.inform_date),
                "left"
            )
            joined = (
                joined
                .withColumn(
                    "pm10_forecast_grade",
                    coalesce(col("pm10_forecast_grade"), lit(""))
                )
                .withColumn(
                    "pm25_forecast_grade",
                    coalesce(col("pm25_forecast_grade"), lit(""))
                )
                .withColumn(
                    "forecast_mask_required",
                    coalesce(col("forecast_mask_required"), lit("N"))
                )
            )

        joined = joined.withColumn(
            "mask_advice",
            when(col("realtime_mask_required") == "Y", lit("Y"))
            .when(col("forecast_mask_required") == "Y", lit("Y"))
            .otherwise(lit("N"))
        )

        spark_utils.save_batch_to_redis_air_summary(joined, batch_id)

    air_sum_checkpoint = f"s3a://{spark_utils.bucket}/air-summary/_checkpoint_redis"
    air_sum_query = (
        air_realtime_df
        .writeStream
        .foreachBatch(write_air_summary)
        .outputMode("update")
        .option("checkpointLocation", air_sum_checkpoint)
        .start()
    )

    log.info("Air-summary streaming started.")
    return [air_sum_query]

def main():
    spark_utils = Spark_utils()
    spark = spark_utils.get_spark("weather_streaming_app")

    log.info("Starting weather + forecast + air-realtime + air-forecast + air-summary streams...")

    # read music df
    music_df = spark_utils.get_music_data(spark)

    # Start both streaming pipelines
    weather_queries = run_weather_stream(spark_utils, spark, music_df)
    forecast_queries = run_forecast_stream(spark_utils, spark)
    air_realtime_queries = run_air_realtime_stream(spark_utils, spark)
    air_forecast_queries = run_air_forecast_stream(spark_utils, spark)
    air_summary_queries = run_air_summary_stream(spark_utils, spark)

    # Wait for termination from any stream
    all_queries = weather_queries + forecast_queries + air_realtime_queries + air_forecast_queries + air_summary_queries

    for q in all_queries:
        q.awaitTermination()


if __name__ == "__main__":
    main()
