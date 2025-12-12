# Credential
import os
import boto3
import logging

# dataframes
import pyarrow.dataset as ds
import pandas as pd
import pyarrow as pa
import io
import json

class s3_util:
    """
        Common S3 Utility using boto3.
        This utility works for Airflow, Spark, Kafka, or any Python environment.
    """

    def __init__(self, ymd, hm, bucket = None):
        """
            Initialize S3_util class
            param
                ymd : Year-Month-Day format 
                hm : HourMinute format
                bucket : S3 bucket name

            ymd and hm will be used to determine S3 folder and file names
        """
        self.ymd = ymd
        self.hm = hm
        self.bucket = bucket or os.getenv('AWS_S3_BUCKET')

        aws_key_id = os.getenv("AWS_ACCESS_KEY_ID")
        aws_secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
        aws_region = os.getenv("AWS_REGION", "ap-northeast-2")

        self.s3 = boto3.client(
            "s3",
            aws_access_key_id = aws_key_id,
            aws_secret_access_key = aws_secret_key,
            region_name = aws_region,
        )



    # Methods
    # Read Dataset From S3
    def read(self, path, input_type = 'parquet', return_type = 'pandas_df'):
        """
            Read and return Dataset from S3
            
            param
                path : The key of stored data
                input_type : The format type of input data
                    [json, csv, parquet (default)]
                return_type : The format type of returned dataset
                    [pandas_df (default), arrow_table]
        """
        
        # Check input data type
        supported_formats = ['parquet', 'json', 'csv']
        input_fmt = input_type.lower()

        if input_fmt not in supported_formats:
            logging.info(f'Input Type not supported : {input_type}. '
                        f'Should be one of {supported_formats}')
            raise ValueError(f"Unsupported input type: {input_type}")

        # get read all data within path and format
        if input_fmt == "json":
            return self._read_json(path, return_type)

        s3_uri = f"s3://{self.bucket}/{path}"
        dataset = ds.dataset(
            s3_uri,
            format=input_fmt
        )

        table = dataset.to_table()

        # Return dataset based on return type
        if return_type == 'pandas_df':
            return table.to_pandas()
        
        elif return_type == 'arrow_table':
            return table
        
        else:
            logging.info(
                f'Return Type not supported : {return_type}. '
                f'Should be arrow_table or spark_df'
            )
            raise ValueError(f"Unsupported return type: {return_type}")



    def _read_json(self, path, return_type):
        obj = self.s3.get_object(Bucket=self.bucket, Key=path)
        body = obj["Body"].read().decode("utf-8")
        data = json.loads(body)

        # pandas dataframe
        if return_type == "pandas_df":
            if isinstance(data, dict):
                return pd.json_normalize([data])
            elif isinstance(data, list):
                return pd.json_normalize(data)
            else:
                logging.info("Cannot convert format fit to pandas_df")
                raise ValueError("Cannot convert format fit to pandas_df")

        # arrow table
        if return_type == "arrow_table":
            if isinstance(data, dict):
                data = [data]
            return pa.Table.from_pylist(data)

        raise ValueError(f"Unsupported return type for JSON: {return_type}")



    # Upload dataset into S3
    def upload(self, data, folder, format = 'auto'):
        """
            Upload data into S3 with following format
            param
                data : The Data willing to upload
                format : The format of data 
                    [auto (default), csv, json, parquet]
                folder : name of folder
        """

        # To clarify the data itself
        if isinstance(data, pd.DataFrame):
            return self._upload_pandas(data, format, folder)

        elif isinstance(data, (dict, list, str)):
            return self._upload_json(data, folder)

        else:
            logging.info(f'Unsupported data type : {type(data)}')
            raise ValueError(f"Unsupported data type: {type(data)}")



    def _upload_pandas(self, df, format, folder):
        """
            Methods for Data known as pandas data frame
            param 
                df : The dataset 
                format : The format of data 
                    [auto (default), csv, json, parquet]
                folder : name of folder
        """

        # Check Format
        if format == 'auto':
            format = 'parquet'

        key = f'{folder}/{self.ymd}/{self.hm}.{format}'

        buffer = io.BytesIO()

        if format == 'parquet':
            df.to_parquet(buffer, index=False, engine="pyarrow", compression="snappy")

        elif format == 'csv':
            csv_str = df.to_csv(index=False)
            buffer = io.BytesIO(csv_str.encode('utf-8'))

        else:
            logging.info(f'Unsupported pandas format: {format}')
            raise ValueError('Unsupported pandas format')
        
        # Load into S3
        return self._put_object(buffer, key)



    def _upload_json(self, data, folder):
        """
            Methods for Data known as [dict, list, str]
            param 
                data : The data
                folder : name of folder
        """

        key = f'{folder}/{self.ymd}/{self.hm}.json'

        if isinstance(data, str):
            json_str = data
            
        else:
            json_str = json.dumps(data, ensure_ascii=False)

        buffer = io.BytesIO(json_str.encode('utf-8'))
        
        # Load into S3
        return self._put_object(buffer, key)


    # Upload
    def _put_object(self, buffer, key):
        """
            Methods put data(buffer) in S3
            param
                buffer : data buffered
                key : path to file
        """

        logging.info('Uploading data into s3 in progress')
        logging.info(f'Uploading to S3 s3://{self.bucket}/{key}')
        buffer.seek(0)

        response = self.s3.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=buffer.getvalue()
        )

        return response