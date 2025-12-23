import os
import boto3
import logging
import io
import pandas as pd


class S3_utils:
    """
        Common S3 utils using boto3.
    """

    def __init__(self, ymd, hm):
        """
            Initialize S3_util class
            param
                ymd : Year-Month-Day format 
                hm : HourMinute format

            ymd and hm will be used to determine S3 folder and file names
        """
        self.ymd = ymd
        self.hm = hm
        self.bucket = os.getenv('AWS_S3_BUCKET')

        aws_key_id = os.getenv("AWS_ACCESS_KEY_ID")
        aws_secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
        aws_region = os.getenv("AWS_REGION", "ap-northeast-2")

        self.s3 = boto3.client(
            "s3",
            aws_access_key_id = aws_key_id,
            aws_secret_access_key = aws_secret_key,
            region_name = aws_region,
        )

    
    def upload_stn_metadata(self, df):
        """
            Upload stn metadata into s3
            param
                df : stn meta data frame
        """

        try:
            df_csv = df.to_csv(index=False)
            buffer = io.BytesIO(df_csv.encode('utf-8'))
            key = 'stn-metadata/metadata.csv'

            self._put_object(buffer, key)
        except Exception as e:
            raise Exception(f'Error has occured uploading stn metadata: {e}')



    # Upload
    def _put_object(self, buffer, key):
        """
            Methods put data(buffer) in S3
            param
                buffer : data buffered
                key : path to file with file name
        """

        logging.info('Uploading data into s3 in progress')
        logging.info(f'Uploading to S3 s3://{self.bucket}/{key}')
        buffer.seek(0)

        self.s3.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=buffer.getvalue()
        )

    # Read Address-coord meta data
    def read_address(self):
        obj = self.s3.get_object(
            Bucket=self.bucket,
            Key="address-coord/coordinate_meta.csv"
        )
        body = obj["Body"].read().decode("utf-8")
        df = pd.read_csv(io.StringIO(body))
        return df