from spark.utils.spark_utils import Spark_utils
import logging

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("weather-streaming")

def main():
    spark_utils = Spark_utils()
    spark = spark_utils.get_spark("kma_hourly_weather")

    # read recent data from kafka topic : batch
    raw_data = spark_utils.read_kafka_topic(spark, 'hourly_weather_raw')

    # Preprocessing the data to data frame
    df = spark_utils.preprocessing_kma_weather(raw_data)


    # 음악 / 도서 추천 알고리즘
    ## 여기 추가 예정

    # send to Redis (Update by key:stn_id) within partition(1)
    df_redis = df.repartition(1)
    redis_checkpoint = f"s3a://{spark_utils.bucket}/kma-weather/_checkpoint_redis"    
    (
        df_redis.writeStream
        .foreachBatch(spark_utils.save_batch_to_redis)
        .outputMode("append")
        .option("checkpointLocation", redis_checkpoint)
        .start()
    )

    # save to S3
    s3_checkpoint = f"s3a://{spark_utils.bucket}/kma-weather/_checkpoint_s3"
    (
        df.writeStream
        .foreachBatch(spark_utils.save_batch_to_s3)
        .outputMode("append")
        .option("checkpointLocation", s3_checkpoint)
        .start()
    )
    log.info("------------S3 stream started-------------")


    log.info("Weather streaming started. Waiting termination...")
    spark.streams.awaitAnyTermination()

if __name__ == "__main__":
    main()