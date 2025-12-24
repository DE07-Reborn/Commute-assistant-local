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

    air_realtime_raw = spark_utils.read_kafka_topic(
        spark, "air-quality-realtime"
    )
    air_realtime_df = spark_utils.preprocessing_air_quality(air_realtime_raw)

    # 음악 / 도서 추천 알고리즘
    ## 여기 추가 예정

    # 날씨 데이터를 토대로 이에 맞는 음악 리스트, 날씨코드가 결합된 형태의 데이터프레임 반환
    # [{"artists":artists, "album_name":album_name, "track_name":track_name}, ...]의 딕셔너리 리스트 형태로 구성되어 있어
    # 이대로 paquet으로 저장하면 내용물은 보이지 않고 object로만 표시됨
    music_s3_path = 'raw_data/music/music_classified.parquet'
    df = spark_utils.weather_to_class(session=spark, file_path=music_s3_path, weather_df=df)
    # 최종 결과 데이터프레임. 이후 작업은 이 df로 진행하시면 됩니다
    df

    # send to Redis (Update by key:stn_id) within partition
    # Redis문제 해결 해야해요
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
    air_redis_checkpoint = f"s3a://{spark_utils.bucket}/air-quality/_checkpoint_redis"
    (
        air_realtime_df
        .repartition(1)
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_redis_air)
        .outputMode("append")
        .option("checkpointLocation", air_redis_checkpoint)
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

    air_s3_checkpoint = f"s3a://{spark_utils.bucket}/air-quality/_checkpoint_s3"
    (
        air_realtime_df
        .writeStream
        .foreachBatch(spark_utils.save_batch_to_s3_air)
        .outputMode("append")
        .option("checkpointLocation", air_s3_checkpoint)
        .start()
    )

    log.info("Weather streaming started. Waiting termination...")
    spark.streams.awaitAnyTermination()

if __name__ == "__main__":
    main()