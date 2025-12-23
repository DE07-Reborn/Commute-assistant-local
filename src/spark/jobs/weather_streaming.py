from spark.utils.spark_utils import Spark_utils
from spark.utils.book_recommender import BookRecommender
import logging

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("weather-forecast-streaming")

def run_weather_stream(spark_utils, spark):
    """
        The topic is received data every 10 minutes about 6hours 
        weather forecast
    """

    log.info("Initializing weather stream...")

    # Read Kafka
    raw_weather = spark_utils.read_kafka_topic(spark, 'hourly_weather_raw')

    # Preprocess
    df_weather = spark_utils.preprocessing_kma_weather(raw_weather)

    # Recommend eBook
    br = BookRecommender(
        spark=spark,
        bucket=spark_utils.bucket
    )
    df_with_recommendation = br.add_recommendation(df_weather)

    # Redis Sink
    df_with_recommendation_redis = df_with_recommendation.repartition(1)
    redis_checkpoint = f"s3a://{spark_utils.bucket}/kma-weather/_checkpoint_redis"
    redis_query = (
        df_with_recommendation.writeStream
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
        Hourly(00:05) planned live climate data
    """

    log.info("Initializing forecast stream...")

    # Read Kafka
    raw_forecast = spark_utils.read_kafka_topic(spark, '10min_forecast_raw')

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


def main():
    spark_utils = Spark_utils()
    spark = spark_utils.get_spark("weather_streaming_app")

    log.info("Starting weather + forecast streams...")

    # Start both streaming pipelines
    weather_queries = run_weather_stream(spark_utils, spark)
    forecast_queries = run_forecast_stream(spark_utils, spark)

    # Wait for termination from any stream
    all_queries = weather_queries + forecast_queries

    for q in all_queries:
        q.awaitTermination()


if __name__ == "__main__":
    main()
