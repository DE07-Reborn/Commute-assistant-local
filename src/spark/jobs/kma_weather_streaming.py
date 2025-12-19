from spark.utils.spark_utils import Spark_utils
import logging

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("weather-streaming")

def main():
    spark_utils = Spark_utils()
    spark = spark_utils.get_spark("kma_hourly_weather")
    
    checkpoint = "kma-weather/_checkpoint"
    s3_folder = "kma-weather/hourly-data"

    # read recent data from kafka topic : batch
    raw_data = spark_utils.read_kafka_topic(spark, 'hourly_weather_raw')

    # Preprocessing the data to data frame
    df = spark_utils.preprocessing_kma_weather(raw_data)


    # 음악 / 도서 추천 알고리즘
    ## 여기 추가 예정

    # send to Redis (Update by key:stn_id) within partition
    # Redis문제 해결 해야해요
    (
        df.writeStream
        .foreachBatch(
            lambda batch_df, batch_id: 
                spark_utils.write_df_to_redis(
                    batch_df
                )
        )
        .outputMode("append")
        .option("checkpointLocation", "kma-weather/_checkpoint_redis")
        .start()
    )

    # save to S3
    spark_utils.save_to_s3(df, s3_folder, checkpoint)


    log.info("Weather streaming started. Waiting termination...")
    spark.streams.awaitAnyTermination()

if __name__ == "__main__":
    main()