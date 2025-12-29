from spark.utils.spark_utils import Spark_utils
from spark.utils.book_recommender import BookRecommender
from pyspark.sql.functions import broadcast

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

    # Redis Sink
    redis_checkpoint = f"s3a://{spark_utils.bucket}/kma-weather/_checkpoint_redis"
    redis_query = (
        df_with_recommendation
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
        df_with_recommendation.writeStream
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
    air_realtime_df = spark_utils.preprocessing_air_quality(air_realtime_raw)

    air_redis_checkpoint = f"s3a://{spark_utils.bucket}/air-quality/_checkpoint_redis"
    air_redis_query = (
        air_realtime_df
        .repartition(1)
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_redis_air)
        .outputMode("append")
        .option("checkpointLocation", air_redis_checkpoint)
        .start()
    )

    air_s3_checkpoint = f"s3a://{spark_utils.bucket}/air-quality/_checkpoint_s3"
    air_s3_query = (
        air_realtime_df
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_s3_air)
        .outputMode("append")
        .option("checkpointLocation", air_s3_checkpoint)
        .start()
    )

    log.info("Air-realtime streaming started.")
    return [air_redis_query, air_s3_query]

def main():
    spark_utils = Spark_utils()
    spark = spark_utils.get_spark("weather_streaming_app")

    log.info("Starting weather + forecast + air-realtime streams...")

    # read music df
    music_df = spark_utils.get_music_data(spark)

    # Start both streaming pipelines
    weather_queries = run_weather_stream(spark_utils, spark, music_df)
    forecast_queries = run_forecast_stream(spark_utils, spark)
    air_realtime_queries = run_air_realtime_stream(spark_utils, spark)

    # Wait for termination from any stream
    all_queries = weather_queries + forecast_queries + air_realtime_queries

    for q in all_queries:
        q.awaitTermination()


if __name__ == "__main__":
    main()
