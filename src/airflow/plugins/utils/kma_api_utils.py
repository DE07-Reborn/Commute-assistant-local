# data frame
from collections import defaultdict
import pandas as pd

# API Request
import requests

# Util
import os
import logging

class kma_api_collector:
    """
        Request API from KMA apihub to collect STN info metadata
        Request API from KMA apihub to collect daily or time range weather/climate data
    """

    def __init__(self, ymd, hm):
        """
            Initialize api collector
            param
                ymd : Year-Month-day
                hm : HourMinute
        """
        self.ymd = ymd.replace('-','')
        self.hm = hm

        # Api key
        self.key = os.getenv("KMA_KEY")
        if not self.key:
            raise EnvironmentError("KMA_KEY is not set in environment variables")
        
        # Default timeout 
        self.base_timeout = 10



    # Methods
    def request_stn_metadata(self):
        """
            Request meta data of stn_inf
            This data will be updated within 6 months
        """
        stn_url = 'https://apihub.kma.go.kr/api/typ01/url/stn_inf.php'
        stn_params = {
            'tm' : self.ymd+self.hm,
            'help' : 0,
            'authKey' : self.key
        }

        # The data will be collected by each columns then converted to pd.dataFrame
        stn_meta_can = defaultdict(list)

        # Request API
        try:
            response = requests.get(stn_url, params=stn_params, timeout=self.base_timeout)
            
            # Check api status
            response.raise_for_status()
            
            logging.info('Success to request API')

            # Append each rows into meta can by column
            for data in response.text.splitlines():
                # Check not metadata
                if not data.startswith('#'):
                    splited = data.split()
                    stn_meta_can['STN_ID'].append(int(splited[0]))
                    stn_meta_can['경도'].append(float(splited[1]))
                    stn_meta_can['위도'].append(float(splited[2]))
                    stn_meta_can['STN_SP'].append(int(splited[3]))
                    stn_meta_can['지역'].append(splited[10])

            if not stn_meta_can:
                raise ValueError("KMA API returned empty station metadata")

            # Convert to Pandas data frame
            df = pd.DataFrame(stn_meta_can)
            return df

        except requests.Timeout:
            logging.error('KMA API request timeout')
            raise

        except requests.HTTPError as exc:
            logging.error(f"KMA API HTTP error: {exc}")
            raise

        except Exception as e:
            logging.exception("Unexpected error caught while requesting KMA API")
            raise



    def request_daily_weather(self, stn=None):
        """
            Reqeust API from KMA apihub to collect daily weather data with STN
            param
                stn : the stn number of specific city or place location
        """
        weather_url = 'https://apihub.kma.go.kr/api/typ01/url/kma_sfcdd.php'
        weather_params = {
            'tm' : self.ymd,
            'stn' : stn if stn else '',
            'disp' : 0,
            'help' : 0,
            'authKey' : self.key
        }

        # The data will be collected by each columns then converted to pd.dataFrame
        weather_can = defaultdict(list)

        # List for parameters
        parameters = ['관측일', 'STN', '평균풍속', '풍정', '최대풍향', '최대풍속', '최대풍속_시각', '최대순간풍향',
            '최대순간풍속', '최대순간풍속_시각', '평균기온', '최고기온', '최고기온_시각',
            '최저기온', '최저기온_시각', '평균_이슬점온도', '평균_지면온도', '최저_초상온도', '평균_상대습도',
            '최저습도', '최저습도_시각', '평균_수증기압', '소형_증발량', '대형_증발량', '안개계속시간',
            '평균_현지기압', '평균_해면기압', '최고_해면기압', '최고_해면기압_시각', '최저_해면기압',
            '최저_해면기압_시각', '평균_전운량', '일조합', '가조시간', '캄벨_일조', '일사합', '최대_1시간일사',
            '최대_1시간일사_시각', '강수량', '99강수량', '강수계속시간', '1시간_최다강수량', '1시간_최다강수량_시각',
            '10분간_최다강수량', '10분간_최다강수량_시각', '최대_강우강도', '최대_강우강도_시각', '최심_신적설', '최심_신적설_시각',
            '최심_적설', '최심_적설_시각', '05지중온도', '10지중온도', '15지중온도', '30지중온도', '50지중온도']

        # Request API
        try:
            response = requests.get(weather_url, params=weather_params, 
                                    timeout=self.base_timeout)
            
            # Check api status
            response.raise_for_status()
            logging.info('Success to request API')

            # Append each rows into meta can by column
            for data in response.text.splitlines():
                # Check not metadata
                if not data.startswith('#'):
                    splited = data.split()
                    for i, param in enumerate(parameters):
                        weather_can[param].append(splited[i]) 

            if not weather_can:
                raise ValueError("KMA API returned empty weather data")

            # Convert to Pandas data frame
            df = pd.DataFrame(weather_can)
            return df

        except requests.Timeout:
            logging.error('KMA API request timeout')
            raise

        except requests.HTTPError as exc:
            logging.error(f"KMA API HTTP error: {exc}")
            raise

        except Exception as e:
            logging.exception("Unexpected error caught while requesting KMA API")
            raise
